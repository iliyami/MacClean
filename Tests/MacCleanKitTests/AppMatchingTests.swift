import XCTest
import Foundation
@testable import MacCleanKit

final class AppMatchingTests: XCTestCase {

    private let chrome = AppInfo(
        bundleIdentifier: "com.google.Chrome",
        name: "Google Chrome",
        path: URL(filePath: "/Applications/Google Chrome.app"),
        version: "100.0.4896.127"
    )

    private let chromeHelper = AppInfo(
        bundleIdentifier: "com.google.Chrome.helper",
        name: "Google Chrome Helper",
        path: URL(filePath: "/Applications/Google Chrome Helper.app")
    )

    // MARK: - Level 1: bundle ID exact

    func testBundleIDExactMatch() {
        let patterns = AppMatching.generatePatterns(for: chrome, maxLevel: .bundleIDExact)
        XCTAssertTrue(patterns.contains("com.google.chrome"))
    }

    // MARK: - Level 2: display name

    func testDisplayNameMatch() {
        let patterns = AppMatching.generatePatterns(for: chrome, maxLevel: .displayName)
        XCTAssertTrue(patterns.contains("google chrome"))
    }

    // MARK: - Level 3: app dir name

    func testAppDirNameMatch() {
        let patterns = AppMatching.generatePatterns(for: chrome, maxLevel: .appDirName)
        XCTAssertTrue(patterns.contains("google chrome"))
    }

    // MARK: - Level 4: normalized name

    func testNormalizedNameMatch() {
        let patterns = AppMatching.generatePatterns(for: chrome, maxLevel: .normalizedName)
        XCTAssertTrue(patterns.contains("googlechrome"))
    }

    func testNormalizedNameIncludesNonLetters() {
        // Apps with punctuation/numbers in the name should still produce a
        // useful normalized pattern.
        let app = AppInfo(
            bundleIdentifier: "com.example.MyApp",
            name: "My App 2.0",
            path: URL(filePath: "/Applications/My App.app")
        )
        let patterns = AppMatching.generatePatterns(for: app, maxLevel: .normalizedName)
        XCTAssertTrue(patterns.contains("myapp"),
                      "normalized form should strip punctuation, numbers, and spaces")
    }

    // MARK: - Level 5: bundle ID components

    func testBundleIDComponentsMatch() {
        let patterns = AppMatching.generatePatterns(for: chrome, maxLevel: .bundleIDComponents)
        XCTAssertTrue(patterns.contains("google.chrome"))
    }

    // MARK: - Level 6: base bundle ID (strip suffixes)

    func testBaseBundleIDStripsHelper() {
        let patterns = AppMatching.generatePatterns(for: chromeHelper, maxLevel: .baseBundleID)
        XCTAssertTrue(patterns.contains("com.google.chrome"))
    }

    func testBaseBundleIDStripsAgent() {
        let app = AppInfo(bundleIdentifier: "com.foo.bar.agent", name: "BarAgent", path: URL(filePath: "/x.app"))
        let patterns = AppMatching.generatePatterns(for: app, maxLevel: .baseBundleID)
        XCTAssertTrue(patterns.contains("com.foo.bar"))
    }

    func testBaseBundleIDStripsDaemon() {
        let app = AppInfo(bundleIdentifier: "com.foo.bar.daemon", name: "Daemon", path: URL(filePath: "/x.app"))
        let patterns = AppMatching.generatePatterns(for: app, maxLevel: .baseBundleID)
        XCTAssertTrue(patterns.contains("com.foo.bar"))
    }

    func testBaseBundleIDStripsUpdater() {
        let app = AppInfo(bundleIdentifier: "com.foo.bar.updater", name: "Updater", path: URL(filePath: "/x.app"))
        let patterns = AppMatching.generatePatterns(for: app, maxLevel: .baseBundleID)
        XCTAssertTrue(patterns.contains("com.foo.bar"))
    }

    // MARK: - Level 7: version stripped

    func testVersionStripping() {
        let app = AppInfo(
            bundleIdentifier: "com.example.app2",
            name: "App 2.0.1",
            path: URL(filePath: "/App.app")
        )
        let patterns = AppMatching.generatePatterns(for: app, maxLevel: .versionStripped)
        XCTAssertTrue(patterns.contains("app"))
    }

    // MARK: - Level 8: company name

    func testCompanyName() {
        let patterns = AppMatching.generatePatterns(for: chrome, maxLevel: .companyName)
        XCTAssertTrue(patterns.contains("google"))
    }

    func testAppleCompanyNotExtracted() {
        let app = AppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari",
                          path: URL(filePath: "/Applications/Safari.app"), isAppleApp: true)
        let patterns = AppMatching.generatePatterns(for: app, maxLevel: .companyName)
        XCTAssertFalse(patterns.contains("apple"),
                       "Don't surface 'apple' as a matcher — would match every system file")
    }

    func testShortCompanyNameSkipped() {
        let app = AppInfo(bundleIdentifier: "com.ai.X", name: "X", path: URL(filePath: "/X.app"))
        let patterns = AppMatching.generatePatterns(for: app, maxLevel: .companyName)
        XCTAssertFalse(patterns.contains("ai"), "Company names < 3 chars are too generic")
    }

    // MARK: - Regression: shared-vendor over-matching (#98)

    func testDefaultLevelDoesNotEmitBareVendorToken() {
        // com.tencent.yuanbao must NOT yield "tencent" at the default level, or
        // it would match every Tencent app (WeChat, QQ, ...). The company-name
        // level is opt-in only, never part of the default an uninstaller uses.
        let yuanbao = AppInfo(bundleIdentifier: "com.tencent.yuanbao", name: "Yuanbao",
                              path: URL(filePath: "/Applications/Yuanbao.app"))
        let patterns = AppMatching.generatePatterns(for: yuanbao)
        XCTAssertFalse(patterns.contains("tencent"),
                       "Default matching must not emit the bare vendor token")
    }

    func testUninstallingOneVendorAppDoesNotMatchSibling() {
        // The exact #98 report: uninstalling Tencent Yuanbao also flagged WeChat.
        let yuanbao = AppInfo(bundleIdentifier: "com.tencent.yuanbao", name: "Yuanbao",
                              path: URL(filePath: "/Applications/Yuanbao.app"))
        let patterns = AppMatching.generatePatterns(for: yuanbao)
        XCTAssertFalse(
            AppMatching.filenameMatches("com.tencent.xinWeChat.plist", patterns: patterns),
            "Uninstalling Yuanbao must not match WeChat files (#98)")
        // Yuanbao's own files (and its helpers) still match.
        XCTAssertTrue(AppMatching.filenameMatches("com.tencent.yuanbao.plist", patterns: patterns))
        XCTAssertTrue(AppMatching.filenameMatches("com.tencent.yuanbao.helper.plist", patterns: patterns))
    }

    // MARK: - filenameMatches

    func testFilenameMatchesContainsPattern() {
        let patterns: Set<String> = ["chrome", "google"]
        XCTAssertTrue(AppMatching.filenameMatches("com.google.Chrome.plist", patterns: patterns))
        XCTAssertTrue(AppMatching.filenameMatches("GoogleSoftwareUpdate.plist", patterns: patterns))
    }

    func testFilenameMatchesCaseInsensitive() {
        let patterns: Set<String> = ["chrome"]
        XCTAssertTrue(AppMatching.filenameMatches("GOOGLE.CHROME.PLIST", patterns: patterns))
    }

    func testFilenameMatchesEmptyPatterns() {
        XCTAssertFalse(AppMatching.filenameMatches("anything.txt", patterns: []))
    }

    func testFilenameMatchesNoMatch() {
        XCTAssertFalse(AppMatching.filenameMatches("com.spotify.client.plist",
                                                    patterns: ["chrome", "google"]))
    }

    // MARK: - Library subdirectories list

    func testLibrarySubdirectoriesIncludesEssentials() {
        let essentials = [
            "Application Support", "Caches", "Containers", "Group Containers",
            "Preferences", "Logs", "LaunchAgents",
        ]
        for dir in essentials {
            XCTAssertTrue(AppMatching.librarySubdirectories.contains(dir),
                          "Missing essential subdir: \(dir)")
        }
    }
}
