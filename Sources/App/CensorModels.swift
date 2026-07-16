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
    case softBlur
    case frosted
    case pixelate
    case chunkyPixel
    case crystallize
    case label
    case sticker
    case colorWash
    case warningTape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .box: return "Solid Box"
        case .blur: return "Strong Blur"
        case .softBlur: return "Soft Blur"
        case .frosted: return "Frosted"
        case .pixelate: return "Mosaic"
        case .chunkyPixel: return "Chunky Pixel"
        case .crystallize: return "Crystallize"
        case .label: return "Label"
        case .sticker: return "Sticker"
        case .colorWash: return "Color Wash"
        case .warningTape: return "Warning Tape"
        }
    }

    var isContentAware: Bool {
        switch self {
        case .blur, .softBlur, .frosted, .pixelate, .chunkyPixel, .crystallize:
            return true
        default:
            return false
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

struct EffectPreset: Equatable, Hashable, Codable, Sendable, Identifiable {
    var id: String
    var style: CensorStyle
    var blurRadius: Double
    var pixelScale: Double
    var labelText: String
    var labelEmoji: String
    var sticker: StickerSymbol
    var fillOpacity: Double
    var animation: OverlayAnimation
    var cornerRadius: Double
    var feather: Double
    var assetName: String?

    enum CodingKeys: String, CodingKey {
        case id, style, blurRadius, pixelScale, labelText, labelEmoji, sticker, fillOpacity, animation
        case cornerRadius, feather, assetName
    }

    init(
        id: String,
        style: CensorStyle,
        blurRadius: Double,
        pixelScale: Double,
        labelText: String,
        labelEmoji: String,
        sticker: StickerSymbol,
        fillOpacity: Double,
        animation: OverlayAnimation,
        cornerRadius: Double = 8,
        feather: Double = 2,
        assetName: String? = nil
    ) {
        self.id = id
        self.style = style
        self.blurRadius = blurRadius
        self.pixelScale = pixelScale
        self.labelText = labelText
        self.labelEmoji = labelEmoji
        self.sticker = sticker
        self.fillOpacity = fillOpacity
        self.animation = animation
        self.cornerRadius = cornerRadius
        self.feather = feather
        self.assetName = assetName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        style = try c.decode(CensorStyle.self, forKey: .style)
        blurRadius = try c.decode(Double.self, forKey: .blurRadius)
        pixelScale = try c.decode(Double.self, forKey: .pixelScale)
        labelText = try c.decode(String.self, forKey: .labelText)
        labelEmoji = try c.decode(String.self, forKey: .labelEmoji)
        sticker = try c.decode(StickerSymbol.self, forKey: .sticker)
        fillOpacity = try c.decode(Double.self, forKey: .fillOpacity)
        animation = try c.decode(OverlayAnimation.self, forKey: .animation)
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 8
        feather = try c.decodeIfPresent(Double.self, forKey: .feather) ?? 2
        assetName = try c.decodeIfPresent(String.self, forKey: .assetName)
    }

    static let `default` = EffectPreset(
        id: "default",
        style: .blur,
        blurRadius: 28,
        pixelScale: 14,
        labelText: "CENSORED",
        labelEmoji: "🚫",
        sticker: .eyeSlash,
        fillOpacity: 0.92,
        animation: .none,
        cornerRadius: 8,
        feather: 2,
        assetName: nil
    )

    static let solid = EffectPreset(
        id: "solid",
        style: .box,
        blurRadius: 20,
        pixelScale: 12,
        labelText: "CENSORED",
        labelEmoji: "",
        sticker: .ban,
        fillOpacity: 0.95,
        animation: .none,
        cornerRadius: 4,
        feather: 0,
        assetName: nil
    )

    static let mosaic = EffectPreset(
        id: "mosaic",
        style: .pixelate,
        blurRadius: 18,
        pixelScale: 16,
        labelText: "CENSORED",
        labelEmoji: "",
        sticker: .sparkles,
        fillOpacity: 1.0,
        animation: .none,
        cornerRadius: 6,
        feather: 1,
        assetName: nil
    )

    static let frosted = EffectPreset(
        id: "frosted",
        style: .frosted,
        blurRadius: 22,
        pixelScale: 12,
        labelText: "CENSORED",
        labelEmoji: "",
        sticker: .lock,
        fillOpacity: 0.85,
        animation: .pulse,
        cornerRadius: 10,
        feather: 4,
        assetName: nil
    )

    static let chunky = EffectPreset(
        id: "chunky",
        style: .chunkyPixel,
        blurRadius: 12,
        pixelScale: 28,
        labelText: "CENSORED",
        labelEmoji: "",
        sticker: .xmark,
        fillOpacity: 1.0,
        animation: .none,
        cornerRadius: 2,
        feather: 0,
        assetName: nil
    )

    static let stamp = EffectPreset(
        id: "stamp",
        style: .sticker,
        blurRadius: 16,
        pixelScale: 12,
        labelText: "CENSORED",
        labelEmoji: "❌",
        sticker: .xmark,
        fillOpacity: 0.8,
        animation: .stampIn,
        cornerRadius: 8,
        feather: 0,
        assetName: "sticker_ban"
    )

    static let warning = EffectPreset(
        id: "warning",
        style: .warningTape,
        blurRadius: 10,
        pixelScale: 10,
        labelText: "BLOCKED",
        labelEmoji: "⚠️",
        sticker: .caution,
        fillOpacity: 0.9,
        animation: .scanline,
        cornerRadius: 0,
        feather: 0,
        assetName: nil
    )

    static var catalog: [EffectPreset] {
        [.default, .frosted, .mosaic, .chunky, .solid, .stamp, .warning]
    }
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
    var coastSeconds: Double = 0.22
    var globalPadding: Double = 0.1
}

struct DisplayPreferences: Equatable, Codable, Sendable {
    /// Empty means all displays enabled.
    var enabledDisplayIDs: [UInt32] = []

    func isEnabled(_ id: UInt32, available: [UInt32]) -> Bool {
        if enabledDisplayIDs.isEmpty { return true }
        return enabledDisplayIDs.contains(id)
    }

    mutating func setEnabled(_ id: UInt32, enabled: Bool, available: [UInt32]) {
        var set = Set(enabledDisplayIDs.isEmpty ? available : enabledDisplayIDs)
        if enabled {
            set.insert(id)
        } else {
            set.remove(id)
        }
        enabledDisplayIDs = Array(set).sorted()
    }
}

// MARK: - Top-level configuration

struct CensorConfiguration: Equatable, Codable, Sendable {
    var rules: [BodyPartRule]
    var globalEffect: EffectPreset
    var performanceMode: PerformanceMode
    var motion: MotionSettings
    var usePoseAssist: Bool
    var useFaceLandmarks: Bool
    var displays: DisplayPreferences

    enum CodingKeys: String, CodingKey {
        case rules, globalEffect, performanceMode, motion, usePoseAssist, useFaceLandmarks, displays
    }

    init(
        rules: [BodyPartRule] = BodyPartID.allCases.map { BodyPartRule.default(for: $0) },
        globalEffect: EffectPreset = .default,
        performanceMode: PerformanceMode = .balanced,
        motion: MotionSettings = MotionSettings(),
        usePoseAssist: Bool = true,
        useFaceLandmarks: Bool = true,
        displays: DisplayPreferences = DisplayPreferences()
    ) {
        self.rules = rules
        self.globalEffect = globalEffect
        self.performanceMode = performanceMode
        self.motion = motion
        self.usePoseAssist = usePoseAssist
        self.useFaceLandmarks = useFaceLandmarks
        self.displays = displays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decodeIfPresent([BodyPartRule].self, forKey: .rules) ?? BodyPartID.allCases.map { BodyPartRule.default(for: $0) }
        globalEffect = try c.decodeIfPresent(EffectPreset.self, forKey: .globalEffect) ?? .default
        performanceMode = try c.decodeIfPresent(PerformanceMode.self, forKey: .performanceMode) ?? .balanced
        motion = try c.decodeIfPresent(MotionSettings.self, forKey: .motion) ?? MotionSettings()
        usePoseAssist = try c.decodeIfPresent(Bool.self, forKey: .usePoseAssist) ?? true
        useFaceLandmarks = try c.decodeIfPresent(Bool.self, forKey: .useFaceLandmarks) ?? true
        displays = try c.decodeIfPresent(DisplayPreferences.self, forKey: .displays) ?? DisplayPreferences()
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

    var style: CensorStyle {
        get { globalEffect.style }
        set { globalEffect.style = newValue }
    }

    var censorText: String {
        get { globalEffect.labelText }
        set { globalEffect.labelText = newValue }
    }
}

enum ConfigurationStore {
    private static let key = "ScreenCensor.configuration.v2"

    static func load() -> CensorConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(CensorConfiguration.self, from: data) else {
            return CensorConfiguration()
        }
        return decoded
    }

    static func save(_ configuration: CensorConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
