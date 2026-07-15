import CoreGraphics
import Foundation

enum DetectionKind: String, Sendable {
    case face
    case faceLandmarks
    case skin
    case intimateZone
}

struct DetectionResult: Identifiable, Sendable {
    let id: UUID
    let kind: DetectionKind
    /// Vision-normalized rect with origin at bottom-left.
    let normalizedRect: CGRect
    let confidence: Float
    let label: String?

    init(
        id: UUID = UUID(),
        kind: DetectionKind,
        normalizedRect: CGRect,
        confidence: Float,
        label: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.normalizedRect = normalizedRect
        self.confidence = confidence
        self.label = label
    }
}

struct FrameDetections: Sendable {
    let timestamp: CFTimeInterval
    let displaySize: CGSize
    let results: [DetectionResult]
}
