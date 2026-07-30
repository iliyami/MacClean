import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit

/// Regression coverage for #120: the uninstaller must find apps nested in
/// subfolders of /Applications (e.g. /Applications/Adobe/Photoshop.app), not
/// just top-level ones, while never descending into .app bundles themselves.
final class AppDiscoveryTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "AppDiscoveryTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Create a minimal but real .app bundle (dir with Contents/Info.plist) so
    /// macOS treats it as a package.
    private func makeApp(_ relativePath: String) throws {
        let appURL = root.appending(path: relativePath)
        let contents = appURL.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let name = appURL.deletingPathExtension().lastPathComponent
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleIdentifier</key><string>com.test.\(name)</string>
          <key>CFBundleName</key><string>\(name)</string>
        </dict></plist>
        """
        try plist.write(to: contents.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
    }

    func testFindsAppsInSubfoldersNotJustTopLevel() throws {
        try makeApp("Root.app")                    // top level (already worked)
        try makeApp("Adobe/Photoshop.app")         // the #120 case: one level deep
        try makeApp("Adobe/CC/Lightroom.app")      // two levels deep
        // A helper app INSIDE a bundle must NOT be surfaced as a separate app.
        try makeApp("Root.app/Contents/Library/LoginItems/Helper.app")
        // Non-app clutter is ignored.
        try FileManager.default.createDirectory(
            at: root.appending(path: "Docs"), withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: root.appending(path: "Docs/readme.txt"))

        let found = AppDiscovery.appBundles(in: root).map(\.lastPathComponent).sorted()

        XCTAssertEqual(found, ["Lightroom.app", "Photoshop.app", "Root.app"])
        XCTAssertFalse(found.contains("Helper.app"),
                       "must not descend into .app bundles to list nested helpers")
    }

    func testMissingDirectoryReturnsEmpty() {
        let missing = root.appending(path: "does-not-exist")
        XCTAssertTrue(AppDiscovery.appBundles(in: missing).isEmpty)
    }
}
