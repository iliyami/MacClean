import XCTest
@testable import MacCleanKit

final class PathExclusionTests: XCTestCase {

    private let home = "/Users/tester"

    // MARK: - Containment

    func testExactRootIsExcluded() {
        XCTAssertTrue(
            PathExclusion.isExcluded(
                path: "/Users/tester/Caches",
                by: ["/Users/tester/Caches"]
            )
        )
    }

    func testDescendantIsExcluded() {
        XCTAssertTrue(
            PathExclusion.isExcluded(
                path: "/Users/tester/Caches/com.example.app/offline.db",
                by: ["/Users/tester/Caches"]
            )
        )
    }

    func testSiblingPrefixIsNotExcluded() {
        XCTAssertFalse(
            PathExclusion.isExcluded(
                path: "/Users/tester/CachesEvil/x",
                by: ["/Users/tester/Caches"]
            )
        )
    }

    func testUnrelatedPathIsNotExcluded() {
        XCTAssertFalse(
            PathExclusion.isExcluded(
                path: "/Users/tester/Documents/a.txt",
                by: ["/Users/tester/Caches"]
            )
        )
    }

    func testEmptyExclusionListNeverMatches() {
        XCTAssertFalse(
            PathExclusion.isExcluded(path: "/Users/tester/Caches", by: [])
        )
    }

    func testFirmlinkFormsMatchEachOther() {
        // /var and /private/var are the same on-disk location.
        XCTAssertTrue(
            PathExclusion.isExcluded(
                path: "/private/var/folders/xx/tmp",
                by: ["/var/folders/xx"]
            )
        )
        XCTAssertTrue(
            PathExclusion.isExcluded(
                path: "/var/folders/xx/tmp",
                by: ["/private/var/folders/xx"]
            )
        )
    }

    // MARK: - Candidate policy

    func testHomeSubtreeIsAllowed() {
        XCTAssertEqual(
            PathExclusion.candidateDecision(
                for: "/Users/tester/Library/Caches/com.example",
                home: home
            ),
            .allow
        )
    }

    func testVolumesSubtreeIsAllowed() {
        XCTAssertEqual(
            PathExclusion.candidateDecision(
                for: "/Volumes/Backup/AppCache",
                home: home
            ),
            .allow
        )
    }

    func testHomeItselfIsRejected() {
        XCTAssertEqual(
            PathExclusion.candidateDecision(for: home, home: home),
            .reject(.entireHome)
        )
    }

    func testVolumesRootIsRejected() {
        XCTAssertEqual(
            PathExclusion.candidateDecision(for: "/Volumes", home: home),
            .reject(.entireVolumesRoot)
        )
    }

    func testSystemPathIsRejected() {
        XCTAssertEqual(
            PathExclusion.candidateDecision(for: "/System/Library", home: home),
            .reject(.outsideAllowedRoots)
        )
        XCTAssertEqual(
            PathExclusion.candidateDecision(for: "/usr/local", home: home),
            .reject(.outsideAllowedRoots)
        )
    }

    func testRelativePathIsRejected() {
        XCTAssertEqual(
            PathExclusion.candidateDecision(for: "Caches/foo", home: home),
            .reject(.notAbsolute)
        )
    }

    func testEmptyPathIsRejected() {
        XCTAssertEqual(
            PathExclusion.candidateDecision(for: "", home: home),
            .reject(.notAbsolute)
        )
    }

    // MARK: - Normalize / prune

    func testNormalizeDropsDescendantsWhenAncestorPresent() {
        let normalized = PathExclusion.normalized(
            [
                "/Users/tester/Caches",
                "/Users/tester/Caches/com.example",
                "/Users/tester/Documents",
            ]
        )
        XCTAssertEqual(
            normalized,
            ["/Users/tester/Caches", "/Users/tester/Documents"]
        )
    }

    func testNormalizeDedupesAndSorts() {
        let normalized = PathExclusion.normalized(
            [
                "/Users/tester/Documents",
                "/Users/tester/Caches",
                "/Users/tester/Documents",
            ]
        )
        XCTAssertEqual(
            normalized,
            ["/Users/tester/Caches", "/Users/tester/Documents"]
        )
    }

    // MARK: - Preferences (injected defaults)

    func testPreferencesRoundTripThroughInjectedDefaults() {
        let suite = "folder-exclusion-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("could not open isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(FolderExclusionPreferences.paths(in: defaults).isEmpty)

        XCTAssertTrue(
            FolderExclusionPreferences.add(
                "/Users/tester/Library/Caches/com.example",
                defaults: defaults,
                homePath: home
            )
        )
        XCTAssertEqual(
            FolderExclusionPreferences.paths(in: defaults),
            ["/Users/tester/Library/Caches/com.example"]
        )

        XCTAssertFalse(
            FolderExclusionPreferences.add("/System/Library", defaults: defaults, homePath: home),
            "system paths must be refused"
        )
        XCTAssertFalse(
            FolderExclusionPreferences.add(home, defaults: defaults, homePath: home),
            "entire home must be refused"
        )

        FolderExclusionPreferences.remove(
            "/Users/tester/Library/Caches/com.example",
            defaults: defaults
        )
        XCTAssertTrue(FolderExclusionPreferences.paths(in: defaults).isEmpty)
    }

    func testPreferencesRespectsMaxCount() {
        let suite = "folder-exclusion-cap-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("could not open isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(
            FolderExclusionPreferences.add("/Users/tester/a", defaults: defaults, homePath: home, maxCount: 2)
        )
        XCTAssertTrue(
            FolderExclusionPreferences.add("/Users/tester/b", defaults: defaults, homePath: home, maxCount: 2)
        )
        XCTAssertFalse(
            FolderExclusionPreferences.add("/Users/tester/c", defaults: defaults, homePath: home, maxCount: 2)
        )
        XCTAssertEqual(FolderExclusionPreferences.paths(in: defaults).count, 2)
    }

    func testSharedKeyStaysStable() {
        XCTAssertEqual(FolderExclusionPreferences.defaultsKey, "excludedFolders")
    }
}
