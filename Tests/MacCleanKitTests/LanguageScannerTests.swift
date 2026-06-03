import XCTest
@testable import MacCleanKit
import MacCleanTestSupport

final class LanguageScannerTests: XCTestCase {

    private let fm = FileManager.default
    private let scanner = LanguageScanner()

    // MARK: - Helpers

    /// Creates a minimal `.app` bundle with the given lproj folders under Contents/Resources.
    private func makeApp(named name: String, lprojs: [String], in root: URL) throws {
        let resources = root
            .appending(path: "\(name).app")
            .appending(path: "Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        for lproj in lprojs {
            try fm.createDirectory(
                at: resources.appending(path: lproj),
                withIntermediateDirectories: true
            )
        }
    }

    // MARK: - Tests

    func testDiscoversDedupedLprojsFromMultipleApps() throws {
        try TestFixtures.withTempDir { root in
            // Foo.app has fr + de; Bar.app has fr + ja (fr is shared → deduped)
            try makeApp(named: "Foo", lprojs: ["fr.lproj", "de.lproj"], in: root)
            try makeApp(named: "Bar", lprojs: ["fr.lproj", "ja.lproj"], in: root)

            let result = scanner.discoverLproj(in: [root])
            XCTAssertEqual(result, ["fr.lproj", "de.lproj", "ja.lproj"])
        }
    }

    func testIgnoresNonAppEntries() throws {
        try TestFixtures.withTempDir { root in
            // A plain directory (not .app) containing lproj folders — must be ignored
            let notAnApp = root.appending(path: "NotAnApp")
            let resources = notAnApp.appending(path: "Contents/Resources")
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            try fm.createDirectory(at: resources.appending(path: "es.lproj"), withIntermediateDirectories: true)

            // A regular file at root level — must be ignored
            try Data("hello".utf8).write(to: root.appending(path: "readme.txt"))

            let result = scanner.discoverLproj(in: [root])
            XCTAssertTrue(result.isEmpty, "Expected no lprojs; got \(result)")
        }
    }

    func testIgnoresNonLprojEntriesInsideApp() throws {
        try TestFixtures.withTempDir { root in
            let resources = root
                .appending(path: "MyApp.app")
                .appending(path: "Contents/Resources")
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)

            // Valid lproj
            try fm.createDirectory(at: resources.appending(path: "ko.lproj"), withIntermediateDirectories: true)
            // Not an lproj — should be ignored
            try fm.createDirectory(at: resources.appending(path: "ko.bundle"), withIntermediateDirectories: true)
            try Data().write(to: resources.appending(path: "Info.plist"))

            let result = scanner.discoverLproj(in: [root])
            XCTAssertEqual(result, ["ko.lproj"])
        }
    }

    func testEmptyRootReturnsEmpty() throws {
        try TestFixtures.withTempDir { root in
            let result = scanner.discoverLproj(in: [root])
            XCTAssertTrue(result.isEmpty)
        }
    }

    func testNonExistentRootIsSkippedGracefully() {
        let bogus = URL(filePath: "/tmp/macclean-nonexistent-\(UUID().uuidString)")
        let result = scanner.discoverLproj(in: [bogus])
        XCTAssertTrue(result.isEmpty)
    }

    func testMultipleRootsAreMerged() throws {
        try TestFixtures.withTempDir { rootA in
            try TestFixtures.withTempDir { rootB in
                try makeApp(named: "Alpha", lprojs: ["fr.lproj"], in: rootA)
                try makeApp(named: "Beta",  lprojs: ["ru.lproj"], in: rootB)

                let result = self.scanner.discoverLproj(in: [rootA, rootB])
                XCTAssertEqual(result, ["fr.lproj", "ru.lproj"])
            }
        }
    }

    func testAppWithNoResourcesDirIsSkippedGracefully() throws {
        try TestFixtures.withTempDir { root in
            // .app exists but has no Contents/Resources
            try fm.createDirectory(
                at: root.appending(path: "Empty.app/Contents"),
                withIntermediateDirectories: true
            )
            let result = scanner.discoverLproj(in: [root])
            XCTAssertTrue(result.isEmpty)
        }
    }
}
