import Testing
@testable import mtts

struct HeadGestureDetectorTests {
    private func pose(yawDegrees: Double, pitchDegrees: Double = 0) -> HeadPose {
        HeadPose(pitch: pitchDegrees * .pi / 180, roll: 0, yaw: yawDegrees * .pi / 180)
    }

    @Test func doesNothingUntilCentered() {
        var detector = HeadGestureDetector()
        #expect(detector.ingest(pose(yawDegrees: 40)) == nil)
        #expect(!detector.isArmed)
    }

    @Test func positiveYawIsLeftNegativeIsRight() {
        var detector = HeadGestureDetector()
        _ = detector.ingest(pose(yawDegrees: 0))
        #expect(detector.ingest(pose(yawDegrees: 30)) == .left)
        _ = detector.ingest(pose(yawDegrees: 0))
        #expect(detector.ingest(pose(yawDegrees: -30)) == .right)
    }

    @Test func firesOnceUntilBackAtCenter() {
        var detector = HeadGestureDetector()
        _ = detector.ingest(pose(yawDegrees: 0))
        #expect(detector.ingest(pose(yawDegrees: 30)) == .left)
        #expect(!detector.isArmed)
        #expect(detector.ingest(pose(yawDegrees: 35)) == nil)
        #expect(detector.ingest(pose(yawDegrees: 10)) == nil)  // not center yet
        #expect(detector.ingest(pose(yawDegrees: 30)) == nil)
        _ = detector.ingest(pose(yawDegrees: 1))
        #expect(detector.ingest(pose(yawDegrees: 30)) == .left)
    }

    @Test func smallTurnsDontFire() {
        var detector = HeadGestureDetector(triggerDegrees: 25)
        _ = detector.ingest(pose(yawDegrees: 0))
        #expect(detector.ingest(pose(yawDegrees: 20)) == nil)
        #expect(detector.isArmed)
    }

    @Test func invertSwapsDirections() {
        var detector = HeadGestureDetector(invert: true)
        _ = detector.ingest(pose(yawDegrees: 0))
        #expect(detector.ingest(pose(yawDegrees: 30)) == .right)
    }

    @Test func lookingDownIsNotCenter() {
        var detector = HeadGestureDetector()
        _ = detector.ingest(pose(yawDegrees: 0, pitchDegrees: -20))
        #expect(!detector.isArmed)
        #expect(pose(yawDegrees: 4, pitchDegrees: -4).isStraight)
    }

    @Test func resetDisarms() {
        var detector = HeadGestureDetector()
        _ = detector.ingest(pose(yawDegrees: 0))
        detector.reset()
        #expect(detector.ingest(pose(yawDegrees: 30)) == nil)
    }
}
