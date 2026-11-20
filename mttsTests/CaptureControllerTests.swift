import Testing
@testable import mtts

@MainActor
struct CaptureControllerTests {
    private final class Sink {
        var segments: [[MotionSample]] = []
    }

    private let rate = 25.0

    private func makeController() -> (CaptureController, Sink) {
        let controller = CaptureController()
        let sink = Sink()
        controller.onSegment = { sink.segments.append($0) }
        return (controller, sink)
    }

    /// Feeds `seconds` of samples starting at `start`, all with the same rotation rate.
    private func feed(_ controller: CaptureController, from start: Double, seconds: Double, rotation: Double) -> Double {
        let count = Int(seconds * rate)
        for i in 0..<count {
            controller.ingest(MotionSample(t: start + Double(i) / rate, rotation: (rotation, 0, 0)))
        }
        return start + Double(count) / rate
    }

    @Test func holdProducesOneSegment() {
        let (controller, sink) = makeController()
        controller.begin()
        _ = feed(controller, from: 0, seconds: 0.8, rotation: 0.1)
        controller.end()
        #expect(sink.segments.count == 1)
        #expect(sink.segments[0].count == 20)
        #expect(!controller.isCapturing)
    }

    @Test func tooShortHoldIsDropped() {
        let (controller, sink) = makeController()
        controller.begin()
        _ = feed(controller, from: 0, seconds: 0.08, rotation: 0.1)
        controller.end()
        #expect(sink.segments.isEmpty)
    }

    @Test func holdIncludesPreroll() {
        let (controller, sink) = makeController()
        let t = feed(controller, from: 0, seconds: 1, rotation: 0.01)
        controller.begin()
        _ = feed(controller, from: t, seconds: 0.4, rotation: 0.1)
        controller.end()
        let segment = try? #require(sink.segments.first)
        #expect((segment?.first?.t ?? t) < t)
    }

    @Test func holdStopsAtMaximumLength() {
        let (controller, sink) = makeController()
        controller.begin()
        _ = feed(controller, from: 0, seconds: CaptureController.maxHoldSeconds + 0.5, rotation: 0.1)
        #expect(sink.segments.count == 1)
        #expect(!controller.isCapturing)
    }

    @Test func endWithoutBeginDoesNothing() {
        let (controller, sink) = makeController()
        controller.end()
        _ = feed(controller, from: 0, seconds: 1, rotation: 0.1)
        #expect(sink.segments.isEmpty)
    }

    @Test func autoDetectNeedsCalibrationFirst() {
        let (controller, sink) = makeController()
        controller.autoEnabled = true
        _ = feed(controller, from: 0, seconds: 1, rotation: 0.3)
        #expect(controller.threshold == nil)
        #expect(sink.segments.isEmpty)
    }

    @Test func autoDetectCapturesABurstAfterCalibration() {
        let (controller, sink) = makeController()
        controller.autoEnabled = true
        controller.calibrate()
        var t = feed(controller, from: 0, seconds: 2.2, rotation: 0.001)
        #expect(!controller.isCalibrating)
        #expect(controller.noiseFloor != nil)

        t = feed(controller, from: t, seconds: 0.5, rotation: 0.2)
        #expect(controller.isCapturing)
        _ = feed(controller, from: t, seconds: 1.5, rotation: 0.001)
        #expect(!controller.isCapturing)
        #expect(sink.segments.count == 1)
    }

    @Test func turningAutoDetectOffEndsAnAutoSegment() {
        let (controller, sink) = makeController()
        controller.autoEnabled = true
        controller.calibrate()
        var t = feed(controller, from: 0, seconds: 2.2, rotation: 0.001)
        t = feed(controller, from: t, seconds: 0.5, rotation: 0.2)
        #expect(controller.isCapturing)
        controller.autoEnabled = false
        #expect(!controller.isCapturing)
        #expect(sink.segments.count == 1)
    }
}
