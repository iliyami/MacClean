import XCTest
@testable import MacCleanKit

final class AppCacheOwnershipTests: XCTestCase {
    private func id(_ path: String) -> String? {
        AppCacheOwnership.owningBundleID(for: URL(filePath: path))
    }

    func testCachesFolderYieldsBundleID() {
        XCTAssertEqual(id("/Users/x/Library/Caches/com.apple.Safari/foo"), "com.apple.Safari")
    }

    func testContainersFolderYieldsBundleID() {
        XCTAssertEqual(id("/Users/x/Library/Containers/com.spotify.client/Data/x"), "com.spotify.client")
    }

    func testNonBundleFolderIsNil() {
        // "Homebrew" has no reverse-DNS shape, so we can't attribute it.
        XCTAssertNil(id("/Users/x/Library/Caches/Homebrew/downloads/a.tar"))
    }

    func testUnrelatedPathIsNil() {
        XCTAssertNil(id("/var/log/system.log"))
    }

    func testBrowserPathLookup() {
        XCTAssertEqual(
            id("/Users/x/Library/Application Support/Google/Chrome/Default/Cache/data"),
            "com.google.Chrome"
        )
    }

    func testRunningOwnedURLsCollectsOnlyRunningOwners() {
        func item(_ name: String, _ path: String) -> FileItem {
            FileItem(url: URL(filePath: path), name: name, size: 1, allocatedSize: 1, isDirectory: false)
        }
        let running = item("a", "/Users/x/Library/Caches/com.acme.app/Cache.db")
        let idle = item("b", "/Users/x/Library/Caches/com.other.tool/Cache.db")
        let unknown = item("c", "/var/log/system.log")
        let result = ScanResult(category: .userCaches, items: [running, idle, unknown])

        let urls = AppCacheOwnership.runningOwnedURLs(in: [result], runningBundleIDs: ["com.acme.app"])
        XCTAssertEqual(urls, [running.url])
    }

    func testRunningOwnedURLsEmptyWhenNothingRunning() {
        let item = FileItem(
            url: URL(filePath: "/Users/x/Library/Caches/com.acme.app/Cache.db"),
            name: "a", size: 1, allocatedSize: 1, isDirectory: false
        )
        let result = ScanResult(category: .userCaches, items: [item])
        XCTAssertTrue(AppCacheOwnership.runningOwnedURLs(in: [result], runningBundleIDs: []).isEmpty)
    }
}

final class ScanCategorySubtitleTests: XCTestCase {
    func testEveryCategoryHasNonEmptySubtitle() {
        for category in ScanCategory.allCases {
            XCTAssertFalse(
                category.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(category) is missing a subtitle"
            )
        }
    }
}
