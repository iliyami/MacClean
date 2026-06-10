import XCTest
@testable import MacCleanKit

final class FileListSortTests: XCTestCase {
    private func item(_ name: String, size: UInt64, path: String? = nil) -> FileItem {
        FileItem(
            url: URL(filePath: path ?? "/tmp/\(name)"),
            name: name,
            size: size,
            allocatedSize: size,
            isDirectory: false
        )
    }

    func testSizeDescendingPutsLargestFirst() {
        let items = [item("a", size: 10), item("b", size: 300), item("c", size: 50)]
        XCTAssertEqual(FileListSort.sizeDescending.sorted(items).map(\.name), ["b", "c", "a"])
    }

    func testSizeAscendingPutsSmallestFirst() {
        let items = [item("a", size: 10), item("b", size: 300), item("c", size: 50)]
        XCTAssertEqual(FileListSort.sizeAscending.sorted(items).map(\.name), ["a", "c", "b"])
    }

    func testNameSortsAlphabeticallyCaseInsensitive() {
        let items = [item("Zebra", size: 1), item("apple", size: 1), item("Mango", size: 1)]
        XCTAssertEqual(FileListSort.name.sorted(items).map(\.name), ["apple", "Mango", "Zebra"])
    }

    func testEqualSizesBreakTieDeterministicallyByName() {
        // Same size: order must be stable and not depend on input order.
        let forward = [item("b", size: 100), item("a", size: 100), item("c", size: 100)]
        let reversed = Array(forward.reversed())
        XCTAssertEqual(FileListSort.sizeDescending.sorted(forward).map(\.name), ["a", "b", "c"])
        XCTAssertEqual(FileListSort.sizeDescending.sorted(reversed).map(\.name), ["a", "b", "c"])
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(FileListSort.sizeDescending.sorted([]).isEmpty)
    }

    func testDefaultIsLargestFirst() {
        XCTAssertEqual(FileListSort.default, .sizeDescending)
    }
}
