import Foundation

enum CensorStyle: String, CaseIterable, Identifiable, Sendable {
    case box
    case blur
    case pixelate
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .box: return "Box"
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .text: return "Text"
        }
    }
}

enum PerformanceMode: String, CaseIterable, Identifiable, Sendable {
    case balanced
    case highRefresh
    case powerSaver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .highRefresh: return "High Refresh"
        case .powerSaver: return "Power Saver"
        }
    }

    var targetFrameRate: Int {
        switch self {
        case .balanced: return 60
        case .highRefresh: return 120
        case .powerSaver: return 30
        }
    }

    var queueDepth: Int {
        switch self {
        case .balanced: return 3
        case .highRefresh: return 5
        case .powerSaver: return 2
        }
    }
}

struct DetectionTargets: Equatable, Sendable {
    var face: Bool = true
    var skin: Bool = false
    var intimateZones: Bool = true
}

struct CensorConfiguration: Equatable, Sendable {
    var targets: DetectionTargets = DetectionTargets()
    var style: CensorStyle = .blur
    var performanceMode: PerformanceMode = .balanced
    var censorText: String = "CENSORED"
}
