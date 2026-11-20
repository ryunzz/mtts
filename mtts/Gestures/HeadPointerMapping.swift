import CoreGraphics
import Foundation

/// Where on the screen the head is pointing. Facing center lands in the middle of the screen;
/// turning `reachDegrees` reaches the side edges, and nodding a bit less reaches top and bottom
/// (heads move less up and down than sideways).
struct HeadPointerMapping: Equatable, Sendable {
    var reachDegrees: Double = 20
    var verticalShare: Double = 0.6
    var invertX = false
    var invertY = false

    /// Maps a pose to a point in `bounds` (global display coordinates, origin top left).
    /// `pitchReference` is the pitch that counts as level.
    func point(for pose: HeadPose, pitchReference: Double, in bounds: CGRect) -> CGPoint {
        let reach = reachDegrees * .pi / 180
        // Positive yaw is a turn to the left; positive pitch is looking up.
        var x = -pose.yaw / reach
        var y = -(pose.pitch - pitchReference) / (reach * verticalShare)
        if invertX { x = -x }
        if invertY { y = -y }
        x = min(max(x, -1), 1)
        y = min(max(y, -1), 1)
        return CGPoint(x: bounds.midX + x * bounds.width / 2,
                       y: bounds.midY + y * bounds.height / 2)
    }
}
