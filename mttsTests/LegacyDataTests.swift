import Foundation
import Testing
@testable import mtts

@MainActor
struct LegacyDataTests {
    private let root = FileManager.default.temporaryDirectory
        .appending(path: "mtts-legacy-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func makeFolder(_ name: String, containing file: String, text: String) throws -> URL {
        let folder = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appending(path: file))
        return folder
    }

    private func contents(of url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func movesTheOldFolderWhenThereIsNoNewOne() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try makeFolder("Beatvox", containing: "dataset.json", text: "takes")
        let new = root.appending(path: "nested/mtts", directoryHint: .isDirectory)

        #expect(LegacyData.moveFolder(from: old, to: new))
        #expect(!exists(old))
        #expect(try contents(of: new.appending(path: "dataset.json")) == "takes")
    }

    @Test func neverOverwritesTheNewFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try makeFolder("Beatvox", containing: "dataset.json", text: "old")
        let new = try makeFolder("mtts", containing: "dataset.json", text: "new")

        #expect(!LegacyData.moveFolder(from: old, to: new))
        #expect(try contents(of: old.appending(path: "dataset.json")) == "old")
        #expect(try contents(of: new.appending(path: "dataset.json")) == "new")
    }

    @Test func replacesAnEmptyNewFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try makeFolder("Beatvox", containing: "dataset.json", text: "takes")
        let new = try makeFolder("mtts", containing: ".DS_Store", text: "")

        #expect(LegacyData.moveFolder(from: old, to: new))
        #expect(!exists(old))
        #expect(try contents(of: new.appending(path: "dataset.json")) == "takes")
    }

    @Test func doesNothingWithoutAnOldFolder() {
        defer { try? FileManager.default.removeItem(at: root) }
        let new = root.appending(path: "mtts", directoryHint: .isDirectory)

        #expect(!LegacyData.moveFolder(from: root.appending(path: "Beatvox"), to: new))
        #expect(!exists(new))
    }

    @Test func copiesOnlyMissingPreferences() throws {
        let suite = "mtts-legacy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("kept", forKey: "a")
        let old: [String: Any] = ["a": "old", "b": ["L": "R"], "unrelated": 1]

        let copied = LegacyData.copyDefaults(["a", "b", "c"], from: old, to: defaults)

        #expect(copied == ["b"])
        #expect(defaults.string(forKey: "a") == "kept")
        #expect(defaults.dictionary(forKey: "b") as? [String: String] == ["L": "R"])
        #expect(defaults.object(forKey: "unrelated") == nil)
    }

    @Test func copiesNothingWithoutOldPreferences() throws {
        let suite = "mtts-legacy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(LegacyData.copyDefaults(["a"], from: nil, to: defaults).isEmpty)
        #expect(defaults.object(forKey: "a") == nil)
    }

    @Test func carriesOverTheHeadphoneChoices() {
        #expect(Set(LegacyData.defaultsKeys) == [AppModel.deviceKeyDefaultsKey, HeadphoneDeviceMonitor.overridesKey])
    }
}
