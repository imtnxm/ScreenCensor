import CoreML
import CoreVideo
import Foundation
import QuartzCore
import Vision

final class DetectionEngine {
    private let processingQueue = DispatchQueue(label: "com.screencensor.detection", qos: .userInitiated)
    private let stateLock = NSLock()

    private var configuration = CensorConfiguration()
    private var coreMLModel: VNCoreMLModel?
    private var isProcessing = false
    private var framesProcessed: UInt64 = 0

    init() {
        coreMLModel = Self.loadOptionalIntimateZonesModel()
    }

    var processedFrameCount: UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return framesProcessed
    }

    func updateConfiguration(_ configuration: CensorConfiguration) {
        stateLock.lock()
        self.configuration = configuration
        stateLock.unlock()
    }

    /// Processes a frame if the previous frame has finished. Returns `nil` when dropping to keep up.
    func process(pixelBuffer: CVPixelBuffer, displaySize: CGSize) async throws -> FrameDetections? {
        stateLock.lock()
        if isProcessing {
            stateLock.unlock()
            return nil
        }
        isProcessing = true
        let config = configuration
        let model = coreMLModel
        stateLock.unlock()

        defer {
            stateLock.lock()
            isProcessing = false
            framesProcessed += 1
            stateLock.unlock()
        }

        return try await withCheckedThrowingContinuation { continuation in
            processingQueue.async {
                do {
                    let detections = try self.runRequests(
                        on: pixelBuffer,
                        configuration: config,
                        model: model,
                        displaySize: displaySize,
                        timestamp: CACurrentMediaTime()
                    )
                    continuation.resume(returning: detections)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runRequests(
        on imageBuffer: CVPixelBuffer,
        configuration: CensorConfiguration,
        model: VNCoreMLModel?,
        displaySize: CGSize,
        timestamp: CFTimeInterval
    ) throws -> FrameDetections {
        var requests: [VNRequest] = []
        var collected: [DetectionResult] = []
        let collectLock = NSLock()

        if configuration.targets.face {
            let faceRequest = VNDetectFaceRectanglesRequest { request, _ in
                guard let observations = request.results as? [VNFaceObservation] else { return }
                let mapped = observations.map { observation in
                    DetectionResult(
                        kind: .face,
                        normalizedRect: observation.boundingBox,
                        confidence: observation.confidence
                    )
                }
                collectLock.lock()
                collected.append(contentsOf: mapped)
                collectLock.unlock()
            }
            faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
            requests.append(faceRequest)

            let landmarksRequest = VNDetectFaceLandmarksRequest { request, _ in
                guard let observations = request.results as? [VNFaceObservation] else { return }
                var landmarkBoxes: [DetectionResult] = []
                for observation in observations {
                    guard let landmarks = observation.landmarks else { continue }
                    let regions = [landmarks.leftEye, landmarks.rightEye, landmarks.outerLips].compactMap { $0 }
                    for region in regions {
                        let box = Self.boundingBox(for: region.normalizedPoints, in: observation.boundingBox)
                        landmarkBoxes.append(
                            DetectionResult(
                                kind: .faceLandmarks,
                                normalizedRect: box,
                                confidence: observation.confidence
                            )
                        )
                    }
                }
                collectLock.lock()
                collected.append(contentsOf: landmarkBoxes)
                collectLock.unlock()
            }
            requests.append(landmarksRequest)
        }

        // Skin detection is a lightweight placeholder using face regions expanded slightly.
        // A dedicated skin-segmentation model can replace this later without changing the coordinator API.
        if configuration.targets.skin && configuration.targets.face == false {
            let skinProxy = VNDetectFaceRectanglesRequest { request, _ in
                guard let observations = request.results as? [VNFaceObservation] else { return }
                let mapped = observations.map { observation -> DetectionResult in
                    let inset = observation.boundingBox.insetBy(
                        dx: -observation.boundingBox.width * 0.15,
                        dy: -observation.boundingBox.height * 0.2
                    )
                    return DetectionResult(
                        kind: .skin,
                        normalizedRect: Self.clampNormalized(inset),
                        confidence: observation.confidence * 0.5,
                        label: "skin-proxy"
                    )
                }
                collectLock.lock()
                collected.append(contentsOf: mapped)
                collectLock.unlock()
            }
            requests.append(skinProxy)
        } else if configuration.targets.skin {
            // When face detection already runs, expand those boxes after the joint request execution.
        }

        if configuration.targets.intimateZones, let model {
            let mlRequest = VNCoreMLRequest(model: model) { request, _ in
                guard let observations = request.results as? [VNRecognizedObjectObservation] else { return }
                let mapped = observations.map { observation in
                    DetectionResult(
                        kind: .intimateZone,
                        normalizedRect: observation.boundingBox,
                        confidence: observation.confidence,
                        label: observation.labels.first?.identifier
                    )
                }
                collectLock.lock()
                collected.append(contentsOf: mapped)
                collectLock.unlock()
            }
            mlRequest.imageCropAndScaleOption = .scaleFill
            requests.append(mlRequest)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .up, options: [:])
        if !requests.isEmpty {
            try handler.perform(requests)
        }

        if configuration.targets.skin && configuration.targets.face {
            let faceBoxes = collected.filter { $0.kind == .face }
            let skinBoxes = faceBoxes.map { face -> DetectionResult in
                let inset = face.normalizedRect.insetBy(
                    dx: -face.normalizedRect.width * 0.15,
                    dy: -face.normalizedRect.height * 0.2
                )
                return DetectionResult(
                    kind: .skin,
                    normalizedRect: Self.clampNormalized(inset),
                    confidence: face.confidence * 0.5,
                    label: "skin-proxy"
                )
            }
            collected.append(contentsOf: skinBoxes)
        }

        return FrameDetections(
            timestamp: timestamp,
            displaySize: displaySize,
            results: collected
        )
    }

    private static func loadOptionalIntimateZonesModel() -> VNCoreMLModel? {
        let bundle = Bundle.main
        let candidates: [(String, String)] = [
            ("IntimateZones", "mlmodelc"),
            ("IntimateZones", "mlmodel")
        ]

        for (name, ext) in candidates {
            guard let url = bundle.url(forResource: name, withExtension: ext) else { continue }
            do {
                let compiledURL: URL
                if ext == "mlmodel" {
                    compiledURL = try MLModel.compileModel(at: url)
                } else {
                    compiledURL = url
                }

                let mlConfig = MLModelConfiguration()
                mlConfig.computeUnits = MLComputeUnits.all
                let model = try MLModel(contentsOf: compiledURL, configuration: mlConfig)
                return try VNCoreMLModel(for: model)
            } catch {
                continue
            }
        }
        return nil
    }

    private static func boundingBox(for points: [CGPoint], in faceBox: CGRect) -> CGRect {
        guard !points.isEmpty else { return faceBox }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return faceBox
        }

        // Landmark points are normalized relative to the face bounding box.
        let absolute = CGRect(
            x: faceBox.origin.x + minX * faceBox.width,
            y: faceBox.origin.y + minY * faceBox.height,
            width: (maxX - minX) * faceBox.width,
            height: (maxY - minY) * faceBox.height
        )

        let padded = absolute.insetBy(dx: -absolute.width * 0.35, dy: -absolute.height * 0.35)
        return clampNormalized(padded)
    }

    private static func clampNormalized(_ rect: CGRect) -> CGRect {
        let x = max(0, min(1, rect.origin.x))
        let y = max(0, min(1, rect.origin.y))
        let maxX = max(0, min(1, rect.origin.x + rect.size.width))
        let maxY = max(0, min(1, rect.origin.y + rect.size.height))
        return CGRect(x: x, y: y, width: max(0, maxX - x), height: max(0, maxY - y))
    }
}
