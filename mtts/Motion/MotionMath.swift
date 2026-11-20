import Foundation

/// A 3D vector in the headphones' frame: x runs ear to ear, y points forward, z points up.
struct Vector3: Hashable, Sendable {
    let x: Double, y: Double, z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        (self.x, self.y, self.z) = (x, y, z)
    }

    static let unitX = Vector3(1, 0, 0)
    static let unitY = Vector3(0, 1, 0)
    static let unitZ = Vector3(0, 0, 1)

    var length: Double { (x * x + y * y + z * z).squareRoot() }

    var normalized: Vector3 {
        let l = length
        return l > 0 ? self * (1 / l) : self
    }

    func dot(_ o: Vector3) -> Double { x * o.x + y * o.y + z * o.z }

    func cross(_ o: Vector3) -> Vector3 {
        Vector3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (v: Vector3, s: Double) -> Vector3 { Vector3(v.x * s, v.y * s, v.z * s) }
}

/// A rotation (Hamilton convention, scalar first), used to pose the 3D head.
struct Quaternion: Hashable, Sendable {
    let w: Double, x: Double, y: Double, z: Double

    static let identity = Quaternion(w: 1, x: 0, y: 0, z: 0)

    init(w: Double, x: Double, y: Double, z: Double) {
        (self.w, self.x, self.y, self.z) = (w, x, y, z)
    }

    init(axis: Vector3, angle: Double) {
        let n = axis.normalized
        let s = sin(angle / 2)
        self.init(w: cos(angle / 2), x: n.x * s, y: n.y * s, z: n.z * s)
    }

    /// CoreMotion's Euler order: yaw about z (vertical), then pitch about x (ear to ear),
    /// then roll about y (forward).
    init(pitch: Double, roll: Double, yaw: Double) {
        self = Quaternion(axis: .unitZ, angle: yaw)
            * Quaternion(axis: .unitX, angle: pitch)
            * Quaternion(axis: .unitY, angle: roll)
    }

    var conjugate: Quaternion { Quaternion(w: w, x: -x, y: -y, z: -z) }

    static func * (a: Quaternion, b: Quaternion) -> Quaternion {
        Quaternion(
            w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
            x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w)
    }

    func rotate(_ v: Vector3) -> Vector3 {
        let p = self * Quaternion(w: 0, x: v.x, y: v.y, z: v.z) * conjugate
        return Vector3(p.x, p.y, p.z)
    }
}

enum Angles {
    /// Wraps an angle into (−π, π].
    static func wrapped(_ radians: Double) -> Double {
        let twoPi = 2 * Double.pi
        let r = (radians + .pi).truncatingRemainder(dividingBy: twoPi)
        let shifted = (r <= 0 ? r + twoPi : r) - .pi
        return shifted
    }

    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}

/// Head orientation, with yaw measured from where the user last recentered.
struct HeadPose: Hashable, Sendable {
    /// Nod, about the ear-to-ear axis (radians).
    let pitch: Double
    /// Tilt toward a shoulder, about the forward axis (radians).
    let roll: Double
    /// Turn, about the vertical axis, relative to the recenter point (radians).
    let yaw: Double

    init(pitch: Double, roll: Double, yaw: Double) {
        (self.pitch, self.roll, self.yaw) = (pitch, roll, yaw)
    }

    init(sample: MotionSample, yawReference: Double) {
        self.init(pitch: sample.pitch, roll: sample.roll, yaw: Angles.wrapped(sample.yaw - yawReference))
    }

    var orientation: Quaternion { Quaternion(pitch: pitch, roll: roll, yaw: yaw) }

    /// The pose at time `t`, interpolated between the samples around it. Roll and yaw take the
    /// short way across ±180°.
    static func interpolated(in samples: [MotionSample], at t: TimeInterval, yawReference: Double) -> HeadPose? {
        guard let (a, b, f) = Trace.bracket(t, in: samples) else { return nil }
        let yaw = a.yaw + Angles.wrapped(b.yaw - a.yaw) * f
        let roll = a.roll + Angles.wrapped(b.roll - a.roll) * f
        return HeadPose(
            pitch: a.pitch + (b.pitch - a.pitch) * f,
            roll: Angles.wrapped(roll),
            yaw: Angles.wrapped(yaw - yawReference))
    }
}

/// Reading a signal between samples. Samples are in time order.
enum Trace {
    /// Index of the first sample at or after `t` (`samples.count` if none).
    static func lowerBound(_ t: TimeInterval, in samples: [MotionSample]) -> Int {
        var low = 0, high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].t < t { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// The samples with `start <= t < end`, without copying.
    static func window(from start: TimeInterval, to end: TimeInterval, in samples: [MotionSample]) -> ArraySlice<MotionSample> {
        let low = lowerBound(start, in: samples)
        let high = max(low, lowerBound(end, in: samples))
        return samples[low..<high]
    }

    /// The samples on either side of `t` and how far `t` is between them (0...1). Outside the
    /// samples it holds the nearest end.
    static func bracket(_ t: TimeInterval, in samples: [MotionSample]) -> (MotionSample, MotionSample, Double)? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if t <= first.t { return (first, first, 0) }
        if t >= last.t { return (last, last, 0) }
        let i = lowerBound(t, in: samples)
        let a = samples[i - 1], b = samples[i]
        let span = b.t - a.t
        return (a, b, span > 0 ? (t - a.t) / span : 0)
    }

    static func value(at t: TimeInterval, in samples: [MotionSample], read: (MotionSample) -> Double) -> Double? {
        guard let (a, b, f) = bracket(t, in: samples) else { return nil }
        let va = read(a)
        return va + (read(b) - va) * f
    }
}

enum ScopeScale {
    /// The smallest 1–2–5 step at or above `value`, and never below `minimum`. Snapping keeps
    /// a live plot's scale from twitching with every sample.
    static func niceCeiling(_ value: Double, minimum: Double) -> Double {
        let lowest = minimum > 0 ? minimum : 1
        let v = max(abs(value), lowest)
        guard v.isFinite else { return lowest }
        let base = pow(10, floor(log10(v)))
        let target: Double = v * (1 - 1e-9)
        let steps: [Double] = [1, 2, 5]
        let step: Double = steps.first { $0 * base >= target } ?? 10
        return step * base
    }
}

/// Keeps a live plot's right edge from stepping backwards when the measured arrival delay
/// rises. A new stream starts over.
struct LiveEdge: Hashable, Sendable {
    let stream: Int
    let time: TimeInterval

    func advanced(to candidate: TimeInterval, stream newStream: Int) -> LiveEdge {
        LiveEdge(stream: newStream, time: newStream == stream ? max(time, candidate) : candidate)
    }
}

/// What the live views draw in one display frame: the samples, the sample-clock time at the
/// right edge (nil when nothing is streaming), and the yaw recenter point.
struct LiveFrame: Sendable {
    let samples: [MotionSample]
    let edge: TimeInterval?
    let yawReference: Double

    var pose: HeadPose? {
        edge.flatMap { HeadPose.interpolated(in: samples, at: $0, yawReference: yawReference) }
    }

    func value(_ read: (MotionSample) -> Double) -> Double? {
        edge.flatMap { Trace.value(at: $0, in: samples, read: read) }
    }
}
