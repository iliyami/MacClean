import XCTest
import AppKit
@testable import MacClean
import MacCleanKit

/// Guards the reason FileTableView exists: scan results can reach tens of
/// thousands of rows, and the table must stay responsive at that scale
/// (SwiftUI's List did not — it re-diffed every row on each update).
@MainActor
final class FileTableViewTests: XCTestCase {

    private func makeRows(_ n: Int) -> [FileListRow] {
        var rows: [FileListRow] = []
        rows.append(.header(FileListHeader(
            category: .userCaches, totalSize: 123, fileCount: n,
            selectedSize: 0, selectedCount: 0, isExpanded: true
        )))
        for i in 0..<n {
            rows.append(.item(
                FileItem(
                    url: URL(filePath: "/tmp/cache/file\(i).cache"),
                    name: "file\(i).cache",
                    size: UInt64(i),
                    allocatedSize: UInt64(i),
                    isDirectory: false
                ),
                isSelected: i.isMultiple(of: 2),
                appRunning: false
            ))
        }
        return rows
    }

    private func makeTable(coordinator: FileTableView.Coordinator) -> NSTableView {
        let table = NSTableView()
        let column = NSTableColumn(identifier: .init("main"))
        column.width = 600
        table.addTableColumn(column)
        table.headerView = nil
        table.usesAutomaticRowHeights = false
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.tableView = table
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scroll.documentView = table
        return table
    }

    func testHundredThousandRowsReloadIsFast() {
        let coordinator = FileTableView.Coordinator()
        coordinator.rows = makeRows(100_000)
        let table = makeTable(coordinator: coordinator)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            table.reloadData()
            table.layoutSubtreeIfNeeded()
        }

        XCTAssertEqual(table.numberOfRows, 100_001)
        // Sub-second at 100k rows; the old SwiftUI List took multiple seconds
        // (and re-paid that cost on every interaction). Generous bound so CI
        // machines don't flake.
        XCTAssertLessThan(elapsed, .seconds(2), "reload must not scale with row count")
    }

    func testCellsMaterializeForHeaderAndItemRows() {
        let coordinator = FileTableView.Coordinator()
        coordinator.rows = makeRows(50)
        let table = makeTable(coordinator: coordinator)
        table.reloadData()

        let headerCell = table.view(atColumn: 0, row: 0, makeIfNecessary: true)
        let itemCell = table.view(atColumn: 0, row: 1, makeIfNecessary: true)
        XCTAssertNotNil(headerCell, "header row must produce a cell")
        XCTAssertNotNil(itemCell, "item row must produce a cell")
        XCTAssertNotEqual(
            headerCell?.identifier, itemCell?.identifier,
            "header and item rows use distinct reusable cell types"
        )
    }

    func testRowHeightsAreFixedPerKind() {
        let coordinator = FileTableView.Coordinator()
        coordinator.rows = makeRows(2)
        let table = makeTable(coordinator: coordinator)

        let headerHeight = coordinator.tableView(table, heightOfRow: 0)
        let itemHeight = coordinator.tableView(table, heightOfRow: 1)
        XCTAssertGreaterThan(headerHeight, 0)
        XCTAssertGreaterThan(itemHeight, 0)
    }
}
