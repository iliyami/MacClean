import XCTest
@testable import MacCleanKit

final class LanguagePreferencesTests: XCTestCase {

    // MARK: - effectivePreserved (unchanged contract)

    func testDefaultsAlwaysPreserved() {
        let eff = LanguagePreferences.effectivePreserved(userKept: [])
        XCTAssertTrue(eff.contains("en.lproj"))
        XCTAssertTrue(eff.contains("Base.lproj"))
        XCTAssertFalse(eff.isEmpty)
    }

    func testUserAdditionsMerged() {
        let eff = LanguagePreferences.effectivePreserved(userKept: ["fr.lproj", "ja.lproj"])
        XCTAssertTrue(eff.contains("fr.lproj"))
        XCTAssertTrue(eff.contains("ja.lproj"))
        XCTAssertTrue(eff.contains("en.lproj"))   // defaults still there
    }

    func testNeverEmptyEvenWithEmptyUserSet() {
        XCTAssertFalse(LanguagePreferences.effectivePreserved(userKept: []).isEmpty)
    }

    // MARK: - displayName: stable English names

    func testDisplayNameMapsKnownCodes() {
        XCTAssertEqual(LanguagePreferences.displayName(forLproj: "fr.lproj"), "French")
        XCTAssertEqual(LanguagePreferences.displayName(forLproj: "de.lproj"), "German")
        XCTAssertEqual(LanguagePreferences.displayName(forLproj: "ja.lproj"), "Japanese")
        XCTAssertEqual(LanguagePreferences.displayName(forLproj: "es.lproj"), "Spanish")
        XCTAssertEqual(LanguagePreferences.displayName(forLproj: "ko.lproj"), "Korean")
        XCTAssertEqual(LanguagePreferences.displayName(forLproj: "ru.lproj"), "Russian")
    }

    func testDisplayNameHandlesScriptVariants() {
        // These exercise the forIdentifier path (script subtag).
        let simp = LanguagePreferences.displayName(forLproj: "zh-Hans.lproj")
        let trad = LanguagePreferences.displayName(forLproj: "zh-Hant.lproj")
        // Must not fall back to raw code — Locale knows these.
        XCTAssertTrue(simp.localizedCaseInsensitiveContains("Chinese"),
                      "Expected 'Chinese …' for zh-Hans, got '\(simp)'")
        XCTAssertTrue(trad.localizedCaseInsensitiveContains("Chinese"),
                      "Expected 'Chinese …' for zh-Hant, got '\(trad)'")
        // The two must be distinct so the UI doesn't show duplicate rows.
        XCTAssertNotEqual(simp, trad)
    }

    func testDisplayNameHandlesRegionVariants() {
        // pt-BR and en_GB exercise the region subtag path.
        let ptBR = LanguagePreferences.displayName(forLproj: "pt-BR.lproj")
        XCTAssertTrue(ptBR.localizedCaseInsensitiveContains("Portuguese"),
                      "Expected 'Portuguese …' for pt-BR, got '\(ptBR)'")

        let enGB = LanguagePreferences.displayName(forLproj: "en_GB.lproj")
        XCTAssertTrue(enGB.localizedCaseInsensitiveContains("English"),
                      "Expected 'English …' for en_GB, got '\(enGB)'")
    }

    func testDisplayNameFallsBackToRawCodeForUnknown() {
        // "zz" is not a real BCP 47 code; Locale returns nil → raw fallback.
        XCTAssertEqual(LanguagePreferences.displayName(forLproj: "zz.lproj"), "zz")
    }

    func testDisplayNameWorksWithoutLprojSuffix() {
        // Should still produce a name when the suffix is already stripped.
        XCTAssertEqual(LanguagePreferences.displayName(forLproj: "fr"), "French")
    }

    // MARK: - selectableLanguages: excludes alwaysKept

    func testSelectableExcludesAlwaysKept() {
        // Stash the real value and restore it after the test.
        let original = LanguagePreferences.discoveredLproj
        defer { LanguagePreferences.discoveredLproj = original }

        LanguagePreferences.discoveredLproj = ["fr.lproj", "en.lproj", "Base.lproj", "de.lproj"]
        let selectable = LanguagePreferences.selectableLanguages()
        let lprojs = Set(selectable.map(\.lproj))

        XCTAssertTrue(lprojs.contains("fr.lproj"), "fr should be selectable")
        XCTAssertTrue(lprojs.contains("de.lproj"), "de should be selectable")
        XCTAssertFalse(lprojs.contains("en.lproj"), "en is always-kept, must not appear")
        XCTAssertFalse(lprojs.contains("Base.lproj"), "Base is always-kept, must not appear")
    }

    func testSelectableIsSortedByDisplayName() {
        let original = LanguagePreferences.discoveredLproj
        defer { LanguagePreferences.discoveredLproj = original }

        // ja = Japanese, de = German, fr = French → alphabetical: French, German, Japanese
        LanguagePreferences.discoveredLproj = ["ja.lproj", "de.lproj", "fr.lproj"]
        let names = LanguagePreferences.selectableLanguages().map(\.name)
        XCTAssertEqual(names, names.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }),
                       "selectableLanguages() must be sorted by display name")
    }

    func testSelectableIsEmptyWhenNothingDiscovered() {
        let original = LanguagePreferences.discoveredLproj
        defer { LanguagePreferences.discoveredLproj = original }

        LanguagePreferences.discoveredLproj = []
        XCTAssertTrue(LanguagePreferences.selectableLanguages().isEmpty)
    }

    func testSelectableReturnsOnlyDiscoveredMinusAlwaysKept() {
        let original = LanguagePreferences.discoveredLproj
        defer { LanguagePreferences.discoveredLproj = original }

        // Only always-kept languages "discovered" → nothing selectable
        LanguagePreferences.discoveredLproj = Set(LanguagePreferences.alwaysKept)
        XCTAssertTrue(LanguagePreferences.selectableLanguages().isEmpty)
    }
}
