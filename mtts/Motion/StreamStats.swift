import Foundation

/// Health of the headphone motion stream: delivery rate, timing jitter, dropped samples and
/// transport delay. Each new sample returns an updated copy.
struct StreamStats: Hashable, Sendable {
    /// How many recent sample spacings the rate and jitter are measured over.
    static let window = 50
    /// A spacing this many times the typical one means samples were lost.
    static let gapFactor = 1.8
    /// Smoothing for the arrival offset. It follows faster arrivals quickly and slower ones
    /// gradually, so it tracks the transport delay rather than Bluetooth batching.
    static let offsetFallSmoothing = 0.3
    static let offsetRiseSmoothing = 0.02
    /// The live edge trails the newest sample by this many sample spacings, so the plots scroll
    /// smoothly between arrivals instead of stepping.
    static let edgeLead = 1.5
    static let fallbackInterval = 0.04

    private(set) var count = 0
    private(set) var dropped = 0
    private(set) var lastT: TimeInterval?
    /// Recent spacings between sample timestamps (seconds), oldest first.
    private(set) var intervals: [Double] = []
    /// Smoothed `arrival − timestamp`. Includes any offset between the two clocks, which is
    /// exactly what display timing needs; `latency` only reports it when it's plausible.
    private(set) var offset: Double?

    func recording(t: TimeInterval, arrival: TimeInterval) -> StreamStats {
        var next = self
        next.count += 1
        if let lastT, t > lastT {
            let dt = t - lastT
            if intervals.count >= 10, let typical = medianInterval, dt > typical * Self.gapFactor {
                next.dropped += max(Int((dt / typical).rounded()) - 1, 1)
            }
            next.intervals = Array((intervals + [dt]).suffix(Self.window))
        }
        next.lastT = max(t, lastT ?? t)
        let observed = arrival - t
        next.offset = offset.map { current in
            let smoothing = observed < current ? Self.offsetFallSmoothing : Self.offsetRiseSmoothing
            return current + (observed - current) * smoothing
        } ?? observed
        return next
    }

    var meanInterval: Double? {
        intervals.isEmpty ? nil : intervals.reduce(0, +) / Double(intervals.count)
    }

    var medianInterval: Double? {
        guard !intervals.isEmpty else { return nil }
        let sorted = intervals.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Samples per second, including any gaps.
    var rate: Double {
        guard let meanInterval, meanInterval > 0 else { return 0 }
        return 1 / meanInterval
    }

    /// Standard deviation of the sample spacing, ignoring gaps (seconds).
    var jitter: Double? {
        guard let typical = medianInterval else { return nil }
        let regular = intervals.filter { $0 <= typical * Self.gapFactor }
        guard regular.count > 1 else { return nil }
        let mean = regular.reduce(0, +) / Double(regular.count)
        let variance = regular.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(regular.count - 1)
        return variance.squareRoot()
    }

    /// Delay from the sensor reading to the app (seconds), when both share a clock.
    var latency: Double? {
        guard let offset, offset >= 0, offset < 1 else { return nil }
        return offset
    }

    /// The sample-clock time to draw at the right edge of a live plot at `uptime`. It never
    /// runs more than half a sample past the newest reading.
    func displayTime(at uptime: TimeInterval) -> TimeInterval? {
        guard let offset, let lastT else { return nil }
        let interval = medianInterval ?? Self.fallbackInterval
        return min(uptime - offset - interval * Self.edgeLead, lastT + interval / 2)
    }
}
