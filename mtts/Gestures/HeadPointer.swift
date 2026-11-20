import AppKit
import CoreGraphics
import os

/// Moves the system cursor toward the head's target point, eased at display rate so the
/// 25 Hz motion stream doesn't look steppy. Touching the trackpad or mouse pauses it briefly.
/// Posting mouse events needs Accessibility access, like the head shortcuts.
@MainActor
final class HeadPointer {
    var mapping = HeadPointerMapping()
    /// 0…1: how far the cursor moves toward the target each frame. Lower is smoother.
    var smoothing = 0.18
    /// How long the head pointer stays out of the way after you move the mouse yourself.
    static let handOffPause: TimeInterval = 1.2

    private(set) var isRunning = false
    private var target: CGPoint?
    private var current: CGPoint?
    private var lastPosted: CGPoint?
    /// Recent cursor positions on the `systemUptime` clock (the motion timestamps' clock),
    /// so a gesture click lands where you were pointing when it started.
    private var history: [(t: TimeInterval, point: CGPoint)] = []
    private var pausedUntil: TimeInterval = 0
    private var timer: Timer?
    private let log = Logger(subsystem: AppInfo.subsystem, category: "pointer")

    static var screenBounds: CGRect { CGDisplayBounds(CGMainDisplayID()) }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        current = nil
        lastPosted = nil
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        log.info("Head pointer on")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        target = nil
        history = []
    }

    func update(pose: HeadPose, pitchReference: Double) {
        target = mapping.point(for: pose, pitchReference: pitchReference, in: Self.screenBounds)
    }

    /// Where the cursor was at `uptime`, so motion during a gesture doesn't move its click.
    func position(at uptime: TimeInterval) -> CGPoint? {
        history.last(where: { $0.t <= uptime })?.point ?? lastPosted
    }

    private func tick() {
        guard let target else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let actual = CGEvent(source: nil)?.location ?? target
        // Someone moved the mouse since our last move: let them have it for a moment.
        if let lastPosted, hypot(actual.x - lastPosted.x, actual.y - lastPosted.y) > 3 {
            pausedUntil = now + Self.handOffPause
            self.lastPosted = nil
        }
        guard now >= pausedUntil else { return }
        let from = current ?? actual
        let next = CGPoint(x: from.x + (target.x - from.x) * smoothing,
                           y: from.y + (target.y - from.y) * smoothing)
        current = next
        if let lastPosted, hypot(next.x - lastPosted.x, next.y - lastPosted.y) < 0.5 { return }
        move(to: next)
    }

    private func move(to point: CGPoint) {
        let leftDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let type: CGEventType = leftDown ? .leftMouseDragged : .mouseMoved
        if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        } else {
            CGWarpMouseCursorPosition(point)
        }
        lastPosted = point
        let now = ProcessInfo.processInfo.systemUptime
        history.append((now, point))
        if let keep = history.firstIndex(where: { $0.t >= now - 3 }), keep > 0 { history.removeFirst(keep) }
    }
}
