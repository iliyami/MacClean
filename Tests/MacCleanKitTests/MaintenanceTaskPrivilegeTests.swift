import XCTest
@testable import MacCleanKit

final class MaintenanceTaskPrivilegeTests: XCTestCase {
    func testRootTasksAreFlaggedPrivileged() {
        XCTAssertTrue(MaintenanceTask.freeUpRAM.requiresPrivilegedHelper)
        XCTAssertTrue(MaintenanceTask.runMaintenanceScripts.requiresPrivilegedHelper)
        XCTAssertFalse(MaintenanceTask.flushDNSCache.requiresPrivilegedHelper)
        XCTAssertFalse(MaintenanceTask.freeUpPurgeableSpace.requiresPrivilegedHelper)
    }
}
