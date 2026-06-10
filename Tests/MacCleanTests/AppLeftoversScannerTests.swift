import XCTest
@testable import MacClean
import MacCleanKit

final class AppLeftoversScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "Leftovers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeEntry(_ name: String, bytes: Int) throws {
        let dir = root.appending(path: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(count: bytes).write(to: dir.appending(path: "data.bin"))
    }

    func testReturnsOnlyOrphanEntries() throws {
        try makeEntry("com.deleted.app", bytes: 4096)        // owner not installed
        try makeEntry("com.installed.app", bytes: 4096)      // owner installed
        try makeEntry("com.apple.Safari", bytes: 4096)       // system, never flagged
        try makeEntry("com.installed.app.helper", bytes: 4096) // helper of installed

        let items = AppLeftoversScanner.scan(
            roots: [root],
            installedBundleIDs: ["com.installed.app"]
        )

        XCTAssertEqual(items.map(\.name), ["com.deleted.app"],
                       "only the deleted app's leftover should be flagged")
        XCTAssertGreaterThan(items.first?.size ?? 0, 0)
    }

    func testEmptyInstalledSetFlagsNothing() throws {
        // An empty installed set means enumeration failed; never treat the
        // whole Mac as orphaned.
        try makeEntry("com.deleted.app", bytes: 4096)
        let items = AppLeftoversScanner.scan(roots: [root], installedBundleIDs: [])
        XCTAssertTrue(items.isEmpty)
    }
}
