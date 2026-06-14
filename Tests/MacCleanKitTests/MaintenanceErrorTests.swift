import XCTest
@testable import MacCleanKit

final class MaintenanceErrorTests: XCTestCase {

    func testStripsOsascriptExecutionErrorWrapper() {
        // The exact shape users see (issue #82) before cleanup.
        let raw = "1:92: execution error: diskutil: did not recognize verb \"repairPermissions\"; type \"diskutil\" for a list (1)"
        XCTAssertEqual(
            MaintenanceShell.humanReadableError(raw),
            "diskutil: did not recognize verb \"repairPermissions\"; type \"diskutil\" for a list"
        )
    }

    func testStripsWrapperWithoutLineOffsets() {
        XCTAssertEqual(
            MaintenanceShell.humanReadableError("execution error: User canceled. (-128)"),
            "User canceled."
        )
    }

    func testLeavesPlainMessageUnchanged() {
        XCTAssertEqual(
            MaintenanceShell.humanReadableError("Operation not permitted"),
            "Operation not permitted"
        )
    }

    func testTrimsSurroundingWhitespaceAndTrailingCode() {
        XCTAssertEqual(
            MaintenanceShell.humanReadableError("  0:56: execution error: boom (5) "),
            "boom"
        )
    }
}
