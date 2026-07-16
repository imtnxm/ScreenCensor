import AppKit
import CoreVideo
import Metal
import QuartzCore

@MainActor
final class OverlayWindowController {
    let display: DisplayInfo
    private let panel: NSPanel
    private let hostView: MetalHostView
    private let effectRenderer: EffectRenderer
    private var layerAnimations: [UUID: OverlayAnimation] = [:]
    private var lastRegions: [TrackedRegion] = []

    init(display: DisplayInfo, effectRenderer: EffectRenderer = EffectRenderer()) {
        self.display = display
        self.effectRenderer = effectRenderer

        panel = NSPanel(
            contentRect: display.pointFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hostView = MetalHostView(frame: CGRect(origin: .zero, size: display.pointFrame.size))
        configurePanel()
    }

    var windowID: CGWindowID {
        CGWindowID(panel.windowNumber)
    }

    var usingGPUFallback: Bool { effectRenderer.usingGPUFallback }

    func show() {
        panel.setFrame(display.pointFrame, display: true)
        hostView.frame = CGRect(origin: .zero, size: display.pointFrame.size)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        clear()
    }

    func clear() {
        lastRegions = []
        hostView.clear()
        layerAnimations.removeAll()
    }

    func render(pixelBuffer: CVPixelBuffer, geometry: FrameGeometry, regions: [TrackedRegion]) {
        lastRegions = regions
        let scale = display.backingScaleFactor
        effectRenderer.compose(
            pixelBuffer: pixelBuffer,
            geometry: geometry,
            regions: regions,
            scaleFactor: scale
        ) { [weak self] image in
            Task { @MainActor in
                guard let self else { return }
                if let image {
                    self.hostView.present(image: image)
                } else {
                    self.hostView.presentFallback(regions: regions, size: self.display.pointFrame.size)
                }
            }
        }
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
        panel.contentView = hostView
        panel.setFrame(display.pointFrame, display: true)
    }
}

@MainActor
final class MetalHostView: NSView {
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor
        imageLayer.frame = bounds
        imageLayer.contentsGravity = .resize
        imageLayer.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull()
        ]
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }

    func present(image: CGImage) {
        imageLayer.contents = image
        imageLayer.backgroundColor = NSColor.clear.cgColor
    }

    func presentFallback(regions: [TrackedRegion], size: CGSize) {
        imageLayer.contents = nil
        // Lightweight solid boxes if GPU compose fails.
        imageLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        for region in regions {
            let box = CALayer()
            box.frame = region.localRect
            box.backgroundColor = NSColor.black.withAlphaComponent(0.9).cgColor
            box.cornerRadius = 6
            imageLayer.addSublayer(box)
        }
    }

    func clear() {
        imageLayer.contents = nil
        imageLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }
}
