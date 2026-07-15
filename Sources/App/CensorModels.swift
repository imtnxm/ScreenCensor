import Foundation
import SwiftUI

// MARK: - Body Parts (NudeNet + pose-derived)

enum BodyPartID: String, CaseIterable, Identifiable, Codable, Sendable {
    // Faces
    case faceFemale
    case faceMale
    // Chest
    case femaleBreastCovered
    case femaleBreastExposed
    case maleBreastExposed
    // Intimate
    case femaleGenitaliaCovered
    case femaleGenitaliaExposed
    case maleGenitaliaExposed
    case anusCovered
    case anusExposed
    // Rear
    case buttocksCovered
    case buttocksExposed
    // Midsection / limbs
    case bellyCovered
    case bellyExposed
    case armpitsCovered
    case armpitsExposed
    case feetCovered
    case feetExposed
    // Pose-derived
    case hands
    case feetPose
    case faceLandmarks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faceFemale: return "Face (Female)"
        case .faceMale: return "Face (Male)"
        case .femaleBreastCovered: return "Breasts Covered"
        case .femaleBreastExposed: return "Breasts Exposed"
        case .maleBreastExposed: return "Male Chest Exposed"
        case .femaleGenitaliaCovered: return "Intimate Covered (F)"
        case .femaleGenitaliaExposed: return "Intimate Exposed (F)"
        case .maleGenitaliaExposed: return "Intimate Exposed (M)"
        case .anusCovered: return "Anus Covered"
        case .anusExposed: return "Anus Exposed"
        case .buttocksCovered: return "Buttocks Covered"
        case .buttocksExposed: return "Buttocks Exposed"
        case .bellyCovered: return "Belly Covered"
        case .bellyExposed: return "Belly Exposed"
        case .armpitsCovered: return "Armpits Covered"
        case .armpitsExposed: return "Armpits Exposed"
        case .feetCovered: return "Feet Covered"
        case .feetExposed: return "Feet Exposed"
        case .hands: return "Hands"
        case .feetPose: return "Feet (Pose)"
        case .faceLandmarks: return "Eyes / Lips"
        }
    }

    var group: BodyPartGroup {
        switch self {
        case .faceFemale, .faceMale, .faceLandmarks: return .face
        case .femaleBreastCovered, .femaleBreastExposed, .maleBreastExposed: return .chest
        case .femaleGenitaliaCovered, .femaleGenitaliaExposed, .maleGenitaliaExposed, .anusCovered, .anusExposed: return .intimate
        case .buttocksCovered, .buttocksExposed: return .rear
        case .bellyCovered, .bellyExposed: return .belly
        case .armpitsCovered, .armpitsExposed: return .armpits
        case .feetCovered, .feetExposed, .feetPose: return .feet
        case .hands: return .hands
        }
    }

    var isCovered: Bool {
        switch self {
        case .femaleBreastCovered, .femaleGenitaliaCovered, .anusCovered,
             .buttocksCovered, .bellyCovered, .armpitsCovered, .feetCovered:
            return true
        default:
            return false
        }
    }

    var isExposed: Bool {
        switch self {
        case .femaleBreastExposed, .maleBreastExposed, .femaleGenitaliaExposed,
             .maleGenitaliaExposed, .anusExposed, .buttocksExposed,
             .bellyExposed, .armpitsExposed, .feetExposed:
            return true
        default:
            return false
        }
    }

    /// NudeNet label string (nil for pose-derived parts).
    var nudeNetLabel: String? {
        switch self {
        case .faceFemale: return "FACE_FEMALE"
        case .faceMale: return "FACE_MALE"
        case .femaleBreastCovered: return "FEMALE_BREAST_COVERED"
        case .femaleBreastExposed: return "FEMALE_BREAST_EXPOSED"
        case .maleBreastExposed: return "MALE_BREAST_EXPOSED"
        case .femaleGenitaliaCovered: return "FEMALE_GENITALIA_COVERED"
        case .femaleGenitaliaExposed: return "FEMALE_GENITALIA_EXPOSED"
        case .maleGenitaliaExposed: return "MALE_GENITALIA_EXPOSED"
        case .anusCovered: return "ANUS_COVERED"
        case .anusExposed: return "ANUS_EXPOSED"
        case .buttocksCovered: return "BUTTOCKS_COVERED"
        case .buttocksExposed: return "BUTTOCKS_EXPOSED"
        case .bellyCovered: return "BELLY_COVERED"
        case .bellyExposed: return "BELLY_EXPOSED"
        case .armpitsCovered: return "ARMPITS_COVERED"
        case .armpitsExposed: return "ARMPITS_EXPOSED"
        case .feetCovered: return "FEET_COVERED"
        case .feetExposed: return "FEET_EXPOSED"
        case .hands, .feetPose, .faceLandmarks: return nil
        }
    }

    static func fromNudeNetLabel(_ label: String) -> BodyPartID? {
        let upper = label.uppercased()
        return allCases.first { $0.nudeNetLabel == upper }
    }

    static var defaultEnabled: Set<BodyPartID> {
        [
            .faceFemale, .faceMale, .faceLandmarks,
            .femaleBreastExposed, .maleBreastExposed,
            .femaleGenitaliaExposed, .maleGenitaliaExposed,
            .anusExposed, .buttocksExposed, .hands
        ]
    }
}

enum BodyPartGroup: String, CaseIterable, Identifiable, Sendable {
    case face, chest, intimate, rear, belly, armpits, feet, hands

    var id: String { rawValue }

    var title: String {
        switch self {
        case .face: return "Face"
        case .chest: return "Chest / Breasts"
        case .intimate: return "Intimate Areas"
        case .rear: return "Buttocks"
        case .belly: return "Belly"
        case .armpits: return "Armpits"
        case .feet: return "Feet"
        case .hands: return "Hands"
        }
    }

    var parts: [BodyPartID] {
        BodyPartID.allCases.filter { $0.group == self }
    }
}

// MARK: - Effects

enum CensorStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case box
    case blur
    case pixelate
    case label
    case sticker
    case colorWash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .box: return "Box"
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .label: return "Label"
        case .sticker: return "Sticker"
        case .colorWash: return "Color Wash"
        }
    }
}

enum OverlayAnimation: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case pulse
    case shake
    case stampIn
    case scanline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .pulse: return "Pulse"
        case .shake: return "Shake"
        case .stampIn: return "Stamp In"
        case .scanline: return "Scanline"
        }
    }
}

enum StickerSymbol: String, CaseIterable, Identifiable, Codable, Sendable {
    case ban = "hand.raised.fill"
    case eyeSlash = "eye.slash.fill"
    case star = "star.fill"
    case lock = "lock.fill"
    case xmark = "xmark.circle.fill"
    case flame = "flame.fill"
    case sparkles = "sparkles"
    case caution = "exclamationmark.triangle.fill"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ban: return "Raised Hand"
        case .eyeSlash: return "Eye Slash"
        case .star: return "Star"
        case .lock: return "Lock"
        case .xmark: return "X Mark"
        case .flame: return "Flame"
        case .sparkles: return "Sparkles"
        case .caution: return "Caution"
        }
    }
}

struct EffectPreset: Equatable, Codable, Sendable, Identifiable {
    var id: String
    var style: CensorStyle
    var blurRadius: Double
    var pixelScale: Double
    var labelText: String
    var labelEmoji: String
    var sticker: StickerSymbol
    var fillOpacity: Double
    var animation: OverlayAnimation

    static let `default` = EffectPreset(
        id: "default",
        style: .blur,
        blurRadius: 24,
        pixelScale: 14,
        labelText: "CENSORED",
        labelEmoji: "🚫",
        sticker: .eyeSlash,
        fillOpacity: 0.85,
        animation: .pulse
    )

    static let solid = EffectPreset(
        id: "solid",
        style: .box,
        blurRadius: 20,
        pixelScale: 12,
        labelText: "CENSORED",
        labelEmoji: "",
        sticker: .ban,
        fillOpacity: 0.92,
        animation: .none
    )

    static let mosaic = EffectPreset(
        id: "mosaic",
        style: .pixelate,
        blurRadius: 18,
        pixelScale: 18,
        labelText: "CENSORED",
        labelEmoji: "",
        sticker: .sparkles,
        fillOpacity: 0.8,
        animation: .none
    )

    static let stamp = EffectPreset(
        id: "stamp",
        style: .sticker,
        blurRadius: 16,
        pixelScale: 12,
        labelText: "CENSORED",
        labelEmoji: "❌",
        sticker: .xmark,
        fillOpacity: 0.75,
        animation: .stampIn
    )
}

// MARK: - Per-part rules

struct BodyPartRule: Equatable, Codable, Sendable, Identifiable {
    var part: BodyPartID
    var enabled: Bool
    var confidenceThreshold: Float
    var padding: Double
    var effect: EffectPreset

    var id: String { part.rawValue }

    static func `default`(for part: BodyPartID) -> BodyPartRule {
        BodyPartRule(
            part: part,
            enabled: BodyPartID.defaultEnabled.contains(part),
            confidenceThreshold: 0.35,
            padding: 0.12,
            effect: .default
        )
    }
}

// MARK: - Performance / motion

enum PerformanceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case powerSaver
    case balanced
    case highRefresh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .powerSaver: return "Power Saver"
        case .balanced: return "Balanced"
        case .highRefresh: return "High Refresh"
        }
    }

    var targetFrameRate: Int {
        switch self {
        case .powerSaver: return 30
        case .balanced: return 60
        case .highRefresh: return 120
        }
    }

    var queueDepth: Int {
        switch self {
        case .powerSaver: return 2
        case .balanced: return 3
        case .highRefresh: return 5
        }
    }

    var detectionScale: Double {
        switch self {
        case .powerSaver: return 0.5
        case .balanced: return 0.75
        case .highRefresh: return 1.0
        }
    }
}

struct MotionSettings: Equatable, Codable, Sendable {
    var smoothing: Double = 0.35
    var coastSeconds: Double = 0.2
    var globalPadding: Double = 0.08
}

// MARK: - Top-level configuration

struct CensorConfiguration: Equatable, Codable, Sendable {
    var rules: [BodyPartRule]
    var globalEffect: EffectPreset
    var performanceMode: PerformanceMode
    var motion: MotionSettings
    var usePoseAssist: Bool
    var useFaceLandmarks: Bool

    init(
        rules: [BodyPartRule] = BodyPartID.allCases.map { BodyPartRule.default(for: $0) },
        globalEffect: EffectPreset = .default,
        performanceMode: PerformanceMode = .balanced,
        motion: MotionSettings = MotionSettings(),
        usePoseAssist: Bool = true,
        useFaceLandmarks: Bool = true
    ) {
        self.rules = rules
        self.globalEffect = globalEffect
        self.performanceMode = performanceMode
        self.motion = motion
        self.usePoseAssist = usePoseAssist
        self.useFaceLandmarks = useFaceLandmarks
    }

    func rule(for part: BodyPartID) -> BodyPartRule {
        rules.first { $0.part == part } ?? BodyPartRule.default(for: part)
    }

    mutating func updateRule(_ rule: BodyPartRule) {
        if let idx = rules.firstIndex(where: { $0.part == rule.part }) {
            rules[idx] = rule
        } else {
            rules.append(rule)
        }
    }

    mutating func setGroup(_ group: BodyPartGroup, enabled: Bool) {
        for part in group.parts {
            var r = rule(for: part)
            r.enabled = enabled
            updateRule(r)
        }
    }

    func isGroupFullyEnabled(_ group: BodyPartGroup) -> Bool {
        group.parts.allSatisfy { rule(for: $0).enabled }
    }

    mutating func applyGlobalEffectToAll() {
        for part in BodyPartID.allCases {
            var r = rule(for: part)
            r.effect = globalEffect
            updateRule(r)
        }
    }

    // Legacy compatibility helpers used during migration of call sites
    var style: CensorStyle {
        get { globalEffect.style }
        set { globalEffect.style = newValue }
    }

    var censorText: String {
        get { globalEffect.labelText }
        set { globalEffect.labelText = newValue }
    }
}
