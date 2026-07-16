import AppKit
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import ScreenCaptureKit

protocol ScreenCaptureManagerDelegate: AnyObject {
    func screenCaptureManager(_ manager: ScreenCaptureManager, didOutput frame: CapturedFrame)
    func screenCaptureManager(_ manager: ScreenCaptureManager, displayID: CGDirectDisplayID, didFail error: Error)
}

final class ScreenCaptureManager: NSObject {
    weak var delegate: ScreenCaptureManagerDelegate?

    private let outputQueue = DispatchQueue(label: "com.screencensor.capture", qos: .userInitiated)
    private var configuration = CensorConfiguration()
    private var sessions: [CGDirectDisplayID: DisplayCaptureSession] = [:]
    private var isRunning = false
    private var excludedWindowIDs: Set<CGWindowID> = []

    func updateConfiguration(_ configuration: CensorConfiguration) {
        self.configuration = configuration
    }

    func start(
        displays: [DisplayInfo],
        enabledDisplayIDs: Set<UInt32>,
        excludingWindowIDs: Set<CGWindowID>
    ) async throws {
        await stop()
        excludedWindowIDs = excludingWindowIDs
        isRunning = true

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let targets = displays.filter { enabledDisplayIDs.contains($0.id) }
        guard !targets.isEmpty else {
            throw ScreenCaptureError.noDisplay
        }

        for displayInfo in targets {
            guard let scDisplay = content.displays.first(where: { $0.displayID == displayInfo.displayID }) else {
                continue
            }
            let session = DisplayCaptureSession(
                display: displayInfo,
                scDisplay: scDisplay,
                configuration: configuration,
                excludedWindowIDs: excludedWindowIDs,
                outputQueue: outputQueue,
                onFrame: { [weak self] frame in
                    guard let self else { return }
                    self.delegate?.screenCaptureManager(self, didOutput: frame)
                },
                onError: { [weak self] displayID, error in
                    guard let self else { return }
                    self.delegate?.screenCaptureManager(self, displayID: displayID, didFail: error)
                }
            )
            try await session.start(allWindows: content.windows)
            sessions[displayInfo.displayID] = session
        }

        if sessions.isEmpty {
            throw ScreenCaptureError.noDisplay
        }
    }

    func stop() async {
        isRunning = false
        for session in sessions.values {
            await session.stop()
        }
        sessions.removeAll()
    }

    func restartIfNeeded(
        displays: [DisplayInfo],
        enabledDisplayIDs: Set<UInt32>,
        excludingWindowIDs: Set<CGWindowID>
    ) async throws {
        guard isRunning else { return }
        try await start(
            displays: displays,
            enabledDisplayIDs: enabledDisplayIDs,
            excludingWindowIDs: excludingWindowIDs
        )
    }
}

private final class DisplayCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate {
    let display: DisplayInfo
    private let scDisplay: SCDisplay
    private var configuration: CensorConfiguration
    private let excludedWindowIDs: Set<CGWindowID>
    private let outputQueue: DispatchQueue
    private let onFrame: (CapturedFrame) -> Void
    private let onError: (CGDirectDisplayID, Error) -> Void
    private var stream: SCStream?

    init(
        display: DisplayInfo,
        scDisplay: SCDisplay,
        configuration: CensorConfiguration,
        excludedWindowIDs: Set<CGWindowID>,
        outputQueue: DispatchQueue,
        onFrame: @escaping (CapturedFrame) -> Void,
        onError: @escaping (CGDirectDisplayID, Error) -> Void
    ) {
        self.display = display
        self.scDisplay = scDisplay
        self.configuration = configuration
        self.excludedWindowIDs = excludedWindowIDs
        self.outputQueue = outputQueue
        self.onFrame = onFrame
        self.onError = onError
    }

    func start(allWindows: [SCWindow]) async throws {
        let excluded = allWindows.filter { excludedWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: excluded)

        let scale = configuration.performanceMode.detectionScale
        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = false
        streamConfig.showsCursor = false
        streamConfig.queueDepth = configuration.performanceMode.queueDepth
        streamConfig.width = max(640, Int(Double(display.pixelSize.width) * scale))
        streamConfig.height = max(360, Int(Double(display.pixelSize.height) * scale))
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.colorSpaceName = CGColorSpace.sRGB
        streamConfig.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(configuration.performanceMode.targetFrameRate)
        )

        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        guard let frame = CapturedFrame.from(sampleBuffer: sampleBuffer, display: display) else { return }
        onFrame(frame)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError(display.displayID, error)
    }
}

enum ScreenCaptureError: LocalizedError {
    case noDisplay
    case streamUnavailable

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No enabled display available for capture."
        case .streamUnavailable: return "Screen capture stream is unavailable."
        }
    }
}
