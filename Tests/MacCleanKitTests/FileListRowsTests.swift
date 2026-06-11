import XCTest
@testable import MacCleanKit

final class FileListRowsTests: XCTestCase {
    private func item(_ name: String, size: UInt64 = 1) -> FileItem {
        FileItem(
            url: URL(filePath: "/tmp/\(name)"),
            name: name,
            size: size,
            allocatedSize: size,
            isDirectory: false
        )
    }

    func testExpandedCategoryEmitsHeaderThenItems() {
        let result = ScanResult(category: .userCaches, items: [item("a"), item("b")])
        let rows = FileListRows.flatten(
            results: [result], isExpanded: { _ in true }, selectedItems: []
        )

        guard case .header(let header) = rows[0] else { return XCTFail("first row must be the header") }
        XCTAssertEqual(header.category, .userCaches)
        XCTAssertEqual(header.fileCount, 2)
        XCTAssertTrue(header.isExpanded)
        guard case .item(let first, _) = rows[1] else { return XCTFail("expected item row") }
        XCTAssertEqual(first.name, "a")
        XCTAssertEqual(rows.count, 3)
    }

    func testCollapsedCategoryEmitsHeaderOnly() {
        let result = ScanResult(category: .userLogs, items: [item("a"), item("b")])
        let rows = FileListRows.flatten(
            results: [result], isExpanded: { _ in false }, selectedItems: []
        )

        XCTAssertEqual(rows.count, 1)
        guard case .header(let header) = rows[0] else { return XCTFail("expected header") }
        XCTAssertFalse(header.isExpanded)
    }

    func testHeaderAllSelectedReflectsSelection() {
        let a = item("a"); let b = item("b")
        let result = ScanResult(category: .userCaches, items: [a, b])

        let all = FileListRows.flatten(
            results: [result], isExpanded: { _ in true }, selectedItems: [a.url, b.url]
        )
        guard case .header(let fullHeader) = all[0] else { return XCTFail() }
        XCTAssertTrue(fullHeader.allSelected)

        let partial = FileListRows.flatten(
            results: [result], isExpanded: { _ in true }, selectedItems: [a.url]
        )
        guard case .header(let partialHeader) = partial[0] else { return XCTFail() }
        XCTAssertFalse(partialHeader.allSelected)
    }

    func testItemRowCarriesSelectionState() {
        let a = item("a"); let b = item("b")
        let result = ScanResult(category: .userCaches, items: [a, b])
        let rows = FileListRows.flatten(
            results: [result], isExpanded: { _ in true }, selectedItems: [b.url]
        )

        guard case .item(let rowA, let selectedA) = rows[1],
              case .item(let rowB, let selectedB) = rows[2]
        else { return XCTFail("expected two item rows") }
        XCTAssertEqual(rowA.name, "a"); XCTAssertFalse(selectedA)
        XCTAssertEqual(rowB.name, "b"); XCTAssertTrue(selectedB)
    }

    func testEmptyCategoryHeaderIsNotAllSelected() {
        let result = ScanResult(category: .userCaches, items: [])
        let rows = FileListRows.flatten(
            results: [result], isExpanded: { _ in true }, selectedItems: []
        )
        guard case .header(let header) = rows[0] else { return XCTFail() }
        XCTAssertFalse(header.allSelected, "empty category must not read as all-selected")
    }
}
