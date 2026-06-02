import Foundation

/// Which `.lproj` language folders are kept (excluded) during Language Files
/// cleanup. A small always-kept default set (English + Base) plus any extra
/// languages the user opts to keep, persisted in UserDefaults. The effective
/// set is never empty, so cleanup can never wipe the UI's own language.
public enum LanguagePreferences {
    /// Never offered for deletion regardless of user choice.
    public static let alwaysKept: Set<String> = MCConstants.preservedLanguages

    /// A curated list of common languages the user can choose to keep.
    /// (display name, lproj folder name)
    public static let commonLanguages: [(name: String, lproj: String)] = [
        ("French", "fr.lproj"), ("German", "de.lproj"), ("Spanish", "es.lproj"),
        ("Italian", "it.lproj"), ("Portuguese", "pt.lproj"), ("Dutch", "nl.lproj"),
        ("Russian", "ru.lproj"), ("Simplified Chinese", "zh-Hans.lproj"),
        ("Traditional Chinese", "zh-Hant.lproj"), ("Japanese", "ja.lproj"),
        ("Korean", "ko.lproj"), ("Arabic", "ar.lproj"),
    ]

    private static let userKeptKey = "keptLanguages"

    /// Extra lproj folders the user chose to keep (persisted).
    public static var userKept: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: userKeptKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: userKeptKey) }
    }

    /// Effective excluded-from-cleanup set = always-kept ∪ user-kept.
    /// Pass `userKept:` explicitly in tests; defaults to the persisted value.
    public static func effectivePreserved(userKept extra: Set<String>? = nil) -> Set<String> {
        alwaysKept.union(extra ?? userKept)
    }
}
