import CoreGraphics
import Foundation
import QuartzCore

struct TrackerSettings: Equatable, Sendable {
    var smoothing: Double
    var coastSeconds: Double
    var minIoU: CGFloat
    var maxCenterDistance: CGFloat

    init(motion: MotionSettings) {
        smoothing = motion.smoothing
        coastSeconds = motion.coastSeconds
        minIoU = 0.08
        maxCenterDistance = 0.25
    }
}

struct TrackerInput: Sendable {
    let part: BodyPartID
    let normalizedRect: CGRect
    let confidence: Float
    let effect: EffectPreset
}

/// Stable ID tracking with velocity prediction, EMA smooth, and coast-on-miss.
final class RegionTracker: @unchecked Sendable {
    private struct State {
        var id: UUID
        var part: BodyPartID
        var normalizedRect: CGRect
        var velocity: CGVector
        var confidence: Float
        var effect: EffectPreset
        var lastSeen: CFTimeInterval
        var age: Int
    }

    private var tracks: [UUID: State] = [:]
    private var settings = TrackerSettings(motion: MotionSettings())

    func updateSettings(_ settings: TrackerSettings) {
        self.settings = settings
    }

    func reset() {
        tracks.removeAll()
    }

    /// Ingest new detections at `now`. Returns active tracks including coasting ones.
    func update(detections: [TrackerInput], now: CFTimeInterval) -> [TrackedInternal] {
        var unmatched = tracks
        var claimed: [UUID: State] = [:]

        for detection in detections {
            var bestID: UUID?
            var bestScore: CGFloat = .greatestFiniteMagnitude

            for (id, state) in unmatched where state.part == detection.part {
                let iouScore = Self.iou(detection.normalizedRect, state.normalizedRect)
                let centerDist = Self.centerDistance(detection.normalizedRect, state.normalizedRect)
                if iouScore < settings.minIoU && centerDist > settings.maxCenterDistance {
                    continue
                }
                // Lower is better: prefer high IoU and nearby centers.
                let score = (1.0 - iouScore) * 0.65 + centerDist * 0.35
                if score < bestScore {
                    bestScore = score
                    bestID = id
                }
            }

            let id = bestID ?? UUID()
            if let bestID { unmatched.removeValue(forKey: bestID) }

            let previous = tracks[id]
            let dt = max(1.0 / 120.0, now - (previous?.lastSeen ?? now))
            let target = detection.normalizedRect

            // Safety-first: expand immediately, shrink smoothly.
            let blended: CGRect
            if let previous {
                let expandX = target.width >= previous.normalizedRect.width
                let expandY = target.height >= previous.normalizedRect.height
                let tGrow: CGFloat = 0.85
                let tShrink = CGFloat(settings.smoothing)
                let tx = expandX ? tGrow : tShrink
                let ty = expandY ? tGrow : tShrink
                blended = CGRect(
                    x: Self.lerp(previous.normalizedRect.origin.x, target.origin.x, tx),
                    y: Self.lerp(previous.normalizedRect.origin.y, target.origin.y, ty),
                    width: Self.lerp(previous.normalizedRect.width, target.width, tx),
                    height: Self.lerp(previous.normalizedRect.height, target.height, ty)
                )
            } else {
                blended = target
            }

            let vx: CGFloat
            let vy: CGFloat
            if let previous {
                vx = (blended.midX - previous.normalizedRect.midX) / CGFloat(dt)
                vy = (blended.midY - previous.normalizedRect.midY) / CGFloat(dt)
            } else {
                vx = 0
                vy = 0
            }

            claimed[id] = State(
                id: id,
                part: detection.part,
                normalizedRect: blended,
                velocity: CGVector(dx: vx, dy: vy),
                confidence: detection.confidence,
                effect: detection.effect,
                lastSeen: now,
                age: (previous?.age ?? 0) + 1
            )
        }

        // Coast unseen tracks with velocity prediction.
        var next = claimed
        for (id, state) in unmatched {
            let age = now - state.lastSeen
            if age > settings.coastSeconds { continue }
            let predicted = state.normalizedRect.offsetBy(
                dx: state.velocity.dx * CGFloat(1.0 / 60.0),
                dy: state.velocity.dy * CGFloat(1.0 / 60.0)
            )
            var coasted = state
            coasted.normalizedRect = PartRuleEngine.clampNormalized(predicted)
            coasted.confidence = max(0.05, state.confidence * 0.92)
            next[id] = coasted
        }

        tracks = next
        return tracks.values.map {
            TrackedInternal(
                id: $0.id,
                part: $0.part,
                normalizedRect: $0.normalizedRect,
                confidence: $0.confidence,
                effect: $0.effect
            )
        }
    }

    /// Interpolate for display refresh between detections.
    func predicted(at now: CFTimeInterval) -> [TrackedInternal] {
        tracks.values.compactMap { state in
            let age = now - state.lastSeen
            guard age <= settings.coastSeconds else { return nil }
            let predicted = state.normalizedRect.offsetBy(
                dx: state.velocity.dx * CGFloat(age),
                dy: state.velocity.dy * CGFloat(age)
            )
            return TrackedInternal(
                id: state.id,
                part: state.part,
                normalizedRect: PartRuleEngine.clampNormalized(predicted),
                confidence: state.confidence,
                effect: state.effect
            )
        }
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, !inter.isEmpty else { return 0 }
        let interArea = inter.width * inter.height
        let union = a.width * a.height + b.width * b.height - interArea
        guard union > 0 else { return 0 }
        return interArea / union
    }

    private static func centerDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(a.midX - b.midX, a.midY - b.midY)
    }
}

struct TrackedInternal: Sendable {
    let id: UUID
    let part: BodyPartID
    let normalizedRect: CGRect
    let confidence: Float
    let effect: EffectPreset
}
