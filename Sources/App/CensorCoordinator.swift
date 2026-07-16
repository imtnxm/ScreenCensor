import AppKit
import Combine
import CoreVideo
import Foundation
import QuartzCore
import ScreenCaptureKit

@MainActor
final class CensorCoordinator: ObservableObject {
    @Published private(set) var framesProcessed: UInt64 = 0
    @Published private(set) var framesDropped: UInt64 = 0
    @Published private(set) var activeDetectionCount = 0
    @Published private(set) var lastError: String?
    @Published private(set) var modelLoaded = false
    @Published private(set) var captureFPS: Double = 0
    @Published private(set) var renderFPS: Double = 0
    @Published private(set) var inferenceFPS: Double = 0
    @Published private(set) var usingGPUFallback = false
    @Published private(set) var availableDisplays: [DisplayInfo] = []

    private let captureManager = ScreenCaptureManager()
    private let detectionEngine = DetectionEngine()

    private var configuration = CensorConfiguration()
    private var isRunning = false
    private var runtimes: [CGDirectDisplayID: DisplayRuntime] = [:]

    private var captureCount = 0
    private var renderCount = 0
    private var inferenceCount = 0
    private var metricsStart = CACurrentMediaTime()

    private var screenObserver: NSObjectProtocol?

    init() {
        captureManager.delegate = self
        modelLoaded = detectionEngine.modelLoaded
        refreshDisplays()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDisplays()
                if self?.isRunning == true {
                    try? await self?.restartCapture()
                }
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func refreshDisplays() {
        availableDisplays = DisplayCatalog.current()
    }

    func start(configuration: CensorConfiguration) async throws {
        self.configuration = configuration
        detectionEngine.updateConfiguration(configuration)
        refreshDisplays()
        modelLoaded = detectionEngine.modelLoaded

        teardownRuntimes()
        let enabled = enabledDisplayIDSet()
        for display in availableDisplays where enabled.contains(display.id) {
            let runtime = DisplayRuntime(display: display, configuration: configuration)
            runtime.show()
            runtimes[display.displayID] = runtime
            if runtime.usingGPUFallback { usingGPUFallback = true }
        }

        let windowIDs = Set(runtimes.values.map(\.windowID))
        do {
            try await captureManager.start(
                displays: availableDisplays,
                enabledDisplayIDs: enabled,
                excludingWindowIDs: windowIDs
            )
            isRunning = true
            lastError = nil
        } catch {
            await stop()
            lastError = error.localizedDescription
            throw error
        }
    }

    func stop() async {
        isRunning = false
        await captureManager.stop()
        teardownRuntimes()
        activeDetectionCount = 0
        captureFPS = 0
        renderFPS = 0
        inferenceFPS = 0
    }

    func updateConfiguration(_ configuration: CensorConfiguration) {
        let modeChanged = configuration.performanceMode != self.configuration.performanceMode
        let displaysChanged = configuration.displays != self.configuration.displays
        self.configuration = configuration
        detectionEngine.updateConfiguration(configuration)
        for runtime in runtimes.values {
            runtime.updateConfiguration(configuration)
        }
        guard isRunning, modeChanged || displaysChanged else { return }
        Task { try? await restartCapture() }
    }

    private func restartCapture() async throws {
        refreshDisplays()
        let enabled = enabledDisplayIDSet()
        // Rebuild runtimes for newly enabled displays
        for display in availableDisplays where enabled.contains(display.id) && runtimes[display.displayID] == nil {
            let runtime = DisplayRuntime(display: display, configuration: configuration)
            runtime.show()
            runtimes[display.displayID] = runtime
        }
        for id in Array(runtimes.keys) where !enabled.contains(UInt32(id)) {
            runtimes[id]?.hide()
            runtimes.removeValue(forKey: id)
        }
        let windowIDs = Set(runtimes.values.map(\.windowID))
        try await captureManager.restartIfNeeded(
            displays: availableDisplays,
            enabledDisplayIDs: enabled,
            excludingWindowIDs: windowIDs
        )
    }

    private func enabledDisplayIDSet() -> Set<UInt32> {
        let available = Set(availableDisplays.map(\.id))
        if configuration.displays.enabledDisplayIDs.isEmpty {
            return available
        }
        return Set(configuration.displays.enabledDisplayIDs).intersection(available)
    }

    private func teardownRuntimes() {
        for runtime in runtimes.values {
            runtime.hide()
        }
        runtimes.removeAll()
    }

    private func handle(frame: CapturedFrame) {
        guard isRunning else { return }
        captureCount += 1
        noteMetrics()

        guard let runtime = runtimes[frame.displayID] else { return }
        runtime.publish(frame)

        Task { [weak self] in
            guard let self else { return }
            do {
                if let detections = try await detectionEngine.process(frame) {
                    await MainActor.run {
                        self.inferenceCount += 1
                        self.framesProcessed = self.detectionEngine.processedFrameCount
                        self.framesDropped = self.detectionEngine.droppedFrameCount
                        self.modelLoaded = self.detectionEngine.modelLoaded
                        runtime.ingest(detections: detections, configuration: self.configuration)
                        self.activeDetectionCount = self.runtimes.values.reduce(0) { $0 + $1.activeCount }
                    }
                } else {
                    await MainActor.run {
                        self.framesDropped = self.detectionEngine.droppedFrameCount
                        runtime.renderPredicted()
                        self.renderCount += 1
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                }
            }
        }

        // Always try a display-refresh style render from latest mailbox + tracker prediction.
        runtime.renderPredicted()
        renderCount += 1
    }

    private func noteMetrics() {
        let now = CACurrentMediaTime()
        let elapsed = now - metricsStart
        if elapsed >= 1 {
            captureFPS = Double(captureCount) / elapsed
            renderFPS = Double(renderCount) / elapsed
            inferenceFPS = Double(inferenceCount) / elapsed
            captureCount = 0
            renderCount = 0
            inferenceCount = 0
            metricsStart = now
        }
    }
}

extension CensorCoordinator: ScreenCaptureManagerDelegate {
    nonisolated func screenCaptureManager(_ manager: ScreenCaptureManager, didOutput frame: CapturedFrame) {
        Task { @MainActor in
            self.handle(frame: frame)
        }
    }

    nonisolated func screenCaptureManager(
        _ manager: ScreenCaptureManager,
        displayID: CGDirectDisplayID,
        didFail error: Error
    ) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
        }
    }
}

// MARK: - Per-display runtime

@MainActor
final class DisplayRuntime {
    let display: DisplayInfo
    private let overlay: OverlayWindowController
    private let tracker = RegionTracker()
    private let mailbox = LatestFrameMailbox()
    private var configuration: CensorConfiguration
    private var latestGeometry: FrameGeometry?
    private(set) var activeCount = 0

    init(display: DisplayInfo, configuration: CensorConfiguration) {
        self.display = display
        self.configuration = configuration
        overlay = OverlayWindowController(display: display)
        tracker.updateSettings(TrackerSettings(motion: configuration.motion))
    }

    var windowID: CGWindowID { overlay.windowID }
    var usingGPUFallback: Bool { overlay.usingGPUFallback }

    func show() { overlay.show() }
    func hide() {
        overlay.hide()
        tracker.reset()
        activeCount = 0
    }

    func updateConfiguration(_ configuration: CensorConfiguration) {
        self.configuration = configuration
        tracker.updateSettings(TrackerSettings(motion: configuration.motion))
    }

    func publish(_ frame: CapturedFrame) {
        mailbox.publish(frame)
        latestGeometry = frame.geometry
    }

    func ingest(detections: FrameDetections, configuration: CensorConfiguration) {
        self.configuration = configuration
        latestGeometry = detections.geometry
        mailbox.publish(CapturedFrame(
            displayID: detections.displayID,
            timestamp: detections.timestamp,
            pixelBuffer: detections.pixelBuffer,
            geometry: detections.geometry
        ))

        let inputs: [TrackerInput] = detections.results.map { det in
            let padded = PartRuleEngine.paddedRect(
                det.normalizedRect,
                part: det.part,
                configuration: configuration
            )
            return TrackerInput(
                part: det.part,
                normalizedRect: padded,
                confidence: det.confidence,
                effect: PartRuleEngine.effect(for: det.part, configuration: configuration)
            )
        }
        let tracked = tracker.update(detections: inputs, now: CACurrentMediaTime())
        present(tracked: tracked, geometry: detections.geometry, pixelBuffer: detections.pixelBuffer)
    }

    func renderPredicted() {
        guard let frame = mailbox.peek(), let geometry = latestGeometry ?? Optional(frame.geometry) else {
            return
        }
        let tracked = tracker.predicted(at: CACurrentMediaTime())
        present(tracked: tracked, geometry: geometry, pixelBuffer: frame.pixelBuffer)
    }

    private func present(tracked: [TrackedInternal], geometry: FrameGeometry, pixelBuffer: CVPixelBuffer) {
        let regions: [TrackedRegion] = tracked.map {
            TrackedRegion(
                id: $0.id,
                part: $0.part,
                displayID: display.displayID,
                localRect: geometry.overlayLocalRect(fromVisionNormalized: $0.normalizedRect),
                normalizedRect: $0.normalizedRect,
                confidence: $0.confidence,
                effect: $0.effect
            )
        }
        activeCount = regions.count
        overlay.render(pixelBuffer: pixelBuffer, geometry: geometry, regions: regions)
    }
}
