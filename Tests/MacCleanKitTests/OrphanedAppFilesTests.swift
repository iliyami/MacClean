import XCTest
@testable import MacCleanKit

/// The orphan decision is the safety-critical core of the "leftovers from
/// deleted apps" scan. These cases encode the false-positive traps real
/// uninstallers hit (Pearcleaner #203): helper/agent ids of installed apps,
/// shared frameworks (Chromium/CEF, Qt, Electron), system ids, and over-broad
/// company-prefix matching.
final class OrphanedAppFilesTests: XCTestCase {

    func testInstalledAppIsNotOrphan() {
        XCTAssertFalse(OrphanedAppFiles.isOrphan(
            bundleID: "com.example.app", installedBundleIDs: ["com.example.app"]))
    }

    func testDeletedAppIsOrphan() {
        XCTAssertTrue(OrphanedAppFiles.isOrphan(
            bundleID: "com.example.deadapp", installedBundleIDs: ["com.other.app"]))
    }

    func testHelperOfInstalledAppIsNotOrphan() {
        // com.parallels.desktop.helper belongs to installed com.parallels.desktop.
        XCTAssertFalse(OrphanedAppFiles.isOrphan(
            bundleID: "com.parallels.desktop.helper",
            installedBundleIDs: ["com.parallels.desktop"]))
    }

    func testParentPrefixOfInstalledAppIsNotOrphan() {
        // An entry that is a parent of an installed app's id is in use.
        XCTAssertFalse(OrphanedAppFiles.isOrphan(
            bundleID: "com.parallels.desktop",
            installedBundleIDs: ["com.parallels.desktop.business"]))
    }

    func testAppleBundleIDIsNeverOrphan() {
        XCTAssertFalse(OrphanedAppFiles.isOrphan(
            bundleID: "com.apple.Safari", installedBundleIDs: []))
    }

    func testSharedFrameworksAreNeverOrphan() {
        for id in ["org.chromium.Chromium", "com.google.Keystone",
                   "org.qt-project.Qt", "com.github.Electron"] {
            XCTAssertFalse(OrphanedAppFiles.isOrphan(bundleID: id, installedBundleIDs: []),
                           "\(id) is a shared framework and must never be flagged")
        }
    }

    func testNonBundleIDNameIsNotFlagged() {
        // We only auto-flag clean reverse-DNS bundle ids, never arbitrary names.
        for name in ["Google", "SomeApp", "cache.db", "a"] {
            XCTAssertFalse(OrphanedAppFiles.isOrphan(bundleID: name, installedBundleIDs: []),
                           "\(name) is not a bundle id and must not be flagged")
        }
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertFalse(OrphanedAppFiles.isOrphan(
            bundleID: "COM.Example.App", installedBundleIDs: ["com.example.app"]))
    }

    func testSiblingAppUnderSameCompanyIsStillOrphan() {
        // Deleting Illustrator leftovers while Photoshop is installed is correct:
        // we must NOT treat a shared company prefix as "in use".
        XCTAssertTrue(OrphanedAppFiles.isOrphan(
            bundleID: "com.adobe.illustrator",
            installedBundleIDs: ["com.adobe.photoshop"]))
    }
}
