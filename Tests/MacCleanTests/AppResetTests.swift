import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit

final class AppResetTests: XCTestCase {

    private func app(_ bundleID: String = "com.example.foo",
                     path: String = "/Applications/Foo.app") -> AppInfo {
        AppInfo(bundleIdentifier: bundleID, name: "Foo",
                path: URL(filePath: path), version: "1.0", size: 1000)
    }

    private func file(_ path: String, size: UInt64 = 10) -> FileItem {
        FileItem(url: URL(filePath: path), name: URL(filePath: path).lastPathComponent,
                 size: size, allocatedSize: size, isDirectory: true)
    }

    func testPlanOmitsAppBundleEvenIfSelected() {
        let a = app()
        let cache = file(MCConstants.userCaches.appending(path: "com.example.foo").path(percentEncoded: false))
        let plan = AppReset.plan(
            app: a,
            associatedFiles: [cache],
            selectedFiles: [cache.url, a.path]
        )
        XCTAssertFalse(plan?.selection.contains(a.path) ?? true,
                       "reset must never trash the app bundle")
        XCTAssertEqual(plan?.items.map(\.url), [cache.url])
    }

    func testPlanNilWhenOnlyUserDataSelected() {
        let a = app()
        let support = file(MCConstants.userAppSupport.appending(path: "Foo").path(percentEncoded: false))
        XCTAssertNil(AppReset.plan(app: a, associatedFiles: [support], selectedFiles: [support.url]),
                     "Application Support is not part of reset-to-defaults")
    }

    func testPlanNilWhenSelectionEmpty() {
        let a = app()
        let cache = file(MCConstants.userCaches.appending(path: "com.example.foo").path(percentEncoded: false))
        XCTAssertNil(AppReset.plan(app: a, associatedFiles: [cache], selectedFiles: []))
    }

    func testProtectedAppleAppCanStillBeReset() {
        // Uninstall refuses Finder; reset of its caches/prefs is allowed.
        let a = app("com.apple.finder", path: "/System/Applications/Finder.app")
        let cache = file(MCConstants.userCaches.appending(path: "com.apple.finder").path(percentEncoded: false))
        let plan = AppReset.plan(app: a, associatedFiles: [cache], selectedFiles: [cache.url])
        XCTAssertEqual(plan?.items.map(\.url), [cache.url])
        XCTAssertNil(AppUninstaller.plan(app: a, associatedFiles: [cache], selectedFiles: [cache.url]),
                     "uninstall must still refuse the protected app")
    }

    func testPlanIntersectsSelectionWithPolicy() {
        let a = app()
        let cache = file(MCConstants.userCaches.appending(path: "com.example.foo").path(percentEncoded: false))
        let prefs = file(MCConstants.userPreferences.appending(path: "com.example.foo.plist").path(percentEncoded: false), size: 2)
        let agents = file(MCConstants.userLaunchAgents.appending(path: "com.example.foo.plist").path(percentEncoded: false))
        let plan = AppReset.plan(
            app: a,
            associatedFiles: [cache, prefs, agents],
            selectedFiles: [cache.url, agents.url]
        )
        XCTAssertEqual(Set(plan?.items.map(\.url) ?? []), [cache.url],
                       "unchecked prefs stay; launch agents never reset")
    }

    /// Source guard: the Uninstaller Reset control must call AppReset, not
    /// the old `resetSelection()` that only cleared the UI.
    func testUninstallerViewWiresRealReset() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/MacClean/Views/Applications/UninstallerView.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(src.contains("AppReset.plan"),
                      "UninstallerView must build a reset plan via AppReset.plan")
        XCTAssertTrue(src.contains("executeUserClean"),
                      "reset must go through CleanActions.executeUserClean")
        XCTAssertFalse(
            src.contains("Button(L10n.tr(\"重置\", \"Reset\", \"Сбросить\")) { resetSelection() }"),
            "the Reset button must no longer only clear UI selection"
        )
    }
}
