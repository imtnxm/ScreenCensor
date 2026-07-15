import AppKit
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

protocol ScreenCaptureManagerDelegate: AnyObject {
    func screenCaptureManager(_ manager: ScreenCaptureManager, didOutput pixelBuffer: CVPixelBuffer)
    func screenCaptureManager(_ manager: ScreenCaptureManager, didFail error: Error)
}

enum ScreenCaptureError: LocalizedError {
    case noDisplay
    case streamUnavailable

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display available for capture."
        case .streamUnavailable:
            return "Screen capture stream is unavailable."
        }
    }
}

final class ScreenCaptureManager: NSObject {
    weak var delegate: ScreenCaptureManagerDelegate?

    private let outputQueue = DispatchQueue(label: "com.screencensor.capture", qos: .userInitiated)
    private var stream: SCStream?
    private var configuration = CensorConfiguration()
    private var excludedWindowID: CGWindowID = 0
    private var isRunning = false

    func updateConfiguration(_ configuration: CensorConfiguration) {
        self.configuration = configuration
    }

    func start(excludingWindowID windowID: CGWindowID) async throws {
        if isRunning {
            await stop()
        }

        excludedWindowID = windowID

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw ScreenCaptureError.noDisplay
        }

        let excludedWindows = content.windows.filter { $0.windowID == windowID }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = false
        streamConfig.showsCursor = false
        streamConfig.queueDepth = configuration.performanceMode.queueDepth
        streamConfig.width = display.width
        streamConfig.height = display.height
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.colorSpaceName = CGColorSpace.sRGB

        let fps = configuration.performanceMode.targetFrameRate
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))

        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()

        self.stream = stream
        isRunning = true
    }

    func stop() async {
        guard let stream else {
            isRunning = false
            return
        }

        do {
            try await stream.stopCapture()
        } catch {
            // Best-effort stop; report but clear local state either way.
            delegate?.screenCaptureManager(self, didFail: error)
        }

        self.stream = nil
        isRunning = false
    }

    func restartIfNeeded() async throws {
        guard isRunning else { return }
        let windowID = excludedWindowID
        try await start(excludingWindowID: windowID)
    }
}

extension ScreenCaptureManager: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Retain the pixel buffer independently of the transient sample buffer.
        delegate?.screenCaptureManager(self, didOutput: pixelBuffer)
    }
}

extension ScreenCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRunning = false
        delegate?.screenCaptureManager(self, didFail: error)
    }
}
