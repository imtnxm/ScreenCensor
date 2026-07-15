import AppKit
import CoreImage
import CoreVideo
import QuartzCore

@MainActor
final class OverlayWindowController {
    private let panel: NSPanel
    private let rootLayer = CALayer()
    private var contentLayers: [UUID: CALayer] = [:]
    private let effectRenderer = EffectRenderer()
    private var lastPixelBuffer: CVPixelBuffer?
    private var displaySize: CGSize = .zero

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
        lastPixelBuffer = nil
    }

    func updateFrameContext(pixelBuffer: CVPixelBuffer?, displaySize: CGSize) {
        lastPixelBuffer = pixelBuffer
        self.displaySize = displaySize
    }

    func render(regions: [TrackedRegion]) {
        let incoming = Set(regions.map(\.id))
        let existing = Set(contentLayers.keys)

        for id in existing.subtracting(incoming) {
            contentLayers[id]?.removeFromSuperlayer()
            contentLayers.removeValue(forKey: id)
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = displaySize.width > 0 ? displaySize : (NSScreen.main?.frame.size ?? .zero)

        for region in regions {
            upsertLayer(region: region, displaySize: size, scaleFactor: scale)
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
        displaySize = screen.frame.size
    }

    private func upsertLayer(region: TrackedRegion, displaySize: CGSize, scaleFactor: CGFloat) {
        let layer = contentLayers[region.id] ?? CALayer()
        layer.frame = region.screenRect
        layer.cornerRadius = 6
        layer.masksToBounds = true
        layer.contentsGravity = .resize
        layer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "contents": NSNull()
        ]

        if let image = effectRenderer.renderPatch(
            pixelBuffer: lastPixelBuffer,
            screenRect: region.screenRect,
            displaySize: displaySize,
            effect: region.effect,
            scaleFactor: scaleFactor
        ) {
            layer.contents = image
            layer.backgroundColor = NSColor.clear.cgColor
        } else {
            layer.contents = nil
            layer.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        }

        applyAnimation(region.effect.animation, to: layer)

        if contentLayers[region.id] == nil {
            rootLayer.addSublayer(layer)
            contentLayers[region.id] = layer
        }
    }

    private func applyAnimation(_ animation: OverlayAnimation, to layer: CALayer) {
        layer.removeAllAnimations()
        switch animation {
        case .none:
            break
        case .pulse:
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 0.75
            anim.toValue = 1.0
            anim.duration = 0.55
            anim.autoreverses = true
            anim.repeatCount = .infinity
            layer.add(anim, forKey: "pulse")
        case .shake:
            let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
            anim.values = [0, -3, 3, -2, 2, 0]
            anim.duration = 0.35
            anim.repeatCount = .infinity
            layer.add(anim, forKey: "shake")
        case .stampIn:
            let anim = CABasicAnimation(keyPath: "transform.scale")
            anim.fromValue = 1.25
            anim.toValue = 1.0
            anim.duration = 0.18
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(anim, forKey: "stamp")
        case .scanline:
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 0.55
            anim.toValue = 1.0
            anim.duration = 0.28
            anim.autoreverses = true
            anim.repeatCount = .infinity
            layer.add(anim, forKey: "scan")
        }
    }
}
