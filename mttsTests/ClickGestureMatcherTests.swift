import Foundation
import Testing
@testable import mtts

struct ClickGestureMatcherTests {
    private let rate = 25.0

    private final class Noise {
        var generator = SplitMix64(seed: 0xC11C_5EED)
        func next() -> Double { Double.random(in: -0.004...0.004, using: &generator) }
    }
    private let noise = Noise()

    private func sample(_ t: Double, accel: (Double, Double, Double) = (0, 0, 0), rx: Double = 0) -> MotionSample {
        MotionSample(t: t,
                     accel: (accel.0 + noise.next(), accel.1 + noise.next(), accel.2 + noise.next()),
                     rotation: (rx + noise.next(), noise.next(), noise.next()))
    }

    /// A jaw-drop-like bump: forward-down acceleration with a little pitch wobble, 0.6 s long.
    private func gesture(start: Double, jitter: Double = 0) -> [MotionSample] {
        (0..<15).map { i in
            let x = Double(i) / 14
            let bump = sin(.pi * x) * (1 + jitter)
            return sample(start + Double(i) / rate, accel: (0, 0.08 * bump, -0.05 * bump),
                          rx: 0.3 * sin(2 * .pi * x) * (1 + jitter))
        }
    }

    private func still(start: Double, seconds: Double) -> [MotionSample] {
        (0..<Int(seconds * rate)).map { sample(start + Double($0) / rate) }
    }

    /// Like a Space-hold take: a little stillness either side of the gesture.
    private var takes: [Template] {
        (0..<5).map { i in
            let jitter = Double(i) * 0.06 - 0.12
            let samples = still(start: 0, seconds: 0.2) + gesture(start: 0.2, jitter: jitter) + still(start: 0.8, seconds: 0.2)
            return Template(label: Template.clickLabel, samples: samples)
        }
    }

    @Test func needsMinimumTakes() {
        #expect(ClickGestureMatcher(templates: Array(takes.prefix(2))) == nil)
        #expect(ClickGestureMatcher(templates: takes) != nil)
    }

    @Test func detectsTheGestureOnceAndIgnoresStillness() {
        var detector = ClickGestureDetector(matcher: ClickGestureMatcher(templates: takes))
        detector.sensitivity = 1.5
        var stream = still(start: 0, seconds: 2)
        stream += gesture(start: 2, jitter: 0.02)
        stream += still(start: 2.6, seconds: 2)
        let clicks = stream.compactMap { detector.ingest($0) }
        #expect(clicks.count == 1)
        // Reported time is the start of the matching window, which covers the gesture.
        if let first = clicks.first { #expect(first > 1.0 && first < 2.6) }
    }

    @Test func stillnessAloneNeverClicks() {
        var detector = ClickGestureDetector(matcher: ClickGestureMatcher(templates: takes))
        detector.sensitivity = 2.5
        #expect(still(start: 0, seconds: 5).compactMap { detector.ingest($0) }.isEmpty)
    }

    @Test func fastHeadTurnsAreNotClicks() {
        var detector = ClickGestureDetector(matcher: ClickGestureMatcher(templates: takes))
        detector.sensitivity = 2.5
        let turn = (0..<50).map { MotionSample(t: Double($0) / rate, rotation: (0, 0, 4)) }
        #expect(turn.compactMap { detector.ingest($0) }.isEmpty)
    }

    @Test func clickLabelStaysOutOfWords() {
        #expect(Template.displayName(Template.clickLabel) == "Click gesture")
        #expect(Template.displayName("yes") == "yes")
    }
}
