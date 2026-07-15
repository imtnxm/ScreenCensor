import AppKit
import Combine
import CoreVideo
import Foundation
import QuartzCore
import ScreenCaptureKit

@MainActor
final class CensorCoordinator: ObservableObject {
    @Published private(set) var framesProcessed: UInt64 = 0
    @Published private(set) var activeDetectionCount = 0
    @Published private(set) var lastError: String?
    @Published private(set) var modelLoaded = false
    @Published private(set) var measuredFPS: Double = 0

    private let overlay = OverlayWindowController()
    private let captureManager = ScreenCaptureManager()
    private let detectionEngine = DetectionEngine()

    private var configuration = CensorConfiguration()
    private var isRunning = false
    private var tracks: [TrackKey: TrackState] = [:]
    private var fpsWindowStart = CACurrentMediaTime()
    private var fpsFrameCount = 0

    init() {
        captureManager.delegate = self
        modelLoaded = detectionEngine.modelLoaded
    }

    func start(configuration: CensorConfiguration) async throws {
        self.configuration = configuration
        detectionEngine.updateConfiguration(configuration)
        captureManager.updateConfiguration(configuration)
        overlay.show()
        modelLoaded = detectionEngine.modelLoaded

        do {
            try await captureManager.start(excludingWindowID: overlay.windowID)
            isRunning = true
            lastError = nil
        } catch {
            overlay.hide()
            isRunning = false
            lastError = error.localizedDescription
            throw error
        }
    }

    func stop() async {
        isRunning = false
        await captureManager.stop()
        overlay.hide()
        tracks.removeAll()
        activeDetectionCount = 0
        measuredFPS = 0
    }

    func updateConfiguration(_ configuration: CensorConfiguration) {
        let performanceChanged = configuration.performanceMode != self.configuration.performanceMode
        self.configuration = configuration
        detectionEngine.updateConfiguration(configuration)
        captureManager.updateConfiguration(configuration)

        guard isRunning, performanceChanged else { return }
        Task {
            do {
                try await captureManager.restartIfNeeded()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func handle(pixelBuffer: CVPixelBuffer) {
        guard isRunning else { return }

        let displaySize = overlayDisplaySize()
        overlay.updateFrameContext(pixelBuffer: pixelBuffer, displaySize: displaySize)

        Task { [weak self] in
            guard let self else { return }
            do {
                guard let frame = try await detectionEngine.process(
                    pixelBuffer: pixelBuffer,
                    displaySize: displaySize
                ) else {
                    await MainActor.run {
                        self.renderCoastingOnly()
                    }
                    return
                }

                await MainActor.run {
                    self.apply(frame: frame)
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private func apply(frame: FrameDetections) {
        framesProcessed = detectionEngine.processedFrameCount
        modelLoaded = detectionEngine.modelLoaded
        overlay.updateFrameContext(pixelBuffer: frame.pixelBuffer, displaySize: frame.displaySize)
        noteFPS()

        let now = CACurrentMediaTime()
        let smoothing = configuration.motion.smoothing
        let coast = configuration.motion.coastSeconds

        var claimed = Set<TrackKey>()
        var unmatched = tracks

        for detection in frame.results {
            let padded = PartRuleEngine.paddedRect(
                detection.normalizedRect,
                part: detection.part,
                configuration: configuration
            )
            let screenRect = CoordinateMapper.screenRect(
                fromVisionNormalized: padded,
                displaySize: frame.displaySize
            )
            let effect = PartRuleEngine.effect(for: detection.part, configuration: configuration)

            var bestKey: TrackKey?
            var bestIoU: CGFloat = 0.12
            for (key, state) in unmatched where key.part == detection.part {
                let score = iou(screenRect, state.rect)
                if score > bestIoU {
                    bestIoU = score
                    bestKey = key
                }
            }

            let key = bestKey ?? TrackKey(id: detection.id, part: detection.part)
            if let bestKey { unmatched.removeValue(forKey: bestKey) }

            let previous = tracks[key]?.rect
            let blended: CGRect
            if let previous {
                blended = CGRect(
                    x: lerp(previous.origin.x, screenRect.origin.x, smoothing),
                    y: lerp(previous.origin.y, screenRect.origin.y, smoothing),
                    width: lerp(previous.width, screenRect.width, smoothing),
                    height: lerp(previous.height, screenRect.height, smoothing)
                )
            } else {
                blended = screenRect
            }

            tracks[key] = TrackState(
                rect: blended,
                confidence: detection.confidence,
                effect: effect,
                lastSeen: now
            )
            claimed.insert(key)
        }

        // Coast stale tracks briefly
        for (key, state) in tracks {
            if claimed.contains(key) { continue }
            if now - state.lastSeen > coast {
                tracks.removeValue(forKey: key)
            }
        }

        let regions: [TrackedRegion] = tracks.map { key, state in
            TrackedRegion(
                id: key.id,
                part: key.part,
                screenRect: state.rect,
                confidence: state.confidence,
                effect: state.effect
            )
        }

        activeDetectionCount = regions.count
        overlay.render(regions: regions)
    }

    private func renderCoastingOnly() {
        let now = CACurrentMediaTime()
        let coast = configuration.motion.coastSeconds
        tracks = tracks.filter { now - $0.value.lastSeen <= coast }
        let regions: [TrackedRegion] = tracks.map { key, state in
            TrackedRegion(
                id: key.id,
                part: key.part,
                screenRect: state.rect,
                confidence: state.confidence,
                effect: state.effect
            )
        }
        activeDetectionCount = regions.count
        overlay.render(regions: regions)
    }

    private func noteFPS() {
        fpsFrameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - fpsWindowStart
        if elapsed >= 1.0 {
            measuredFPS = Double(fpsFrameCount) / elapsed
            fpsFrameCount = 0
            fpsWindowStart = now
        }
    }

    private func overlayDisplaySize() -> CGSize {
        NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull && !intersection.isEmpty else { return 0 }
        let interArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        guard unionArea > 0 else { return 0 }
        return interArea / unionArea
    }
}

extension CensorCoordinator: ScreenCaptureManagerDelegate {
    nonisolated func screenCaptureManager(_ manager: ScreenCaptureManager, didOutput pixelBuffer: CVPixelBuffer) {
        Task { @MainActor in
            self.handle(pixelBuffer: pixelBuffer)
        }
    }

    nonisolated func screenCaptureManager(_ manager: ScreenCaptureManager, didFail error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
        }
    }
}

private struct TrackKey: Hashable {
    let id: UUID
    let part: BodyPartID
}

private struct TrackState {
    var rect: CGRect
    var confidence: Float
    var effect: EffectPreset
    var lastSeen: CFTimeInterval
}

enum CoordinateMapper {
    static func screenRect(fromVisionNormalized rect: CGRect, displaySize: CGSize) -> CGRect {
        CGRect(
            x: rect.origin.x * displaySize.width,
            y: rect.origin.y * displaySize.height,
            width: rect.size.width * displaySize.width,
            height: rect.size.height * displaySize.height
        )
    }
}
