import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import ScreenCaptureKit

struct DisplayInfo: Identifiable, Hashable, Codable, Sendable {
    let id: UInt32
    let name: String
    let pointFrame: CGRect
    let pixelSize: CGSize
    let backingScaleFactor: CGFloat
    let isMain: Bool

    var displayID: CGDirectDisplayID { CGDirectDisplayID(id) }
}

enum DisplayCatalog {
    @MainActor
    static func current() -> [DisplayInfo] {
        NSScreen.screens.enumerated().map { index, screen in
            let id = screen.displayID
            let pixelW = CGFloat(CGDisplayPixelsWide(id))
            let pixelH = CGFloat(CGDisplayPixelsHigh(id))
            return DisplayInfo(
                id: UInt32(id),
                name: screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName,
                pointFrame: screen.frame,
                pixelSize: CGSize(width: max(1, pixelW), height: max(1, pixelH)),
                backingScaleFactor: screen.backingScaleFactor,
                isMain: screen == NSScreen.main
            )
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.uint32Value ?? 0
    }
}

/// Canonical geometry for one captured frame on one display.
struct FrameGeometry: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    /// AppKit screen frame in global points (may have negative origin).
    let pointFrame: CGRect
    /// Captured pixel buffer size.
    let bufferSize: CGSize
    /// Visible content rect inside the buffer (ScreenCaptureKit attachment), in buffer pixels, top-left origin.
    let contentRect: CGRect
    let contentScale: CGFloat
    let scaleFactor: CGFloat

    static func make(
        display: DisplayInfo,
        bufferWidth: Int,
        bufferHeight: Int,
        contentRect: CGRect?,
        contentScale: CGFloat?,
        scaleFactor: CGFloat?
    ) -> FrameGeometry {
        let bufferSize = CGSize(width: CGFloat(bufferWidth), height: CGFloat(bufferHeight))
        let full = CGRect(origin: .zero, size: bufferSize)
        return FrameGeometry(
            displayID: display.displayID,
            pointFrame: display.pointFrame,
            bufferSize: bufferSize,
            contentRect: contentRect?.integral.isNull == false ? contentRect!.integral : full,
            contentScale: contentScale ?? 1,
            scaleFactor: scaleFactor ?? display.backingScaleFactor
        )
    }

    /// Vision normalized (bottom-left) → AppKit global screen points (bottom-left).
    func screenRect(fromVisionNormalized normalized: CGRect) -> CGRect {
        let local = CGRect(
            x: normalized.origin.x * pointFrame.width,
            y: normalized.origin.y * pointFrame.height,
            width: normalized.width * pointFrame.width,
            height: normalized.height * pointFrame.height
        )
        return local.offsetBy(dx: pointFrame.minX, dy: pointFrame.minY)
    }

    /// Vision normalized → pixel crop in buffer space (Core Image / top-left).
    func bufferCrop(fromVisionNormalized normalized: CGRect) -> CGRect {
        let nx = normalized.origin.x
        let ny = normalized.origin.y
        let nw = normalized.width
        let nh = normalized.height

        let x = contentRect.minX + nx * contentRect.width
        // Vision bottom-left → buffer top-left within contentRect.
        let y = contentRect.minY + (1.0 - ny - nh) * contentRect.height
        let w = max(1, nw * contentRect.width)
        let h = max(1, nh * contentRect.height)
        return CGRect(x: x, y: y, width: w, height: h).integral
    }

    /// Overlay-local rect (panel origin at display pointFrame.origin).
    func overlayLocalRect(fromVisionNormalized normalized: CGRect) -> CGRect {
        CGRect(
            x: normalized.origin.x * pointFrame.width,
            y: normalized.origin.y * pointFrame.height,
            width: normalized.width * pointFrame.width,
            height: normalized.height * pointFrame.height
        )
    }
}

struct CapturedFrame: @unchecked Sendable {
    let displayID: CGDirectDisplayID
    let timestamp: CFTimeInterval
    let pixelBuffer: CVPixelBuffer
    let geometry: FrameGeometry

    static func from(
        sampleBuffer: CMSampleBuffer,
        display: DisplayInfo
    ) -> CapturedFrame? {
        guard sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        var contentRect: CGRect?
        var contentScale: CGFloat?
        var scaleFactor: CGFloat?

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let first = attachments.first {
            if let dict = first[.contentRect] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: dict) {
                contentRect = rect
            }
            if let scale = first[.contentScale] as? CGFloat {
                contentScale = scale
            }
            if let sf = first[.scaleFactor] as? CGFloat {
                scaleFactor = sf
            }
        }

        let geometry = FrameGeometry.make(
            display: display,
            bufferWidth: CVPixelBufferGetWidth(pixelBuffer),
            bufferHeight: CVPixelBufferGetHeight(pixelBuffer),
            contentRect: contentRect,
            contentScale: contentScale,
            scaleFactor: scaleFactor
        )

        return CapturedFrame(
            displayID: display.displayID,
            timestamp: CACurrentMediaTime(),
            pixelBuffer: pixelBuffer,
            geometry: geometry
        )
    }
}

/// Single-slot mailbox: always keeps the newest frame, drops older ones.
final class LatestFrameMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: CapturedFrame?

    func publish(_ frame: CapturedFrame) {
        lock.lock()
        self.frame = frame
        lock.unlock()
    }

    func take() -> CapturedFrame? {
        lock.lock()
        defer { lock.unlock() }
        let value = frame
        frame = nil
        return value
    }

    func peek() -> CapturedFrame? {
        lock.lock()
        defer { lock.unlock() }
        return frame
    }
}
