import XCTest
@testable import MacCleanKit

final class MaintenanceTaskPrivilegeTests: XCTestCase {
    func testRootTasksAreFlaggedPrivileged() {
        XCTAssertTrue(MaintenanceTask.freeUpRAM.requiresAdmin)
        XCTAssertTrue(MaintenanceTask.runMaintenanceScripts.requiresAdmin)
        XCTAssertFalse(MaintenanceTask.flushDNSCache.requiresAdmin)
        XCTAssertFalse(MaintenanceTask.freeUpPurgeableSpace.requiresAdmin)
    }
}
