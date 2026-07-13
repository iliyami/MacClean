import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit

/// The uninstall decision logic, extracted from the view so it's testable.
/// Guards against the security-review finding: the app bundle used to be
/// trashed with a raw `try? trashItem` that skipped SafetyGuard and never
/// re-checked protected apps.
final class AppUninstallerTests: XCTestCase {

    private func app(_ bundleID: String, path: String = "/Applications/Foo.app") -> AppInfo {
        AppInfo(bundleIdentifier: bundleID, name: "Foo",
                path: URL(filePath: path), version: "1.0", size: 1000)
    }

    func testProtectedAppIsRefused() {
        // Finder is in the protected set; uninstall must refuse it regardless
        // of what the UI does (defense in depth beyond hiding the button).
        XCTAssertNil(AppUninstaller.plan(app: app("com.apple.finder"),
                                         associatedFiles: [], selectedFiles: []),
                     "a protected system app must never be uninstallable")
    }

    func testNormalAppRoutesBundleThroughEngine() {
        let a = app("com.example.foo", path: "/Applications/Foo.app")
        let plan = AppUninstaller.plan(app: a, associatedFiles: [], selectedFiles: [])
        // The bundle itself must be in the item list so it goes through the
        // validated, logged CleaningEngine, not a raw try? trashItem.
        XCTAssertTrue(plan?.items.contains { $0.url == a.path } ?? false,
                      "the app bundle must be routed through the cleaning engine")
        XCTAssertTrue(plan?.selection.contains(a.path) ?? false,
                      "the bundle must be selected for removal")
    }

    func testSelectedLeftoversArePreservedAlongsideBundle() {
        let a = app("com.example.foo", path: "/Applications/Foo.app")
        let leftover = FileItem(
            url: URL(filePath: "/Users/x/Library/Caches/com.example.foo"),
            name: "com.example.foo", size: 10, allocatedSize: 10, isDirectory: true)
        let plan = AppUninstaller.plan(app: a, associatedFiles: [leftover],
                                       selectedFiles: [leftover.url])
        XCTAssertTrue(plan?.items.contains { $0.url == leftover.url } ?? false)
        XCTAssertTrue(plan?.selection.contains(leftover.url) ?? false)
        XCTAssertTrue(plan?.selection.contains(a.path) ?? false,
                      "the bundle is always included even if only leftovers were checked")
    }
}
