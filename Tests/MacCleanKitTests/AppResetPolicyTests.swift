import XCTest
@testable import MacCleanKit

final class AppResetPolicyTests: XCTestCase {

    private let bundle = URL(filePath: "/Applications/Foo.app")

    private func item(_ path: String) -> URL {
        URL(filePath: path)
    }

    private func homeLibrary(_ subdir: String, _ name: String) -> URL {
        MCConstants.userLibrary.appending(path: subdir).appending(path: name)
    }

    // MARK: - Resetable (issue #52: caches, preferences, saved state)

    func testCachesAreResetable() {
        let url = homeLibrary("Caches", "com.example.foo")
        XCTAssertEqual(AppResetPolicy.decision(for: url, appBundle: bundle), .resetable)
        XCTAssertTrue(AppResetPolicy.isResetable(url: url, appBundle: bundle))
    }

    func testPreferencesAreResetable() {
        let url = homeLibrary("Preferences", "com.example.foo.plist")
        XCTAssertEqual(AppResetPolicy.decision(for: url, appBundle: bundle), .resetable)
    }

    func testSavedApplicationStateIsResetable() {
        let url = homeLibrary("Saved Application State", "com.example.foo.savedState")
        XCTAssertEqual(AppResetPolicy.decision(for: url, appBundle: bundle), .resetable)
    }

    func testLogsCookiesHTTPStoragesWebKitAreResetable() {
        XCTAssertEqual(
            AppResetPolicy.decision(for: homeLibrary("Logs", "Foo.log"), appBundle: bundle),
            .resetable
        )
        XCTAssertEqual(
            AppResetPolicy.decision(for: homeLibrary("Cookies", "com.example.foo.binarycookies"), appBundle: bundle),
            .resetable
        )
        XCTAssertEqual(
            AppResetPolicy.decision(for: homeLibrary("HTTPStorages", "com.example.foo"), appBundle: bundle),
            .resetable
        )
        XCTAssertEqual(
            AppResetPolicy.decision(for: homeLibrary("WebKit", "com.example.foo"), appBundle: bundle),
            .resetable
        )
    }

    // MARK: - Never the bundle

    func testAppBundleIsNeverResetable() {
        XCTAssertEqual(AppResetPolicy.decision(for: bundle, appBundle: bundle), .keepBundle)
        XCTAssertFalse(AppResetPolicy.isResetable(url: bundle, appBundle: bundle))
    }

    func testFileInsideAppBundleIsNeverResetable() {
        let nested = bundle.appending(path: "Contents/Info.plist")
        XCTAssertEqual(AppResetPolicy.decision(for: nested, appBundle: bundle), .keepBundle)
    }

    // MARK: - User data (fresh-install v1 does not wipe documents / licenses)

    func testApplicationSupportIsKept() {
        let url = homeLibrary("Application Support", "Foo")
        XCTAssertEqual(AppResetPolicy.decision(for: url, appBundle: bundle), .keepUserData)
        XCTAssertFalse(AppResetPolicy.isResetable(url: url, appBundle: bundle))
    }

    func testContainersAreKept() {
        XCTAssertEqual(
            AppResetPolicy.decision(for: homeLibrary("Containers", "com.example.foo"), appBundle: bundle),
            .keepUserData
        )
        XCTAssertEqual(
            AppResetPolicy.decision(
                for: homeLibrary("Group Containers", "group.com.example.foo"),
                appBundle: bundle
            ),
            .keepUserData
        )
    }

    func testApplicationScriptsAreKept() {
        XCTAssertEqual(
            AppResetPolicy.decision(for: homeLibrary("Application Scripts", "com.example.foo"), appBundle: bundle),
            .keepUserData
        )
    }

    // MARK: - System integration

    func testLaunchAgentsAreKept() {
        XCTAssertEqual(
            AppResetPolicy.decision(for: homeLibrary("LaunchAgents", "com.example.foo.plist"), appBundle: bundle),
            .keepSystemIntegration
        )
    }

    func testPlugInsAndHelpersAreKept() {
        XCTAssertEqual(
            AppResetPolicy.decision(for: homeLibrary("Internet Plug-Ins", "Foo.plugin"), appBundle: bundle),
            .keepSystemIntegration
        )
        XCTAssertEqual(
            AppResetPolicy.decision(for: homeLibrary("PreferencePanes", "Foo.prefPane"), appBundle: bundle),
            .keepSystemIntegration
        )
        XCTAssertEqual(
            AppResetPolicy.decision(
                for: homeLibrary("PrivilegedHelperTools", "com.example.foo"),
                appBundle: bundle
            ),
            .keepSystemIntegration
        )
    }

    func testSystemLaunchDaemonIsKept() {
        let url = URL(filePath: "/Library/LaunchDaemons/com.example.foo.plist")
        XCTAssertEqual(AppResetPolicy.decision(for: url, appBundle: bundle), .keepSystemIntegration)
    }

    // MARK: - Prefix boundary (Caches vs CachesEvil)

    func testCachePrefixDoesNotMatchSiblingDirectory() {
        let sibling = MCConstants.userLibrary.appending(path: "CachesEvil").appending(path: "com.example.foo")
        XCTAssertNotEqual(AppResetPolicy.decision(for: sibling, appBundle: bundle), .resetable)
    }

    // MARK: - Filter

    func testFilterKeepsOnlySelectedResetableItems() {
        let cache = FileItem(
            url: homeLibrary("Caches", "com.example.foo"),
            name: "com.example.foo", size: 10, allocatedSize: 10, isDirectory: true
        )
        let prefs = FileItem(
            url: homeLibrary("Preferences", "com.example.foo.plist"),
            name: "com.example.foo.plist", size: 2, allocatedSize: 2, isDirectory: false
        )
        let support = FileItem(
            url: homeLibrary("Application Support", "Foo"),
            name: "Foo", size: 99, allocatedSize: 99, isDirectory: true
        )
        let bundleItem = FileItem(
            url: bundle, name: "Foo.app", size: 1000, allocatedSize: 1000, isDirectory: true
        )

        let filtered = AppResetPolicy.resetableItems(
            from: [cache, prefs, support, bundleItem],
            selected: [cache.url, support.url, bundle],
            appBundle: bundle
        )
        XCTAssertEqual(filtered.map(\.url), [cache.url],
                       "only selected resetable files; prefs was unchecked, support and bundle excluded")
    }

    func testFilterEmptyWhenNothingResetableSelected() {
        let support = FileItem(
            url: homeLibrary("Application Support", "Foo"),
            name: "Foo", size: 99, allocatedSize: 99, isDirectory: true
        )
        let filtered = AppResetPolicy.resetableItems(
            from: [support],
            selected: [support.url],
            appBundle: bundle
        )
        XCTAssertTrue(filtered.isEmpty)
    }
}
