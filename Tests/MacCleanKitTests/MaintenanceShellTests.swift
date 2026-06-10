import XCTest
@testable import MacCleanKit

final class MaintenanceShellTests: XCTestCase {
    func testPlainWordIsQuoted() {
        XCTAssertEqual(MaintenanceShell.quote("daily"), "'daily'")
    }

    func testSpacesArePreservedInsideQuotes() {
        XCTAssertEqual(MaintenanceShell.quote("/Volumes/My Disk"), "'/Volumes/My Disk'")
    }

    func testSingleQuoteIsEscaped() {
        // POSIX idiom: close quote, escaped quote, reopen quote.
        XCTAssertEqual(MaintenanceShell.quote("a'b"), "'a'\\''b'")
    }

    func testMetacharactersAreNeutralised() {
        XCTAssertEqual(MaintenanceShell.quote("x; rm -rf /"), "'x; rm -rf /'")
        XCTAssertEqual(MaintenanceShell.quote("$(whoami)"), "'$(whoami)'")
        XCTAssertEqual(MaintenanceShell.quote("`id`"), "'`id`'")
    }

    func testCommandLineJoinsQuotedArgs() {
        let line = MaintenanceShell.commandLine("/usr/sbin/periodic", ["daily", "weekly"])
        XCTAssertEqual(line, "'/usr/sbin/periodic' 'daily' 'weekly'")
    }
}
