import Foundation
import Testing
@testable import mtts

struct MotionMathTests {
    private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }
    private func close(_ a: Vector3, _ b: Vector3) -> Bool { close(a.x, b.x) && close(a.y, b.y) && close(a.z, b.z) }

    @Test func quarterTurnAboutVerticalTurnsForwardToTheLeft() {
        let turned = Quaternion(axis: .unitZ, angle: .pi / 2).rotate(.unitY)
        #expect(close(turned, Vector3(-1, 0, 0)))
    }

    @Test func positivePitchLiftsTheNose() {
        let nose = Quaternion(pitch: 0.3, roll: 0, yaw: 0).rotate(.unitY)
        #expect(nose.z > 0)
        #expect(close(nose.length, 1))
    }

    @Test func eulerOrderIsYawThenPitchThenRoll() {
        let (pitch, roll, yaw) = (0.4, -0.7, 1.1)
        let v = Vector3(0.3, -0.5, 0.8)
        let stepwise = Quaternion(axis: .unitZ, angle: yaw).rotate(
            Quaternion(axis: .unitX, angle: pitch).rotate(
                Quaternion(axis: .unitY, angle: roll).rotate(v)))
        #expect(close(Quaternion(pitch: pitch, roll: roll, yaw: yaw).rotate(v), stepwise))
    }

    private static let pi = Double.pi
    private static let wrapCases: [(Double, Double)] = [
        (0, 0), (pi, pi), (-pi, pi), (1.5 * pi, -0.5 * pi), (-1.5 * pi, 0.5 * pi), (7, 7 - 2 * pi),
    ]

    @Test(arguments: wrapCases)
    func wrapsAnglesIntoHalfOpenRange(input: Double, expected: Double) {
        #expect(close(Angles.wrapped(input), expected))
    }

    @Test(arguments: [(0.0, 30.0, 50.0), (37.0, 20.0, 50.0), (120.0, 30.0, 200.0),
                      (100.0, 1.0, 100.0), (0.003, 0.002, 0.005), (-450.0, 30.0, 500.0)])
    func scopeScaleSnapsToOneTwoFiveSteps(value: Double, minimum: Double, expected: Double) {
        #expect(close(ScopeScale.niceCeiling(value, minimum: minimum), expected, 1e-12))
    }

    @Test func traceInterpolatesAndHoldsTheEnds() {
        let samples = [MotionSample(t: 0, rotation: (0, 0, 0)), MotionSample(t: 1, rotation: (2, 0, 0))]
        #expect(Trace.value(at: 0.25, in: samples, read: \.rx) == 0.5)
        #expect(Trace.value(at: -1, in: samples, read: \.rx) == 0)
        #expect(Trace.value(at: 5, in: samples, read: \.rx) == 2)
        #expect(Trace.value(at: 0.5, in: [], read: \.rx) == nil)
    }

    @Test func poseInterpolationTakesTheShortWayAcrossTheYawSeam() throws {
        let samples = [MotionSample(t: 0, attitude: (0, 0, 3.0)), MotionSample(t: 1, attitude: (0, 0, -3.0))]
        let pose = try #require(HeadPose.interpolated(in: samples, at: 0.5, yawReference: 0))
        #expect(abs(pose.yaw) > 3.1)
    }

    @Test func poseInterpolationWrapsRollToo() throws {
        let samples = [MotionSample(t: 0, attitude: (0, 3.0, 0)), MotionSample(t: 1, attitude: (0, -3.0, 0))]
        let pose = try #require(HeadPose.interpolated(in: samples, at: 0.5, yawReference: 0))
        #expect(abs(pose.roll) > 3.1)
    }

    @Test func windowFindsSamplesWithoutCopying() {
        let samples = (0..<10).map { MotionSample(t: Double($0)) }
        #expect(Trace.lowerBound(3.5, in: samples) == 4)
        #expect(Trace.lowerBound(-1, in: samples) == 0)
        #expect(Trace.lowerBound(20, in: samples) == 10)
        #expect(Trace.window(from: 2, to: 5, in: samples).map(\.t) == [2, 3, 4])
        #expect(Trace.window(from: 5, to: 2, in: samples).isEmpty)
        #expect(Trace.window(from: 0, to: 1, in: []).isEmpty)
    }

    @Test func liveEdgeNeverStepsBackWithinAStream() {
        let edge = LiveEdge(stream: 1, time: 10)
        #expect(edge.advanced(to: 9.9, stream: 1).time == 10)
        #expect(edge.advanced(to: 10.2, stream: 1).time == 10.2)
        #expect(edge.advanced(to: 3, stream: 2) == LiveEdge(stream: 2, time: 3))
    }

    @Test func scopeScaleSurvivesAZeroMinimum() {
        #expect(ScopeScale.niceCeiling(0, minimum: 0) == 1)
    }

    @Test func poseYawIsRelativeToTheRecenterPoint() {
        let pose = HeadPose(sample: MotionSample(t: 0, attitude: (0.1, 0.2, 0.5)), yawReference: 0.4)
        #expect(close(pose.yaw, 0.1))
        #expect(pose.pitch == 0.1)
        #expect(pose.roll == 0.2)
    }

    @Test func frameWithoutAnEdgeHasNoPose() {
        let frame = LiveFrame(samples: [MotionSample(t: 0)], edge: nil, yawReference: 0)
        #expect(frame.pose == nil)
        #expect(frame.value(\.rx) == nil)
    }

    @Test(arguments: [(12.34, 1, "+12.3"), (-4.0, 0, "−4"), (-0.04, 1, "0.0"), (0.0, 0, "0")])
    func signedFormatting(value: Double, decimals: Int, expected: String) {
        #expect(Format.signed(value, decimals: decimals) == expected)
    }

    @Test(arguments: [(5, "battery.0percent"), (30, "battery.25percent"), (50, "battery.50percent"),
                      (80, "battery.75percent"), (100, "battery.100percent")])
    @MainActor func batterySymbols(percent: Int, symbol: String) {
        #expect(BatteryMetric.symbol(for: percent) == symbol)
    }
}
