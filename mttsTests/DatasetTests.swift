import Testing
@testable import mtts

struct DatasetTests {
    private let dataset = Dataset(vocabulary: ["yes", "no"], templates: [
        Template(label: "yes", samples: [], device: "powerbeats-pro-2"),
        Template(label: "no", samples: [], device: "airpods-pro"),
        Template(label: "yes", samples: [], device: nil),
    ])

    @Test func keepsOnlyTakesFromTheCurrentHeadphones() {
        let takes = dataset.templates(forDevice: "powerbeats-pro-2")
        #expect(takes.count == 1)
        #expect(takes.allSatisfy { $0.device == "powerbeats-pro-2" })
    }

    @Test func untaggedTakesFormTheirOwnGroup() {
        let takes = dataset.templates(forDevice: nil)
        #expect(takes.count == 1)
        #expect(takes[0].device == nil)
    }

    @Test func starterVocabularyHasFiveWords() {
        #expect(Dataset.starter.vocabulary.count == 5)
        #expect(Dataset.starter.templates.isEmpty)
    }
}
