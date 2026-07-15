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

    private let overlay = OverlayWindowController()
    private let captureManager = ScreenCaptureManager()
    private let detectionEngine = DetectionEngine()

    private var configuration = CensorConfiguration()
    private var isRunning = false
    private var smoothedRects: [UUID: SmoothedRect] = [:]
    private let smoothingFactor: CGFloat = 0.35

    init() {
        captureManager.delegate = self
    }

    func start(configuration: CensorConfiguration) async throws {
        self.configuration = configuration
        detectionEngine.updateConfiguration(configuration)
        captureManager.updateConfiguration(configuration)
        overlay.updateStyle(configuration.style, text: configuration.censorText)
        overlay.show()

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
        smoothedRects.removeAll()
        activeDetectionCount = 0
    }

    func updateConfiguration(_ configuration: CensorConfiguration) {
        let performanceChanged = configuration.performanceMode != self.configuration.performanceMode
        self.configuration = configuration
        detectionEngine.updateConfiguration(configuration)
        captureManager.updateConfiguration(configuration)
        overlay.updateStyle(configuration.style, text: configuration.censorText)

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
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let frame = try await detectionEngine.process(
                    pixelBuffer: pixelBuffer,
                    displaySize: displaySize
                ) else {
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

        let filtered = frame.results.filter { result in
            switch result.kind {
            case .face, .faceLandmarks:
                return configuration.targets.face
            case .skin:
                return configuration.targets.skin
            case .intimateZone:
                return configuration.targets.intimateZones
            }
        }

        let screenItems: [(id: UUID, rect: CGRect)] = filtered.map { result in
            let screenRect = CoordinateMapper.screenRect(
                fromVisionNormalized: result.normalizedRect,
                displaySize: frame.displaySize
            )
            return (result.id, screenRect)
        }

        // Match detections across frames by IoU, then smooth to reduce jitter.
        let stabilized = stabilizeIdentities(screenItems)
        activeDetectionCount = stabilized.count
        overlay.render(screenRects: stabilized)

        pruneSmoothedRects(keeping: Set(stabilized.map(\.id)))
    }

    private func smooth(id: UUID, rect: CGRect) -> CGRect {
        if let previous = smoothedRects[id] {
            let blended = CGRect(
                x: lerp(previous.rect.origin.x, rect.origin.x, smoothingFactor),
                y: lerp(previous.rect.origin.y, rect.origin.y, smoothingFactor),
                width: lerp(previous.rect.width, rect.width, smoothingFactor),
                height: lerp(previous.rect.height, rect.height, smoothingFactor)
            )
            smoothedRects[id] = SmoothedRect(rect: blended, lastSeen: CACurrentMediaTime())
            return blended
        }

        smoothedRects[id] = SmoothedRect(rect: rect, lastSeen: CACurrentMediaTime())
        return rect
    }

    private func stabilizeIdentities(
        _ items: [(id: UUID, rect: CGRect)]
    ) -> [(id: UUID, rect: CGRect)] {
        // Match new detections to previous smoothed rects by IoU to reduce flicker from fresh UUIDs.
        var available = smoothedRects
        var output: [(id: UUID, rect: CGRect)] = []

        for item in items {
            var bestID: UUID?
            var bestIoU: CGFloat = 0.15

            for (candidateID, candidate) in available {
                let score = iou(item.rect, candidate.rect)
                if score > bestIoU {
                    bestIoU = score
                    bestID = candidateID
                }
            }

            if let bestID {
                available.removeValue(forKey: bestID)
                let smoothed = smooth(id: bestID, rect: item.rect)
                output.append((bestID, smoothed))
            } else {
                let smoothed = smooth(id: item.id, rect: item.rect)
                output.append((item.id, smoothed))
            }
        }

        return output
    }

    private func pruneSmoothedRects(keeping ids: Set<UUID>) {
        let now = CACurrentMediaTime()
        smoothedRects = smoothedRects.filter { id, value in
            ids.contains(id) || (now - value.lastSeen) < 0.25
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

private struct SmoothedRect {
    var rect: CGRect
    var lastSeen: CFTimeInterval
}

enum CoordinateMapper {
    /// Converts Vision's bottom-left normalized coordinates into AppKit screen coordinates (bottom-left origin).
    static func screenRect(fromVisionNormalized rect: CGRect, displaySize: CGSize) -> CGRect {
        CGRect(
            x: rect.origin.x * displaySize.width,
            y: rect.origin.y * displaySize.height,
            width: rect.size.width * displaySize.width,
            height: rect.size.height * displaySize.height
        )
    }
}
