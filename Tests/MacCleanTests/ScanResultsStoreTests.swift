import XCTest
@testable import MacClean
@testable import MacCleanKit

final class ScanResultsStoreTests: XCTestCase {
    private func sample() -> [ScanResult] { [ScanResult(category: .userCaches, items: [])] }

    func testSaveAndRetrievePerModule() {
        let store = ScanResultsStore()
        store.save(results: sample(), selection: [URL(filePath: "/a")], scanComplete: true, for: .systemJunk)
        let e = store.entry(for: .systemJunk)
        XCTAssertEqual(e?.results.count, 1)
        XCTAssertEqual(e?.selection, [URL(filePath: "/a")])
        XCTAssertEqual(e?.scanComplete, true)
    }

    func testIsolationBetweenModules() {
        let store = ScanResultsStore()
        store.save(results: sample(), selection: [], scanComplete: true, for: .systemJunk)
        XCTAssertNil(store.entry(for: .trashBins))
    }

    func testOverwrite() {
        let store = ScanResultsStore()
        store.save(results: sample(), selection: [URL(filePath: "/a")], scanComplete: true, for: .trashBins)
        store.save(results: [], selection: [], scanComplete: false, for: .trashBins)
        XCTAssertEqual(store.entry(for: .trashBins)?.results.count, 0)
        XCTAssertEqual(store.entry(for: .trashBins)?.scanComplete, false)
    }

    func testClearAndClearAll() {
        let store = ScanResultsStore()
        store.save(results: sample(), selection: [], scanComplete: true, for: .privacy)
        store.clear(.privacy)
        XCTAssertNil(store.entry(for: .privacy))
        store.save(results: sample(), selection: [], scanComplete: true, for: .malwareRemoval)
        store.clearAll()
        XCTAssertNil(store.entry(for: .malwareRemoval))
    }

    func testAbsentLookupIsNil() {
        XCTAssertNil(ScanResultsStore().entry(for: .duplicates))
    }
}
