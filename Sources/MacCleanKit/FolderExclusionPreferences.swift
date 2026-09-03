import Foundation

/// Persisted list of folders the user asked Mac Sai never to scan or delete
/// (issue #141). Mirrors `LanguagePreferences`: `UserDefaults` string array.
/// Tests pass an injected suite / home path so they never touch the real prefs.
public enum FolderExclusionPreferences {
    public static let defaultsKey = "excludedFolders"
    public static let defaultMaxCount = 50

    /// Absolute folder paths currently excluded (normalized).
    public static var paths: [String] {
        get { paths(in: .standard) }
        set { setPaths(newValue, in: .standard) }
    }

    public static func paths(in defaults: UserDefaults) -> [String] {
        PathExclusion.normalized(defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    public static func setPaths(_ paths: [String], in defaults: UserDefaults) {
        defaults.set(PathExclusion.normalized(paths), forKey: defaultsKey)
    }

    /// Adds `path` if the candidate policy allows it. Returns false on reject.
    @discardableResult
    public static func add(
        _ path: String,
        defaults: UserDefaults = .standard,
        homePath: String = NSHomeDirectory(),
        maxCount: Int = defaultMaxCount
    ) -> Bool {
        let existing = paths(in: defaults)
        switch PathExclusion.candidateDecision(
            for: path,
            home: homePath,
            maxCount: maxCount,
            existing: existing
        ) {
        case .allow:
            let canonical = SafetyGuard.canonicalizeMacOSFirmlinks(
                path.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            var next = existing.filter { !PathExclusion.isInside($0, root: canonical) }
            next.append(canonical)
            setPaths(next, in: defaults)
            return true
        case .reject:
            return false
        }
    }

    public static func remove(
        _ path: String,
        defaults: UserDefaults = .standard
    ) {
        let canonical = SafetyGuard.canonicalizeMacOSFirmlinks(path)
        setPaths(paths(in: defaults).filter { $0 != canonical }, in: defaults)
    }
}
