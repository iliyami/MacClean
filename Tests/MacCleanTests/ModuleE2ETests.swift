import XCTest
@testable import MacClean
@testable import MacCleanKit
import MacCleanTestSupport

/// E2E coverage for modules previously tested only at unit level:
/// Uninstaller, Malware, Duplicates, SpaceLens. Each test plants
/// synthetic fixtures and exercises the module's real public scan
/// surface — no mocks of the underlying file traversal or hashing.
///
/// Privacy / Maintenance / Updater are intentionally NOT here:
///  - Privacy targets real browser data dirs (Safari, Chrome) — planting
///    fixtures means touching the user's actual browser data.
///  - Maintenance dispatches shell commands via the XPC helper; the
///    helper-side logic is covered by HelperThinningTests' pattern,
///    and the per-command dispatch is unit-tested in MaintenanceTaskTests.
///  - Updater parses Sparkle XML appcasts; that's covered in AppcastParserTests.
final class ModuleE2ETests: XCTestCase {

    private var stragglerFiles: [URL] = []
    private var stragglerDirs: [URL] = []

    override func tearDownWithError() throws {
        for url in stragglerFiles { try? FileManager.default.removeItem(at: url) }
        for url in stragglerDirs  { try? FileManager.default.removeItem(at: url) }
        stragglerFiles.removeAll()
        stragglerDirs.removeAll()
    }

    @discardableResult
    private func plant(at url: URL, bytes: Data) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: url)
        return url
    }

    private func canon(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    // MARK: - Uninstaller

    /// SPEC: planting a synthetic .app with a unique bundleID under
    /// ~/Applications, plus matching leftover files in Library subdirs,
    /// must let AppDiscovery find the app and AppPathFinder find every
    /// leftover via the 10-level matcher.
    func testUninstaller_findsAppAndAssociatedFiles() async throws {
        let id = UUID().uuidString
        let bundleID = "com.macclean.e2e.acmechat\(id.prefix(8).lowercased())"
        let appName = "AcmeChatE2E\(id.prefix(8))"

        // Synthetic .app under ~/Applications (user-writable).
        let userApps = MCConstants.home.appending(path: "Applications")
        try FileManager.default.createDirectory(
            at: userApps, withIntermediateDirectories: true
        )
        let appURL = userApps.appending(path: "\(appName).app")
        stragglerDirs.append(appURL)

        let infoPlist = appURL.appending(path: "Contents/Info.plist")
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": appName,
            "CFBundleName": appName,
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL",
        ]
        try plant(
            at: infoPlist,
            bytes: try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            )
        )

        // Matching leftover files in Library subdirs (the 10-level matcher
        // should pick these up via bundle-ID-prefix matching).
        let cacheFile = MCConstants.userCaches
            .appending(path: "\(bundleID)/cache.db")
        let prefFile = MCConstants.userPreferences
            .appending(path: "\(bundleID).plist")
        stragglerDirs.append(cacheFile.deletingLastPathComponent())
        stragglerFiles.append(prefFile)
        try plant(at: cacheFile, bytes: Data(count: 128))
        try plant(at: prefFile, bytes: Data(count: 128))

        // 1. AppDiscovery enumerates apps.
        let discovery = AppDiscovery()
        let allApps = await discovery.discoverApps()
        guard let app = allApps.first(where: { $0.bundleIdentifier == bundleID }) else {
            return XCTFail("AppDiscovery must find our planted .app under ~/Applications")
        }

        // 2. AppPathFinder finds the associated files.
        let finder = AppPathFinder(maxLevel: .companyName)
        let assoc = finder.findAssociatedFiles(for: app)
        let foundPaths = Set(assoc.map { canon($0.url) })

        XCTAssertTrue(foundPaths.contains(canon(cacheFile.deletingLastPathComponent())),
                      "leftover cache dir must be found via bundleID match")
        XCTAssertTrue(foundPaths.contains(canon(prefFile)),
                      "leftover .plist must be found via bundleID match")
    }

    // MARK: - Malware

    /// SPEC: a launch-agent plist with a name matching a known pattern
    /// (e.g. "genio") must be surfaced by MalwareModule.scan().
    func testMalware_flagsLaunchAgentWithMaliciousName() async throws {
        let id = UUID().uuidString
        // "genio" is in MalwareSignatures.knownPatterns.
        let agent = MCConstants.userLaunchAgents
            .appending(path: "com.macclean.e2e.genio-\(id).plist")
        stragglerFiles.append(agent)

        let plist: [String: Any] = [
            "Label": "com.macclean.e2e.genio-\(id)",
            "ProgramArguments": ["/usr/bin/true"],
            "RunAtLoad": true,
        ]
        try plant(
            at: agent,
            bytes: try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            )
        )

        let scan = await MalwareModule(depth: .quick).scan()
        let urls = scan.flatMap(\.items).map { canon($0.url) }
        XCTAssertTrue(urls.contains(canon(agent)),
                      "agent with name containing 'genio' must be flagged as malware")
    }

    // MARK: - Duplicates

    /// SPEC: three byte-identical files in the home tree must be grouped
    /// as duplicates by the size → partial-hash → full-hash pipeline.
    /// A near-duplicate of similar size but different content must NOT
    /// be flagged.
    func testDuplicates_groupsByteIdenticalFiles() async throws {
        let id = UUID().uuidString
        let dir = MCConstants.home.appending(path: "MacCleanE2E-dupes-\(id)")
        stragglerDirs.append(dir)

        let identicalPayload = Data(repeating: 0xAB, count: 8_192)
        let f1 = try plant(at: dir.appending(path: "a/copy1.bin"), bytes: identicalPayload)
        let f2 = try plant(at: dir.appending(path: "b/copy2.bin"), bytes: identicalPayload)
        let f3 = try plant(at: dir.appending(path: "c/copy3.bin"), bytes: identicalPayload)
        // Different content, same size — must NOT collide after hashing.
        let near = try plant(at: dir.appending(path: "d/near.bin"),
                             bytes: Data(repeating: 0xCD, count: 8_192))

        let scan = await DuplicatesModule().scan()
        let allItems = scan.flatMap(\.items).map { canon($0.url) }

        let dupeURLs = Set(allItems).intersection(Set([f1, f2, f3].map(canon)))
        XCTAssertEqual(dupeURLs.count, 2,
                       "extractDeletableDuplicates surfaces N-1 = 2 (keeps one original)")
        XCTAssertFalse(allItems.contains(canon(near)),
                       "different-content file must NOT be flagged as a duplicate")
    }

    // MARK: - SpaceLens

    /// SPEC: SpaceLens.scan(root:) builds a tree where every node's
    /// `totalSize` equals the sum of its descendant file sizes.
    /// Treemap rectangles' areas should be proportional to those totals.
    /// We don't test rendering — pure layout is covered in
    /// SquarifiedTreemapTests — but we do verify the tree's bookkeeping
    /// against a known synthetic fixture.
    func testSpaceLens_treeSizeMatchesFileSystemReality() async throws {
        let id = UUID().uuidString
        let root = MCConstants.home.appending(path: "MacCleanE2E-spacelens-\(id)")
        stragglerDirs.append(root)

        try plant(at: root.appending(path: "small.bin"), bytes: Data(count: 1024))
        try plant(at: root.appending(path: "big.bin"),   bytes: Data(count: 10_240))
        try plant(at: root.appending(path: "nested/even-bigger.bin"),
                  bytes: Data(count: 50_000))

        // SpaceLens is driven by FileTreeScanner.scanWithSizeAggregation —
        // SpaceLensModule itself only provides metadata (the View calls the
        // scanner directly). Exercise the actual aggregator here.
        let scanner = FileTreeScanner()
        let node = await scanner.scanWithSizeAggregation(root: root)

        // 1024 + 10240 + 50000 = 61264 bytes total. The aggregator uses
        // allocated sizes from APFS which round up to block boundaries, so
        // accept a small overhead.
        XCTAssertGreaterThanOrEqual(node.totalSize, 61_264,
                                    "root totalSize must include every descendant file")
        XCTAssertLessThan(node.totalSize, 200_000,
                          "totalSize sanity bound — no runaway from unrelated paths")
    }
}
