import CoreGraphics
import CoreVideo
import Foundation

enum DetectionSource: String, Sendable {
    case nudeNet
    case visionFace
    case visionLandmarks
    case visionHandPose
    case visionBodyPose
}

struct DetectionResult: Identifiable, Sendable {
    let id: UUID
    let part: BodyPartID
    let source: DetectionSource
    /// Vision-normalized rect with origin at bottom-left, relative to the captured display content.
    let normalizedRect: CGRect
    let confidence: Float
    let label: String?

    init(
        id: UUID = UUID(),
        part: BodyPartID,
        source: DetectionSource,
        normalizedRect: CGRect,
        confidence: Float,
        label: String? = nil
    ) {
        self.id = id
        self.part = part
        self.source = source
        self.normalizedRect = normalizedRect
        self.confidence = confidence
        self.label = label
    }
}

struct TrackedRegion: Identifiable, Sendable {
    let id: UUID
    let part: BodyPartID
    let displayID: CGDirectDisplayID
    /// Overlay-local rect (origin at display corner, AppKit bottom-left).
    let localRect: CGRect
    /// Vision-normalized rect used for buffer cropping.
    let normalizedRect: CGRect
    let confidence: Float
    let effect: EffectPreset
}

struct FrameDetections: Sendable {
    let timestamp: CFTimeInterval
    let displayID: CGDirectDisplayID
    let geometry: FrameGeometry
    let pixelBuffer: CVPixelBuffer
    let results: [DetectionResult]
}
