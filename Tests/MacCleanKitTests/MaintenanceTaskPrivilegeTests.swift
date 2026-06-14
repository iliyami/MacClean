import XCTest
@testable import MacCleanKit

final class MaintenanceTaskPrivilegeTests: XCTestCase {
    func testRootTasksAreFlaggedPrivileged() {
        XCTAssertTrue(MaintenanceTask.freeUpRAM.requiresAdmin)
        XCTAssertTrue(MaintenanceTask.runMaintenanceScripts.requiresAdmin)
        XCTAssertFalse(MaintenanceTask.flushDNSCache.requiresAdmin)
    }

    // Issue #82 privilege corrections:
    func testReindexSpotlightRequiresAdmin() {
        // `mdutil -E /` needs root; without it the task fails — the likely
        // second error in the report.
        XCTAssertTrue(MaintenanceTask.reindexSpotlight.requiresAdmin)
    }

    func testFreeUpPurgeableSpaceRequiresAdmin() {
        // `tmutil thinlocalsnapshots` needs root to actually reclaim space.
        XCTAssertTrue(MaintenanceTask.freeUpPurgeableSpace.requiresAdmin)
    }

    func testVerifyStartupDiskDoesNotRequireAdmin() {
        // `diskutil verifyVolume /` runs read-only without root — no need to
        // burden the user with a password prompt.
        XCTAssertFalse(MaintenanceTask.verifyStartupDisk.requiresAdmin)
    }
}
