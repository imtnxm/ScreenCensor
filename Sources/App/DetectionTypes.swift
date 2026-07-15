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
    /// Vision-normalized rect with origin at bottom-left.
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
    let screenRect: CGRect
    let confidence: Float
    let effect: EffectPreset
}

struct FrameDetections: Sendable {
    let timestamp: CFTimeInterval
    let displaySize: CGSize
    /// Pixel buffer retained for content-aware effects (caller must not mutate).
    let pixelBuffer: CVPixelBuffer?
    let results: [DetectionResult]
}
