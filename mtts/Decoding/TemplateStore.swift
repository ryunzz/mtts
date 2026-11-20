import Foundation
import os

struct Dataset: Codable {
    var vocabulary: [String]
    var templates: [Template]

    static let starter = Dataset(vocabulary: ["yes", "no", "next", "back", "stop"], templates: [])

    /// Takes recorded with the given headphones. Motion differs between models and fits, so
    /// takes from other headphones are left out. Untagged takes form their own group.
    func templates(forDevice device: String?) -> [Template] {
        templates.filter { $0.device == device }
    }
}

/// Persists the training set as JSON in Application Support.
enum TemplateStore {
    private static let log = Logger(subsystem: AppInfo.subsystem, category: "dataset")

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: AppInfo.name, directoryHint: .isDirectory)
    }

    static var url: URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "dataset.json")
    }

    static func load() -> Dataset {
        guard let data = try? Data(contentsOf: url) else { return .starter }
        do {
            return try JSONDecoder().decode(Dataset.self, from: data)
        } catch {
            // Keep the unreadable file instead of overwriting it on the next save.
            let backup = url.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            log.error("Dataset unreadable, moved to \(backup.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .starter
        }
    }

    static func save(_ dataset: Dataset) {
        do {
            let data = try JSONEncoder().encode(dataset)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("Failed to save dataset: \(error.localizedDescription, privacy: .public)")
        }
    }
}
