import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit

final class DuplicatesConsolidationTests: XCTestCase {
    private func item(_ path: String, _ size: UInt64 = 100) -> FileItem {
        FileItem(url: URL(filePath: path), name: URL(filePath: path).lastPathComponent,
                 size: size, allocatedSize: size, isDirectory: false, modificationDate: nil)
    }

    func testMapsSelectedCopiesUnderTheirOriginalAsMaster() {
        let g = DuplicateDisplayGroup(
            original: item("/A/report.psd"),
            duplicates: [item("/B/report.psd"), item("/C/report.psd")])
        let selection: Set<URL> = [URL(filePath: "/B/report.psd")]  // only one copy chosen

        let groups = DuplicatesConsolidation.groups(from: [g], selection: selection)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].master, URL(filePath: "/A/report.psd"))
        XCTAssertEqual(groups[0].copies, [URL(filePath: "/B/report.psd")])
    }

    func testGroupsWithNoSelectedCopiesAreExcluded() {
        let g = DuplicateDisplayGroup(
            original: item("/A/a"), duplicates: [item("/B/a")])
        XCTAssertTrue(DuplicatesConsolidation.groups(from: [g], selection: []).isEmpty)
    }

    func testOriginalIsNeverTreatedAsACopyEvenIfSelected() {
        let g = DuplicateDisplayGroup(
            original: item("/A/a"), duplicates: [item("/B/a")])
        // Selecting the original must not add it as a copy to clone over.
        let groups = DuplicatesConsolidation.groups(
            from: [g], selection: [URL(filePath: "/A/a"), URL(filePath: "/B/a")])
        XCTAssertEqual(groups[0].copies, [URL(filePath: "/B/a")])
    }
}
