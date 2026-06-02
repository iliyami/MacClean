import XCTest
@testable import MacClean
@testable import MacCleanKit

@MainActor
final class SystemJunkRestoreTests: XCTestCase {
    func testRestoreWithResultsShowsResults() {
        let vm = SystemJunkViewModel()
        let r = [ScanResult(category: .userCaches, items: [])]
        vm.restore(results: r, selection: [URL(filePath: "/a")], scanComplete: true)
        XCTAssertEqual(vm.results.count, 1)
        XCTAssertEqual(vm.selectedItems, [URL(filePath: "/a")])
        XCTAssertTrue(vm.isScanComplete)
        if case .results = vm.state {} else { XCTFail("expected .results") }
    }

    func testRestoreEmptyScanShowsEmpty() {
        let vm = SystemJunkViewModel()
        vm.restore(results: [], selection: [], scanComplete: true)
        if case .empty = vm.state {} else { XCTFail("expected .empty") }
    }

    func testRestoreNotScannedStaysIdle() {
        let vm = SystemJunkViewModel()
        vm.restore(results: [], selection: [], scanComplete: false)
        if case .idle = vm.state {} else { XCTFail("expected .idle") }
        XCTAssertFalse(vm.isScanComplete)
    }
}
