import AppKit
import CoreImage
import QuartzCore

@MainActor
final class OverlayWindowController {
    private let panel: NSPanel
    private let rootLayer = CALayer()
    private var contentLayers: [UUID: CALayer] = [:]
    private var currentStyle: CensorStyle = .blur
    private var censorText = "CENSORED"

    private let blurFilter: CIFilter? = CIFilter(name: "CIGaussianBlur")
    private let pixellateFilter: CIFilter? = CIFilter(name: "CIPixellate")

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        configureRootLayer()
        syncFrameToPrimaryDisplay()
    }

    var windowID: CGWindowID {
        CGWindowID(panel.windowNumber)
    }

    func show() {
        syncFrameToPrimaryDisplay()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        clearDetections()
    }

    func updateStyle(_ style: CensorStyle, text: String) {
        currentStyle = style
        censorText = text
        // Force rebuild so style changes apply immediately.
        let snapshot = contentLayers.map { (id: $0.key, frame: $0.value.frame) }
        clearDetections()
        for item in snapshot {
            upsertLayer(id: item.id, frame: item.frame)
        }
    }

    func render(screenRects: [(id: UUID, rect: CGRect)]) {
        let incoming = Set(screenRects.map(\.id))
        let existing = Set(contentLayers.keys)

        for id in existing.subtracting(incoming) {
            contentLayers[id]?.removeFromSuperlayer()
            contentLayers.removeValue(forKey: id)
        }

        for item in screenRects {
            upsertLayer(id: item.id, frame: item.rect)
        }
    }

    func clearDetections() {
        contentLayers.values.forEach { $0.removeFromSuperlayer() }
        contentLayers.removeAll()
    }

    private func configurePanel() {
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none

        let contentView = NSView(frame: panel.frame)
        contentView.wantsLayer = true
        contentView.layer = rootLayer
        panel.contentView = contentView
    }

    private func configureRootLayer() {
        rootLayer.backgroundColor = NSColor.clear.cgColor
        rootLayer.masksToBounds = false
    }

    private func syncFrameToPrimaryDisplay() {
        guard let screen = NSScreen.main else { return }
        panel.setFrame(screen.frame, display: true)
        rootLayer.frame = CGRect(origin: .zero, size: screen.frame.size)
    }

    private func upsertLayer(id: UUID, frame: CGRect) {
        let layer = contentLayers[id] ?? makeLayer(for: currentStyle)
        layer.frame = frame
        applyStyle(to: layer)

        if contentLayers[id] == nil {
            rootLayer.addSublayer(layer)
            contentLayers[id] = layer
        }
    }

    private func makeLayer(for style: CensorStyle) -> CALayer {
        switch style {
        case .box, .blur, .pixelate:
            return CALayer()
        case .text:
            let textLayer = CATextLayer()
            textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            textLayer.alignmentMode = .center
            textLayer.foregroundColor = NSColor.white.cgColor
            textLayer.font = NSFont.boldSystemFont(ofSize: 14)
            textLayer.fontSize = 14
            return textLayer
        }
    }

    private func applyStyle(to layer: CALayer) {
        layer.cornerRadius = 6
        layer.masksToBounds = true
        layer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "contents": NSNull()
        ]

        switch currentStyle {
        case .box:
            layer.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
            layer.filters = nil
            if let textLayer = layer as? CATextLayer {
                textLayer.string = nil
            }

        case .blur:
            layer.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
            blurFilter?.setValue(18.0, forKey: kCIInputRadiusKey)
            layer.filters = blurFilter.map { [$0] }
            if let textLayer = layer as? CATextLayer {
                textLayer.string = nil
            }

        case .pixelate:
            layer.backgroundColor = NSColor.gray.withAlphaComponent(0.55).cgColor
            pixellateFilter?.setValue(12.0, forKey: kCIInputScaleKey)
            layer.filters = pixellateFilter.map { [$0] }
            if let textLayer = layer as? CATextLayer {
                textLayer.string = nil
            }

        case .text:
            layer.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
            layer.filters = nil
            if let textLayer = layer as? CATextLayer {
                textLayer.string = censorText
            }
        }
    }
}
