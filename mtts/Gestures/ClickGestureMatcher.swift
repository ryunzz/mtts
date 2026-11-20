import Foundation

extension Template {
    /// The label for takes of the trained click gesture (say, opening your mouth). It isn't a
    /// word, so it stays out of the vocabulary, the word classifier and Signal Check.
    static let clickLabel = "⟨click⟩"

    static func displayName(_ label: String) -> String {
        label == clickLabel ? "Click gesture" : label
    }
}

/// Recognizes one trained gesture in the live stream: a sliding window is compared with
/// every take by DTW, and a close enough match is a click. "Close enough" comes from the
/// takes themselves: how far each take is from its nearest other take.
struct ClickGestureMatcher: Sendable {
    static let minimumTakes = 3
    static let features: FeatureSet = [.acceleration, .rotation]

    /// Distance at sensitivity 1: the farthest any take sits from its nearest neighbour.
    let baseThreshold: Double
    /// How much of the stream to compare at a time, from the takes' typical length (s).
    let windowSeconds: TimeInterval
    /// Faster head rotation than this (rad/s) is looking around, not the gesture.
    let maxRotation: Double
    /// The window needs at least this much motion to be the gesture rather than stillness.
    let minPeakEnergy: Double

    private let takes: [[[Double]]]
    private let scales: [Double]

    init?(templates: [Template]) {
        guard templates.count >= Self.minimumTakes else { return nil }
        let raw = templates.map { MotionFeatures.frames(MotionFeatures.trim($0.samples), set: Self.features) }
        let scales = MotionFeatures.channelScales(raw)
        let takes = raw.map { MotionFeatures.scaled($0, by: scales) }

        var nearest: [Double] = []
        for i in takes.indices {
            let others = takes.indices.filter { $0 != i }.map { DTW.distance(takes[i], takes[$0]) }
            nearest.append(others.min() ?? .infinity)
        }
        let durations = templates.map(\.duration).sorted()
        let peaks = templates.map { take in take.samples.map(Self.rotation).max() ?? 0 }
        let energies = templates.map { take in take.samples.map(MotionFeatures.energy).max() ?? 0 }.sorted()

        self.takes = takes
        self.scales = scales
        baseThreshold = nearest.max() ?? 0
        windowSeconds = min(max(durations[durations.count / 2], 0.4), 2.0)
        maxRotation = max((peaks.max() ?? 0) * 2.5, 0.5)
        minPeakEnergy = energies[energies.count / 2] * 0.4
    }

    /// Best DTW distance from the window to any take, or nil if the window can't be the
    /// gesture (too still, or the head is turning).
    func distance(_ window: [MotionSample]) -> Double? {
        guard window.count >= 4 else { return nil }
        guard (window.map(Self.rotation).max() ?? 0) <= maxRotation else { return nil }
        guard (window.map(MotionFeatures.energy).max() ?? 0) >= minPeakEnergy else { return nil }
        let query = MotionFeatures.scaled(
            MotionFeatures.frames(MotionFeatures.trim(window), set: Self.features), by: scales)
        return takes.map { DTW.distance(query, $0) }.min()
    }

    static func rotation(_ s: MotionSample) -> Double {
        (s.rx * s.rx + s.ry * s.ry + s.rz * s.rz).squareRoot()
    }
}

/// Runs a `ClickGestureMatcher` over the live stream and reports each click once.
struct ClickGestureDetector {
    var matcher: ClickGestureMatcher?
    /// Multiplies the matcher's threshold. Higher clicks more easily.
    var sensitivity = 1.2
    /// Quiet time after a click (s).
    var cooldown: TimeInterval = 1.0

    /// Latest best distance divided by the threshold: at or below 1 is a match. nil when the
    /// window was skipped.
    private(set) var score: Double?

    private var buffer: [MotionSample] = []
    private var quietUntil: TimeInterval = -.infinity
    private var counter = 0

    init(matcher: ClickGestureMatcher? = nil) {
        self.matcher = matcher
    }

    mutating func reset() {
        buffer = []
        score = nil
        quietUntil = -.infinity
    }

    /// Feeds one sample. Returns the time the gesture started when a click fires.
    mutating func ingest(_ sample: MotionSample) -> TimeInterval? {
        guard let matcher else { return nil }
        // Skip the cooldown entirely, so the tail of the gesture that just clicked can't
        // match again once it ends.
        guard sample.t >= quietUntil else { return nil }
        buffer.append(sample)
        let start = sample.t - matcher.windowSeconds
        if let keep = buffer.firstIndex(where: { $0.t >= start }), keep > 0 { buffer.removeFirst(keep) }
        // Every other sample is plenty at 25 Hz.
        counter += 1
        guard counter % 2 == 0, let first = buffer.first, sample.t - first.t >= matcher.windowSeconds * 0.8 else {
            return nil
        }
        let threshold = matcher.baseThreshold * sensitivity
        guard let distance = matcher.distance(buffer), threshold > 0 else {
            score = nil
            return nil
        }
        score = distance / threshold
        guard distance <= threshold else { return nil }
        quietUntil = sample.t + cooldown
        buffer = []
        return first.t
    }
}
