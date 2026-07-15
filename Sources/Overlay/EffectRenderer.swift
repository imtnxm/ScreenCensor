import AppKit
import CoreImage
import CoreVideo
import Foundation
import Metal
import QuartzCore

/// Renders content-aware censor patches from captured pixel buffers into CALayer contents.
@MainActor
final class EffectRenderer {
    private let ciContext: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
        }
    }

    func renderPatch(
        pixelBuffer: CVPixelBuffer?,
        screenRect: CGRect,
        displaySize: CGSize,
        effect: EffectPreset,
        scaleFactor: CGFloat
    ) -> CGImage? {
        guard let pixelBuffer else {
            return solidImage(size: screenRect.size, effect: effect, scaleFactor: scaleFactor)
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let bufferW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufferH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // Screen rect is AppKit (bottom-left). Pixel buffer is top-left origin in CI.
        let nx = screenRect.origin.x / displaySize.width
        let ny = screenRect.origin.y / displaySize.height
        let nw = screenRect.width / displaySize.width
        let nh = screenRect.height / displaySize.height

        let crop = CGRect(
            x: nx * bufferW,
            y: (1.0 - ny - nh) * bufferH,
            width: max(1, nw * bufferW),
            height: max(1, nh * bufferH)
        ).integral

        var cropped = image.cropped(to: crop)
        cropped = cropped.transformed(by: CGAffineTransform(translationX: -crop.origin.x, y: -crop.origin.y))

        let processed: CIImage
        switch effect.style {
        case .blur:
            let radius = max(2, effect.blurRadius)
            processed = cropped
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: cropped.extent)
        case .pixelate:
            let scale = max(4, effect.pixelScale)
            processed = cropped.applyingFilter(
                "CIPixellate",
                parameters: [kCIInputScaleKey: scale, kCIInputCenterKey: CIVector(x: crop.width / 2, y: crop.height / 2)]
            )
        case .box, .colorWash, .label, .sticker:
            return solidImage(size: screenRect.size, effect: effect, scaleFactor: scaleFactor)
        }

        let extent = processed.extent.integral
        guard extent.width > 0, extent.height > 0,
              let cgImage = ciContext.createCGImage(processed, from: extent, format: .BGRA8, colorSpace: colorSpace)
        else {
            return solidImage(size: screenRect.size, effect: effect, scaleFactor: scaleFactor)
        }
        return cgImage
    }

    private func solidImage(size: CGSize, effect: EffectPreset, scaleFactor: CGFloat) -> CGImage? {
        let w = max(1, Int(size.width * scaleFactor))
        let h = max(1, Int(size.height * scaleFactor))
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
            let alpha = CGFloat(effect.fillOpacity)

            switch effect.style {
            case .box:
                NSColor.black.withAlphaComponent(alpha).setFill()
                rect.fill()
            case .colorWash:
                NSColor.systemPink.withAlphaComponent(alpha * 0.85).setFill()
                rect.fill()
            case .label:
                NSColor.black.withAlphaComponent(alpha).setFill()
                rect.fill()
                let text = "\(effect.labelEmoji) \(effect.labelText)".trimmingCharacters(in: .whitespaces)
                let fontSize = max(10, min(rect.width, rect.height) * 0.22)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: fontSize),
                    .foregroundColor: NSColor.white
                ]
                let ns = NSString(string: text)
                let textSize = ns.size(withAttributes: attrs)
                let origin = NSPoint(
                    x: (rect.width - textSize.width) / 2,
                    y: (rect.height - textSize.height) / 2
                )
                ns.draw(at: origin, withAttributes: attrs)
            case .sticker:
                NSColor.black.withAlphaComponent(alpha * 0.55).setFill()
                rect.fill()
                let config = NSImage.SymbolConfiguration(pointSize: min(rect.width, rect.height) * 0.45, weight: .bold)
                if let symbol = NSImage(systemSymbolName: effect.sticker.rawValue, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    let side = min(rect.width, rect.height) * 0.55
                    let dest = NSRect(
                        x: (rect.width - side) / 2,
                        y: (rect.height - side) / 2,
                        width: side,
                        height: side
                    )
                    NSColor.white.set()
                    symbol.draw(in: dest)
                }
            default:
                NSColor.black.withAlphaComponent(alpha).setFill()
                rect.fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}
