import AppKit
import CoreImage
import CoreVideo
import Foundation
import Metal
import QuartzCore

/// Single-pass GPU compositor that builds one transparent overlay texture for a display.
final class EffectRenderer {
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let ciContext: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let renderQueue = DispatchQueue(label: "com.screencensor.render", qos: .userInteractive)

    private(set) var usingGPUFallback = false

    init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        if let device {
            ciContext = CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false
            ])
            usingGPUFallback = false
        } else {
            ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
            usingGPUFallback = true
        }
    }

    /// Renders all regions into a single BGRA texture sized to the display points * scale.
    func compose(
        pixelBuffer: CVPixelBuffer,
        geometry: FrameGeometry,
        regions: [TrackedRegion],
        scaleFactor: CGFloat,
        completion: @escaping (CGImage?) -> Void
    ) {
        renderQueue.async {
            let image = self.composeSync(
                pixelBuffer: pixelBuffer,
                geometry: geometry,
                regions: regions,
                scaleFactor: scaleFactor
            )
            completion(image)
        }
    }

    func composeSync(
        pixelBuffer: CVPixelBuffer,
        geometry: FrameGeometry,
        regions: [TrackedRegion],
        scaleFactor: CGFloat
    ) -> CGImage? {
        let pointSize = geometry.pointFrame.size
        let outW = max(1, Int(pointSize.width * scaleFactor))
        let outH = max(1, Int(pointSize.height * scaleFactor))
        let canvasExtent = CGRect(x: 0, y: 0, width: outW, height: outH)

        let source = CIImage(cvPixelBuffer: pixelBuffer)
        var canvas = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: canvasExtent)

        // Precompute filtered variants once per required style class.
        let needsStrongBlur = regions.contains { [.blur, .frosted].contains($0.effect.style) }
        let needsSoftBlur = regions.contains { $0.effect.style == .softBlur }
        let needsPixel = regions.contains { [.pixelate, .chunkyPixel].contains($0.effect.style) }
        let needsCrystal = regions.contains { $0.effect.style == .crystallize }

        let strongBlur: CIImage? = needsStrongBlur ? Self.blurred(source, radius: 28) : nil
        let softBlur: CIImage? = needsSoftBlur ? Self.blurred(source, radius: 12) : nil
        let pixelated: CIImage? = needsPixel ? Self.pixellated(source, scale: 16) : nil
        let crystal: CIImage? = needsCrystal ? Self.crystallized(source, radius: 18) : nil

        for region in regions {
            let crop = geometry.bufferCrop(fromVisionNormalized: region.normalizedRect)
            guard crop.width > 1, crop.height > 1 else { continue }

            let local = region.localRect
            let dest = CGRect(
                x: local.minX * scaleFactor,
                y: local.minY * scaleFactor,
                width: max(1, local.width * scaleFactor),
                height: max(1, local.height * scaleFactor)
            )

            let patch: CIImage
            switch region.effect.style {
            case .blur, .frosted:
                patch = Self.extract(strongBlur ?? source, crop: crop, dest: dest, opacity: region.effect.fillOpacity)
            case .softBlur:
                patch = Self.extract(softBlur ?? source, crop: crop, dest: dest, opacity: region.effect.fillOpacity)
            case .pixelate:
                let custom = Self.pixellated(source, scale: max(4, region.effect.pixelScale))
                patch = Self.extract(custom, crop: crop, dest: dest, opacity: 1)
            case .chunkyPixel:
                let custom = Self.pixellated(source, scale: max(12, region.effect.pixelScale))
                patch = Self.extract(custom, crop: crop, dest: dest, opacity: 1)
            case .crystallize:
                patch = Self.extract(crystal ?? source, crop: crop, dest: dest, opacity: region.effect.fillOpacity)
            case .box, .colorWash, .label, .sticker, .warningTape:
                patch = Self.solidPatch(dest: dest, effect: region.effect, scaleFactor: scaleFactor)
            }

            let rounded = Self.roundedMask(dest: dest, corner: region.effect.cornerRadius * scaleFactor, feather: region.effect.feather * scaleFactor)
            let masked = patch.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: dest),
                kCIInputMaskImageKey: rounded
            ])
            canvas = masked.composited(over: canvas)
        }

        return ciContext.createCGImage(canvas, from: canvasExtent, format: .BGRA8, colorSpace: colorSpace)
    }

    private static func blurred(_ image: CIImage, radius: Double) -> CIImage {
        image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: image.extent)
    }

    private static func pixellated(_ image: CIImage, scale: Double) -> CIImage {
        let center = CIVector(x: image.extent.midX, y: image.extent.midY)
        return image.applyingFilter("CIPixellate", parameters: [
            kCIInputScaleKey: scale,
            kCIInputCenterKey: center
        ])
    }

    private static func crystallized(_ image: CIImage, radius: Double) -> CIImage {
        image.applyingFilter("CICrystallize", parameters: [
            kCIInputRadiusKey: radius,
            kCIInputCenterKey: CIVector(x: image.extent.midX, y: image.extent.midY)
        ])
    }

    private static func extract(_ image: CIImage, crop: CGRect, dest: CGRect, opacity: Double) -> CIImage {
        var cropped = image.cropped(to: crop)
        cropped = cropped.transformed(by: CGAffineTransform(translationX: -crop.origin.x, y: -crop.origin.y))
        let sx = dest.width / max(1, crop.width)
        let sy = dest.height / max(1, crop.height)
        var placed = cropped
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: dest.minX, y: dest.minY))
            .cropped(to: dest)
        if opacity < 0.999 {
            let fade = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: opacity)).cropped(to: dest)
            placed = placed.applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: fade
            ])
        }
        return placed
    }

    private static func solidPatch(dest: CGRect, effect: EffectPreset, scaleFactor: CGFloat) -> CIImage {
        let color: CIColor
        switch effect.style {
        case .colorWash:
            color = CIColor(red: 1, green: 0.2, blue: 0.55, alpha: effect.fillOpacity * 0.85)
        case .warningTape:
            color = CIColor(red: 1, green: 0.85, blue: 0.1, alpha: effect.fillOpacity)
        default:
            color = CIColor(red: 0, green: 0, blue: 0, alpha: effect.fillOpacity)
        }
        var image = CIImage(color: color).cropped(to: dest)

        if effect.style == .label || effect.style == .warningTape || effect.style == .sticker {
            // Text/sticker drawn as overlay bitmap for clarity
            if let cg = drawAnnotation(dest: dest, effect: effect, scaleFactor: scaleFactor) {
                let annotated = CIImage(cgImage: cg)
                image = annotated.composited(over: image)
            }
        }
        return image
    }

    private static func roundedMask(dest: CGRect, corner: Double, feather: Double) -> CIImage {
        let radius = max(0, corner)
        // Approximate rounded rect via generator + morphology when needed.
        let color = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        var mask = CIImage(color: color).cropped(to: dest)
        if radius > 0.5 {
            // Soften outer edge
            mask = mask.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(0.5, feather)])
                .cropped(to: dest.insetBy(dx: -feather, dy: -feather))
                .cropped(to: dest)
        }
        return mask
    }

    private static func drawAnnotation(dest: CGRect, effect: EffectPreset, scaleFactor: CGFloat) -> CGImage? {
        let w = max(1, Int(dest.width))
        let h = max(1, Int(dest.height))
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            let rect = NSRect(x: 0, y: 0, width: w, height: h)
            if effect.style == .label || effect.style == .warningTape {
                let text = "\(effect.labelEmoji) \(effect.labelText)".trimmingCharacters(in: .whitespaces)
                let fontSize = max(10, min(rect.width, rect.height) * 0.28)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: fontSize),
                    .foregroundColor: effect.style == .warningTape ? NSColor.black : NSColor.white
                ]
                let ns = NSString(string: text)
                let size = ns.size(withAttributes: attrs)
                ns.draw(
                    at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2),
                    withAttributes: attrs
                )
            }
            if effect.style == .sticker {
                let config = NSImage.SymbolConfiguration(pointSize: min(rect.width, rect.height) * 0.45, weight: .bold)
                if let symbol = NSImage(systemSymbolName: effect.sticker.rawValue, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    let side = min(rect.width, rect.height) * 0.55
                    let destRect = NSRect(
                        x: (rect.width - side) / 2,
                        y: (rect.height - side) / 2,
                        width: side,
                        height: side
                    )
                    NSColor.white.set()
                    symbol.draw(in: destRect)
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}
