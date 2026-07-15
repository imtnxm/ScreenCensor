import CoreGraphics
import Foundation

enum PartRuleEngine {
    /// Filters raw detections by per-part enabled state and confidence.
    static func filter(
        _ detections: [DetectionResult],
        configuration: CensorConfiguration
    ) -> [DetectionResult] {
        detections.filter { detection in
            let rule = configuration.rule(for: detection.part)
            guard rule.enabled else { return false }
            guard detection.confidence >= rule.confidenceThreshold else { return false }

            // Covered / exposed are separate BodyPartIDs — enabled flag already encodes the toggle.
            return true
        }
    }

    static func paddedRect(
        _ rect: CGRect,
        part: BodyPartID,
        configuration: CensorConfiguration
    ) -> CGRect {
        let rule = configuration.rule(for: part)
        let pad = max(configuration.motion.globalPadding, rule.padding)
        let inset = rect.insetBy(dx: -rect.width * pad, dy: -rect.height * pad)
        return clampNormalized(inset)
    }

    static func effect(
        for part: BodyPartID,
        configuration: CensorConfiguration
    ) -> EffectPreset {
        configuration.rule(for: part).effect
    }

    static func clampNormalized(_ rect: CGRect) -> CGRect {
        let x = max(0, min(1, rect.origin.x))
        let y = max(0, min(1, rect.origin.y))
        let maxX = max(0, min(1, rect.origin.x + rect.size.width))
        let maxY = max(0, min(1, rect.origin.y + rect.size.height))
        return CGRect(x: x, y: y, width: max(0, maxX - x), height: max(0, maxY - y))
    }
}
