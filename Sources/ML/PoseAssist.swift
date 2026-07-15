import CoreGraphics
import Foundation
import Vision

enum PoseAssist {
    static func handBoxes(from observations: [VNHumanHandPoseObservation]) -> [DetectionResult] {
        observations.compactMap { observation -> DetectionResult? in
            guard let box = boundingBox(from: observation) else { return nil }
            return DetectionResult(
                part: .hands,
                source: .visionHandPose,
                normalizedRect: PartRuleEngine.clampNormalized(box),
                confidence: observation.confidence
            )
        }
    }

    static func feetBoxes(from observations: [VNHumanBodyPoseObservation]) -> [DetectionResult] {
        var results: [DetectionResult] = []
        for observation in observations {
            for jointName in [VNHumanBodyPoseObservation.JointName.leftAnkle, .rightAnkle] {
                guard let point = try? observation.recognizedPoint(jointName),
                      point.confidence > 0.2 else { continue }
                let size: CGFloat = 0.06
                let box = CGRect(
                    x: point.location.x - size / 2,
                    y: point.location.y - size / 2,
                    width: size,
                    height: size
                )
                results.append(
                    DetectionResult(
                        part: .feetPose,
                        source: .visionBodyPose,
                        normalizedRect: PartRuleEngine.clampNormalized(box),
                        confidence: point.confidence
                    )
                )
            }
        }
        return results
    }

    private static func boundingBox(from observation: VNHumanHandPoseObservation) -> CGRect? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        let valid = points.values.filter { $0.confidence > 0.2 }.map(\.location)
        guard !valid.isEmpty else { return nil }

        let xs = valid.map(\.x)
        let ys = valid.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }

        var box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if box.width < 0.04 { box.size.width = 0.04; box.origin.x -= 0.02 }
        if box.height < 0.04 { box.size.height = 0.04; box.origin.y -= 0.02 }
        let padded = box.insetBy(dx: -box.width * 0.25, dy: -box.height * 0.25)
        return padded
    }
}
