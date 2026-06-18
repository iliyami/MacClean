import Foundation

/// Which `.lproj` language folders are kept (excluded) during Language Files
/// cleanup. A small always-kept default set (English + Base) plus any extra
/// languages the user opts to keep, persisted in UserDefaults. The effective
/// set is never empty, so cleanup can never wipe the UI's own language.
public enum LanguagePreferences {
    /// Never offered for deletion regardless of user choice.
    public static let alwaysKept: Set<String> = MCConstants.preservedLanguages

    // MARK: - Discovered languages (persisted cache)

    private static let discoveredKey = "discoveredLanguages"

    /// The set of `.lproj` folder names discovered from installed app bundles,
    /// persisted across launches so Settings shows something even before the
    /// first background scan completes.
    public static var discoveredLproj: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: discoveredKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: discoveredKey) }
    }

    // MARK: - Display-name mapping

    /// Human-readable name for an lproj folder in the current interface
    /// language, e.g. "fr.lproj" → "法语" / "French". Falls back to the raw code.
    public static func displayName(forLproj lproj: String) -> String {
        let code = lproj.hasSuffix(".lproj") ? String(lproj.dropLast(6)) : lproj
        let locale = Locale(identifier: AppLanguage.current.resolved == .en ? "en_US" : "zh_Hans")
        // forIdentifier handles region/script variants (e.g. zh-Hans, pt-BR, en_GB).
        // forLanguageCode handles plain language codes (e.g. fr, de, ja).
        // Raw code is the final fallback for anything Locale doesn't recognise.
        return locale.localizedString(forIdentifier: code)
            ?? locale.localizedString(forLanguageCode: code)
            ?? code
    }

    // MARK: - Selectable list for Settings

    /// Languages the user can choose to keep/remove: those actually found on
    /// disk, minus the always-kept defaults, GROUPED by display name. A single
    /// language can ship under several folder names (e.g. modern "fr.lproj"
    /// and legacy "French.lproj") — these collapse into one entry whose
    /// `lprojs` covers every variant, so one toggle keeps/removes them all and
    /// the list never shows duplicate rows. Sorted by display name.
    public static func selectableLanguages() -> [(name: String, lprojs: [String])] {
        let candidates = discoveredLproj.subtracting(alwaysKept)
        return Dictionary(grouping: candidates) { displayName(forLproj: $0) }
            .map { (name: $0.key, lprojs: $0.value.sorted()) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - User-kept persistence

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
