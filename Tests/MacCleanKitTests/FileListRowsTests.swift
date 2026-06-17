import XCTest
@testable import MacCleanKit

final class FileListRowsTests: XCTestCase {
    private func item(_ name: String, size: UInt64 = 1, path: String? = nil) -> FileItem {
        FileItem(
            url: URL(filePath: path ?? "/tmp/\(name)"),
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
        guard case .item(let first, _, _) = rows[1] else { return XCTFail("expected item row") }
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

    func testHeaderSelectionStates() {
        let a = item("a"); let b = item("b")
        let result = ScanResult(category: .userCaches, items: [a, b])

        let all = FileListRows.flatten(
            results: [result], isExpanded: { _ in true }, selectedItems: [a.url, b.url]
        )
        guard case .header(let fullHeader) = all[0] else { return XCTFail() }
        XCTAssertEqual(fullHeader.selection, .all)
        XCTAssertEqual(fullHeader.selectedCount, 2)

        let partial = FileListRows.flatten(
            results: [result], isExpanded: { _ in true }, selectedItems: [a.url]
        )
        guard case .header(let partialHeader) = partial[0] else { return XCTFail() }
        XCTAssertEqual(partialHeader.selection, .mixed)
        XCTAssertEqual(partialHeader.selectedCount, 1)

        let none = FileListRows.flatten(
            results: [result], isExpanded: { _ in true }, selectedItems: []
        )
        guard case .header(let noneHeader) = none[0] else { return XCTFail() }
        XCTAssertEqual(noneHeader.selection, .none)
        XCTAssertEqual(noneHeader.selectedCount, 0)
    }

    func testHeaderSelectedSizeSumsSelectedItemsOnly() {
        let a = item("a", size: 100); let b = item("b", size: 250)
        let result = ScanResult(category: .userCaches, items: [a, b])
        let rows = FileListRows.flatten(
            results: [result], isExpanded: { _ in true }, selectedItems: [b.url]
        )
        guard case .header(let header) = rows[0] else { return XCTFail() }
        XCTAssertEqual(header.totalSize, 350)
        XCTAssertEqual(header.selectedSize, 250)
    }

    func testItemRowCarriesSelectionState() {
        let a = item("a"); let b = item("b")
        let result = ScanResult(category: .userCaches, items: [a, b])
        let rows = FileListRows.flatten(
            results: [result], isExpanded: { _ in true }, selectedItems: [b.url]
        )

        guard case .item(let rowA, let selectedA, _) = rows[1],
              case .item(let rowB, let selectedB, _) = rows[2]
        else { return XCTFail("expected two item rows") }
        XCTAssertEqual(rowA.name, "a"); XCTAssertFalse(selectedA)
        XCTAssertEqual(rowB.name, "b"); XCTAssertTrue(selectedB)
    }

    func testEmptyCategoryHeaderSelectionIsNone() {
        let result = ScanResult(category: .userCaches, items: [])
        let rows = FileListRows.flatten(
            results: [result], isExpanded: { _ in true }, selectedItems: []
        )
        guard case .header(let header) = rows[0] else { return XCTFail() }
        XCTAssertEqual(header.selection, .none, "empty category must not read as all-selected")
    }

    func testItemsMarkedAppRunningWhenURLInAppRunningSet() {
        let running = item("c")
        let idle = item("d")
        let result = ScanResult(category: .userCaches, items: [running, idle])
        let rows = FileListRows.flatten(
            results: [result], isExpanded: { _ in true }, selectedItems: [],
            appRunningURLs: [running.url]
        )
        guard case .item(let r1, _, let running1) = rows[1],
              case .item(let r2, _, let running2) = rows[2]
        else { return XCTFail("expected two item rows") }
        XCTAssertEqual(r1.name, "c"); XCTAssertTrue(running1, "URL is in the app-running set")
        XCTAssertEqual(r2.name, "d"); XCTAssertFalse(running2, "URL is not in the app-running set")
    }
}
