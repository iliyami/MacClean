import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit

final class SmartScanCleanupTests: XCTestCase {
    private func item(_ path: String, _ size: UInt64) -> FileItem {
        FileItem(url: URL(filePath: path), name: (path as NSString).lastPathComponent,
                 size: size, allocatedSize: size, isDirectory: false)
    }

    func testFlattensModuleResultsAcrossCategories() {
        let modules = [
            ModuleScanResult(moduleID: "systemJunk", moduleName: "System Junk",
                categories: [ScanResult(category: .userCaches, items: [item("/c/a", 100)])],
                scanDuration: 0),
            ModuleScanResult(moduleID: "trashBins", moduleName: "Trash Bins",
                categories: [ScanResult(category: .trashBins, items: [item("/t/b", 200)])],
                scanDuration: 0),
        ]
        let flat = SmartScanCleanup.allResults(from: modules)
        XCTAssertEqual(flat.count, 2)
        XCTAssertEqual(Set(flat.map(\.category)), [.userCaches, .trashBins])
    }

    func testFiltersEmptyCategories() {
        let modules = [
            ModuleScanResult(moduleID: "m", moduleName: "M",
                categories: [ScanResult(category: .userCaches, items: []),
                             ScanResult(category: .userLogs, items: [item("/l/x", 50)])],
                scanDuration: 0),
        ]
        let flat = SmartScanCleanup.allResults(from: modules)
        XCTAssertEqual(flat.map(\.category), [.userLogs])
    }

    func testDefaultSelectionIsEveryItemFromAutoSelectCategories() {
        let modules = [
            ModuleScanResult(moduleID: "systemJunk", moduleName: "System Junk",
                categories: [ScanResult(category: .userCaches,
                    items: [item("/c/a", 100), item("/c/b", 100)], autoSelect: true)],
                scanDuration: 0),
        ]
        let urls = SmartScanCleanup.defaultSelection(from: modules)
        XCTAssertEqual(urls, Set([URL(filePath: "/c/a"), URL(filePath: "/c/b")]))
    }
}
