import CoreGraphics
import Testing
@testable import mtts

struct HeadPointerMappingTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private func pose(yaw: Double = 0, pitch: Double = 0) -> HeadPose {
        HeadPose(pitch: pitch * .pi / 180, roll: 0, yaw: yaw * .pi / 180)
    }

    @Test func centerIsMiddleOfScreen() {
        let p = HeadPointerMapping().point(for: pose(), pitchReference: 0, in: screen)
        #expect(p == CGPoint(x: 500, y: 300))
    }

    @Test func turningLeftMovesLeftAndRightMovesRight() {
        let mapping = HeadPointerMapping(reachDegrees: 20)
        #expect(mapping.point(for: pose(yaw: 20), pitchReference: 0, in: screen).x == 0)
        #expect(mapping.point(for: pose(yaw: -20), pitchReference: 0, in: screen).x == 1000)
        #expect(mapping.point(for: pose(yaw: 10), pitchReference: 0, in: screen).x == 250)
    }

    @Test func lookingUpMovesUpRelativeToReference() {
        let mapping = HeadPointerMapping(reachDegrees: 20, verticalShare: 0.5)
        // 10° up from a 5° reference pitch = top edge (reach 20° × 0.5).
        let up = mapping.point(for: pose(pitch: 15), pitchReference: 5 * .pi / 180, in: screen)
        #expect(abs(up.y) < 1e-9)
        let down = mapping.point(for: pose(pitch: -5), pitchReference: 5 * .pi / 180, in: screen)
        #expect(abs(down.y - 600) < 1e-9)
    }

    @Test func clampsToScreenEdges() {
        let p = HeadPointerMapping().point(for: pose(yaw: 90, pitch: -90), pitchReference: 0, in: screen)
        #expect(p == CGPoint(x: 0, y: 600))
    }

    @Test func invertFlipsAxes() {
        let mapping = HeadPointerMapping(reachDegrees: 20, invertX: true, invertY: true)
        let p = mapping.point(for: pose(yaw: 20, pitch: 12), pitchReference: 0, in: screen)
        #expect(p == CGPoint(x: 1000, y: 600))
    }
}
