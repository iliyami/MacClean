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

    /// Human-readable English name for an lproj folder, e.g. "fr.lproj" → "French",
    /// "zh-Hans.lproj" → "Chinese (Simplified)". Falls back to the raw code.
    /// Always uses a fixed en_US locale so the result is deterministic across
    /// CI machines and non-English user accounts.
    public static func displayName(forLproj lproj: String) -> String {
        let code = lproj.hasSuffix(".lproj") ? String(lproj.dropLast(6)) : lproj
        let en = Locale(identifier: "en_US")
        // forIdentifier handles region/script variants (e.g. zh-Hans, pt-BR, en_GB).
        // forLanguageCode handles plain language codes (e.g. fr, de, ja).
        // Raw code is the final fallback for anything Locale doesn't recognise.
        return en.localizedString(forIdentifier: code)
            ?? en.localizedString(forLanguageCode: code)
            ?? code
    }

    // MARK: - Selectable list for Settings

    /// Languages the user can choose to keep/remove: those actually found on
    /// disk, minus the always-kept defaults. Sorted by display name.
    public static func selectableLanguages() -> [(name: String, lproj: String)] {
        discoveredLproj.subtracting(alwaysKept)
            .map { (displayName(forLproj: $0), $0) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
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
