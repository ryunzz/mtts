import Foundation

/// Which way the head turned away from center.
enum HeadTurn: String, Sendable {
    case left, right
}

/// Turns head angle into one-shot shortcuts: turn from center past `triggerAngle` and it fires
/// once, then stays quiet until you come back to center (`HeadPose.isStraight`). Holding a turn
/// never repeats.
struct HeadGestureDetector {
    /// How far you have to turn from center to fire (radians). Default 25°.
    var triggerAngle: Double = 25 * .pi / 180
    /// Swap if left and right come out reversed.
    var invert = false

    /// Ready to fire: set when you face center, cleared when a turn fires.
    private(set) var isArmed = false

    init(triggerDegrees: Double = 25, invert: Bool = false) {
        triggerAngle = triggerDegrees * .pi / 180
        self.invert = invert
    }

    mutating func reset() {
        isArmed = false
    }

    /// Feeds the current head pose (yaw relative to the recenter point).
    /// Returns a turn when one has just fired.
    mutating func ingest(_ pose: HeadPose) -> HeadTurn? {
        if pose.isStraight {
            isArmed = true
            return nil
        }
        guard isArmed else { return nil }
        // Yaw grows counterclockwise seen from above, so positive yaw is a turn to the left.
        let yaw = invert ? -pose.yaw : pose.yaw
        guard abs(yaw) >= triggerAngle else { return nil }
        isArmed = false
        return yaw > 0 ? .left : .right
    }
}

extension HeadPose {
    /// Within this many degrees on every axis counts as facing center.
    static let straightToleranceDegrees = 5.0

    var isStraight: Bool {
        let limit = Self.straightToleranceDegrees * .pi / 180
        return abs(pitch) < limit && abs(roll) < limit && abs(yaw) < limit
    }
}
