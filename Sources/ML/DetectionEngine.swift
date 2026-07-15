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
    private(set) var modelLoaded = false

    init() {
        coreMLModel = Self.loadNudeNetModel()
        modelLoaded = coreMLModel != nil
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

        let needsFace = configuration.rule(for: .faceFemale).enabled
            || configuration.rule(for: .faceMale).enabled
            || (configuration.useFaceLandmarks && configuration.rule(for: .faceLandmarks).enabled)

        if needsFace {
            let faceRequest = VNDetectFaceRectanglesRequest { request, _ in
                guard let observations = request.results as? [VNFaceObservation] else { return }
                let mapped: [DetectionResult] = observations.map { observation in
                    // NudeNet also returns gendered faces; Vision faces map to both face parts.
                    DetectionResult(
                        part: .faceFemale,
                        source: .visionFace,
                        normalizedRect: observation.boundingBox,
                        confidence: observation.confidence,
                        label: "FACE_VISION"
                    )
                }
                collectLock.lock()
                collected.append(contentsOf: mapped)
                collectLock.unlock()
            }
            faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
            requests.append(faceRequest)

            if configuration.useFaceLandmarks && configuration.rule(for: .faceLandmarks).enabled {
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
                                    part: .faceLandmarks,
                                    source: .visionLandmarks,
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
        }

        if let model {
            let mlRequest = VNCoreMLRequest(model: model) { request, _ in
                let observations = (request.results as? [VNRecognizedObjectObservation]) ?? []
                let mapped = observations.compactMap { observation -> DetectionResult? in
                    guard let label = observation.labels.first?.identifier,
                          let part = BodyPartID.fromNudeNetLabel(label) else { return nil }
                    return DetectionResult(
                        part: part,
                        source: .nudeNet,
                        normalizedRect: observation.boundingBox,
                        confidence: observation.confidence,
                        label: label
                    )
                }
                collectLock.lock()
                collected.append(contentsOf: mapped)
                collectLock.unlock()
            }
            mlRequest.imageCropAndScaleOption = .scaleFill
            requests.append(mlRequest)
        }

        if configuration.usePoseAssist {
            if configuration.rule(for: .hands).enabled {
                let handRequest = VNDetectHumanHandPoseRequest { request, _ in
                    guard let observations = request.results as? [VNHumanHandPoseObservation] else { return }
                    let boxes = PoseAssist.handBoxes(from: observations)
                    collectLock.lock()
                    collected.append(contentsOf: boxes)
                    collectLock.unlock()
                }
                handRequest.maximumHandCount = 4
                requests.append(handRequest)
            }

            let feetEnabled = configuration.rule(for: .feetPose).enabled
                || configuration.rule(for: .feetCovered).enabled
                || configuration.rule(for: .feetExposed).enabled
            if feetEnabled {
                let bodyRequest = VNDetectHumanBodyPoseRequest { request, _ in
                    guard let observations = request.results as? [VNHumanBodyPoseObservation] else { return }
                    let boxes = PoseAssist.feetBoxes(from: observations)
                    collectLock.lock()
                    collected.append(contentsOf: boxes)
                    collectLock.unlock()
                }
                requests.append(bodyRequest)
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .up, options: [:])
        if !requests.isEmpty {
            try handler.perform(requests)
        }

        let filtered = PartRuleEngine.filter(collected, configuration: configuration)

        return FrameDetections(
            timestamp: timestamp,
            displaySize: displaySize,
            pixelBuffer: imageBuffer,
            results: filtered
        )
    }

    private static func loadNudeNetModel() -> VNCoreMLModel? {
        let bundle = Bundle.main
        let candidates: [(String, String)] = [
            ("NudeNet320n", "mlmodelc"),
            ("NudeNet320n", "mlpackage"),
            ("NudeNet320n", "mlmodel"),
            ("IntimateZones", "mlmodelc"),
            ("IntimateZones", "mlmodel")
        ]

        for (name, ext) in candidates {
            guard let url = bundle.url(forResource: name, withExtension: ext) else { continue }
            do {
                let compiledURL: URL
                if ext == "mlmodel" {
                    compiledURL = try MLModel.compileModel(at: url)
                } else if ext == "mlpackage" {
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

        let absolute = CGRect(
            x: faceBox.origin.x + minX * faceBox.width,
            y: faceBox.origin.y + minY * faceBox.height,
            width: (maxX - minX) * faceBox.width,
            height: (maxY - minY) * faceBox.height
        )

        let padded = absolute.insetBy(dx: -absolute.width * 0.35, dy: -absolute.height * 0.35)
        return PartRuleEngine.clampNormalized(padded)
    }
}
