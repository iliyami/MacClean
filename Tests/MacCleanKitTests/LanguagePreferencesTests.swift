import XCTest
@testable import MacCleanKit

final class LanguagePreferencesTests: XCTestCase {
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
    func testCommonLanguagesAreValidLproj() {
        for lang in LanguagePreferences.commonLanguages {
            XCTAssertTrue(lang.lproj.hasSuffix(".lproj"))
            XCTAssertFalse(lang.name.isEmpty)
        }
    }
}
