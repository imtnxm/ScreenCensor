import XCTest

final class FrameGeometryTests: XCTestCase {
    func testVisionNormalizedMapsOntoPrimaryDisplay() {
        let display = DisplayInfo(
            id: 1,
            name: "Main",
            pointFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            pixelSize: CGSize(width: 1920, height: 1080),
            backingScaleFactor: 1,
            isMain: true
        )
        let geometry = FrameGeometry.make(
            display: display,
            bufferWidth: 960,
            bufferHeight: 540,
            contentRect: CGRect(x: 0, y: 0, width: 960, height: 540),
            contentScale: 1,
            scaleFactor: 1
        )

        let norm = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let screen = geometry.screenRect(fromVisionNormalized: norm)
        XCTAssertEqual(screen.minX, 480, accuracy: 0.5)
        XCTAssertEqual(screen.minY, 270, accuracy: 0.5)
        XCTAssertEqual(screen.width, 960, accuracy: 0.5)
        XCTAssertEqual(screen.height, 540, accuracy: 0.5)

        let crop = geometry.bufferCrop(fromVisionNormalized: norm)
        // Top-left buffer: y = (1 - 0.25 - 0.5) * 540 = 135
        XCTAssertEqual(crop.minX, 240, accuracy: 1)
        XCTAssertEqual(crop.minY, 135, accuracy: 1)
        XCTAssertEqual(crop.width, 480, accuracy: 1)
        XCTAssertEqual(crop.height, 270, accuracy: 1)
    }

    func testNegativeOriginSecondaryDisplay() {
        let display = DisplayInfo(
            id: 2,
            name: "Left",
            pointFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            pixelSize: CGSize(width: 1920, height: 1080),
            backingScaleFactor: 2,
            isMain: false
        )
        let geometry = FrameGeometry.make(
            display: display,
            bufferWidth: 1920,
            bufferHeight: 1080,
            contentRect: nil,
            contentScale: nil,
            scaleFactor: 2
        )
        let screen = geometry.screenRect(fromVisionNormalized: CGRect(x: 0, y: 0, width: 0.1, height: 0.1))
        XCTAssertEqual(screen.minX, -1920, accuracy: 0.5)
        let local = geometry.overlayLocalRect(fromVisionNormalized: CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1))
        XCTAssertEqual(local.minX, 960, accuracy: 0.5)
        XCTAssertEqual(local.minY, 540, accuracy: 0.5)
    }
}

final class RegionTrackerTests: XCTestCase {
    func testStableIdentityAcrossFrames() {
        let tracker = RegionTracker()
        tracker.updateSettings(TrackerSettings(motion: MotionSettings(smoothing: 0.5, coastSeconds: 0.3, globalPadding: 0.1)))

        let first = tracker.update(
            detections: [
                TrackerInput(
                    part: .faceFemale,
                    normalizedRect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                    confidence: 0.9,
                    effect: .default
                )
            ],
            now: 1.0
        )
        XCTAssertEqual(first.count, 1)
        let id = first[0].id

        let second = tracker.update(
            detections: [
                TrackerInput(
                    part: .faceFemale,
                    normalizedRect: CGRect(x: 0.42, y: 0.41, width: 0.2, height: 0.2),
                    confidence: 0.88,
                    effect: .default
                )
            ],
            now: 1.05
        )
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].id, id)
    }

    func testCoastKeepsTrackBriefly() {
        let tracker = RegionTracker()
        tracker.updateSettings(TrackerSettings(motion: MotionSettings(smoothing: 0.4, coastSeconds: 0.25, globalPadding: 0.1)))
        _ = tracker.update(
            detections: [
                TrackerInput(
                    part: .buttocksExposed,
                    normalizedRect: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
                    confidence: 0.9,
                    effect: .mosaic
                )
            ],
            now: 2.0
        )
        let coasted = tracker.update(detections: [], now: 2.1)
        XCTAssertEqual(coasted.count, 1)
        let expired = tracker.update(detections: [], now: 2.5)
        XCTAssertTrue(expired.isEmpty)
    }
}

final class PartRuleEngineTests: XCTestCase {
    func testDisabledPartFilteredOut() {
        var config = CensorConfiguration()
        var rule = config.rule(for: .hands)
        rule.enabled = false
        config.updateRule(rule)

        let detections = [
            DetectionResult(part: .hands, source: .visionHandPose, normalizedRect: CGRect(x: 0, y: 0, width: 0.1, height: 0.1), confidence: 0.9)
        ]
        let filtered = PartRuleEngine.filter(detections, configuration: config)
        XCTAssertTrue(filtered.isEmpty)
    }
}
