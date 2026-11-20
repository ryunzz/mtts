import Foundation
import Testing
@testable import mtts

/// A small seeded generator, so tests that use noise give the same result every run.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct DecodingTests {
    private final class Seeded {
        var generator = SplitMix64(seed: 0xB0A7_5EED)
    }

    /// Each test gets a fresh instance, so its noise is the same on every run.
    private let random = Seeded()

    /// A synthetic "word": a burst of rotation at `frequency` cycles over the segment.
    private func take(_ frequency: Double, axis: Int, frames: Int = 30, noise: Double = 0.01) -> [MotionSample] {
        (0..<frames).map { i in
            let envelope = sin(Double.pi * Double(i) / Double(frames - 1))
            let v = 0.2 * envelope * sin(2 * .pi * frequency * Double(i) / Double(frames))
            let jitter = { noise == 0 ? 0 : Double.random(in: -noise...noise, using: &random.generator) }
            var rotation = (jitter(), jitter(), jitter())
            switch axis {
            case 0: rotation.0 += v
            case 1: rotation.1 += v
            default: rotation.2 += v
            }
            return MotionSample(t: Double(i) / 25, rotation: rotation)
        }
    }

    @Test func dtwIdenticalIsZeroAndWarpTolerant() {
        let a = MotionFeatures.frames(take(2, axis: 0, noise: 0), set: .rotation)
        let stretched = MotionFeatures.frames(take(2, axis: 0, frames: 40, noise: 0), set: .rotation)
        let other = MotionFeatures.frames(take(2, axis: 1, noise: 0), set: .rotation)
        #expect(abs(DTW.distance(a, a)) < 1e-12)
        #expect(DTW.distance(a, stretched) < DTW.distance(a, other))
    }

    @Test func dtwOfEmptySequenceIsInfinite() {
        #expect(DTW.distance([], [[1, 2, 3]]) == .infinity)
    }

    @Test func classifierSeparatesDistinctWords() throws {
        let templates = (0..<6).flatMap { _ in
            [Template(label: "yes", samples: take(2, axis: 0)), Template(label: "no", samples: take(3, axis: 1))]
        }
        let classifier = try #require(TemplateClassifier(templates: templates, featureSet: .all))
        let prediction = classifier.predict(take(3, axis: 1), maxDistance: 10, minConfidence: 0)
        #expect(prediction.best?.label == "no")
        #expect(prediction.accepted)
    }

    @Test func classifierRejectsOutsideThresholds() throws {
        let templates = (0..<4).flatMap { _ in
            [Template(label: "yes", samples: take(2, axis: 0)), Template(label: "no", samples: take(3, axis: 1))]
        }
        let classifier = try #require(TemplateClassifier(templates: templates, featureSet: .all))
        let prediction = classifier.predict(take(3, axis: 1), maxDistance: 0, minConfidence: 0)
        #expect(!prediction.accepted)
    }

    @Test func classifierNeedsTwoWords() {
        let templates = [Template(label: "yes", samples: take(2, axis: 0))]
        #expect(TemplateClassifier(templates: templates, featureSet: .all) == nil)
        #expect(TemplateClassifier(templates: templates, featureSet: []) == nil)
    }

    @Test func evaluationBeatsChanceOnlyWhenSignalExists() throws {
        let real = (0..<8).flatMap { _ in
            [Template(label: "yes", samples: take(2, axis: 0)), Template(label: "no", samples: take(3, axis: 2))]
        }
        let noise = (0..<8).flatMap { _ in
            [Template(label: "yes", samples: take(0, axis: 0, noise: 0.05)),
             Template(label: "no", samples: take(0, axis: 0, noise: 0.05))]
        }
        let signal = try #require(Evaluation.run(templates: real, featureSet: .all, permutations: 200,
                                                 using: &random.generator))
        #expect(signal.accuracy > 0.9)
        #expect(signal.pValue < 0.01)

        // Under pure noise the p-value is uniform, so unseeded this would fail about 1% of runs.
        let null = try #require(Evaluation.run(templates: noise, featureSet: .all, permutations: 200,
                                               using: &random.generator))
        #expect(null.pValue > 0.01)
    }

    @Test func trimDropsQuietPadding() {
        let quiet = (0..<20).map { MotionSample(t: Double($0) / 25) }
        let burst = take(2, axis: 0, noise: 0).map { sample -> MotionSample in
            var shifted = sample
            shifted.t += 0.8
            return shifted
        }
        let tail = quiet.map { sample -> MotionSample in
            var shifted = sample
            shifted.t += 2
            return shifted
        }
        let trimmed = MotionFeatures.trim(quiet + burst + tail)
        #expect(trimmed.count < 40)
        #expect(trimmed.count >= 20)
    }

    @Test func templateDecodesWithoutDeviceField() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","label":"yes","samples":[],"createdAt":0}"#
        let template = try JSONDecoder().decode(Template.self, from: Data(json.utf8))
        #expect(template.device == nil)
        #expect(template.label == "yes")
    }
}
