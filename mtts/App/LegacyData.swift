import Foundation
import os

/// mtts was called Beatvox before it was renamed. On launch this carries the training set and
/// headphone choices over from the old name, so earlier takes still count. Recordings stay
/// where they were, in ~/Documents/Beatvox/Sessions.
@MainActor
enum LegacyData {
    static let name = "Beatvox"
    static let defaultsDomain = "com.ryunzz.beatvox"
    /// The last headphones used and any model overrides.
    static let defaultsKeys = [AppModel.deviceKeyDefaultsKey, HeadphoneDeviceMonitor.overridesKey]

    private static let log = Logger(subsystem: AppInfo.subsystem, category: "migration")

    static func migrate() {
        moveFolder(from: URL.applicationSupportDirectory.appending(path: name, directoryHint: .isDirectory),
                   to: TemplateStore.directory)
        copyDefaults(defaultsKeys, from: UserDefaults.standard.persistentDomain(forName: defaultsDomain),
                     to: .standard)
    }

    /// Moves `old` to `new` when `new` is missing or empty. Never overwrites data. Returns
    /// whether it moved.
    @discardableResult
    static func moveFolder(from old: URL, to new: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: old.path(percentEncoded: false)) else { return false }
        let newExists = fileManager.fileExists(atPath: new.path(percentEncoded: false))
        if newExists, !isEmptyFolder(new, fileManager: fileManager) {
            log.info("Kept \(new.path(percentEncoded: false), privacy: .public); \(old.path(percentEncoded: false), privacy: .public) left in place")
            return false
        }
        do {
            if newExists {
                try fileManager.removeItem(at: new)
            }
            try fileManager.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: old, to: new)
            log.info("Moved \(old.path(percentEncoded: false), privacy: .public) to \(new.path(percentEncoded: false), privacy: .public)")
            return true
        } catch {
            log.error("Couldn't move \(old.path(percentEncoded: false), privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// A folder holding nothing but Finder's `.DS_Store`.
    private static func isEmptyFolder(_ url: URL, fileManager: FileManager) -> Bool {
        guard let items = try? fileManager.contentsOfDirectory(atPath: url.path(percentEncoded: false)) else {
            return false
        }
        return items.allSatisfy { $0 == ".DS_Store" }
    }

    /// Copies the `keys` that `defaults` doesn't have yet from `old`. Returns the keys copied.
    @discardableResult
    static func copyDefaults(_ keys: [String], from old: [String: Any]?, to defaults: UserDefaults) -> [String] {
        guard let old else { return [] }
        let missing = keys.filter { old[$0] != nil && defaults.object(forKey: $0) == nil }
        for key in missing {
            defaults.set(old[key], forKey: key)
        }
        if !missing.isEmpty {
            log.info("Copied preferences: \(missing.joined(separator: ", "), privacy: .public)")
        }
        return missing
    }
}
