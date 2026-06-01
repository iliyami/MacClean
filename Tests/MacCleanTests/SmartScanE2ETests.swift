import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit
import MacCleanTestSupport

/// End-to-end tests for the Smart Scan flow. We use fake modules for
/// most assertions so the suite doesn't scan the user's actual home dir
/// (which can take minutes and produces flaky timing).
@MainActor
final class SmartScanE2ETests: XCTestCase {

    func testCoordinatorAggregatesAllRegisteredModules() async throws {
        // Real files so the CleanFilter (which drops un-cleanable
        // paths) keeps them in the aggregated results. The previous
        // version used `/tmp/a.cache` / `/tmp/b.log` literally — those
        // didn't exist, so the filter correctly dropped them and the
        // aggregation assertions failed for the wrong reason.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "SmartScanE2E-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let aURL = dir.appending(path: "a.cache")
        let bURL = dir.appending(path: "b.log")
        FileManager.default.createFile(atPath: aURL.path, contents: Data(count: 100))
        FileManager.default.createFile(atPath: bURL.path, contents: Data(count: 200))

        let coord = ScanCoordinator()
        coord.registerModules([
            ScanCoordinatorTests.FakeModule(
                id: "a", name: "A",
                result: [ScanResult(
                    category: .userCaches,
                    items: [FileItem(url: aURL,
                                     name: "a.cache", size: 100, allocatedSize: 100,
                                     isDirectory: false)]
                )]
            ),
            ScanCoordinatorTests.FakeModule(
                id: "b", name: "B",
                result: [ScanResult(
                    category: .userLogs,
                    items: [FileItem(url: bURL,
                                     name: "b.log", size: 200, allocatedSize: 200,
                                     isDirectory: false)]
                )]
            ),
        ])
        coord.scanAll()

        for _ in 0..<100 {
            if case .completed = coord.state { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard case .completed(let results) = coord.state else {
            return XCTFail("Expected completed, got \(coord.state)")
        }
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(coord.filesScanned, 2)
        XCTAssertEqual(coord.totalSizeFound, 300)
    }

    func testCoordinatorStateTransitions() async {
        // idle → completed for an empty module set
        let coord = ScanCoordinator()
        guard case .idle = coord.state else {
            return XCTFail("Initial state should be idle")
        }

        coord.registerModule(ScanCoordinatorTests.FakeModule(id: "x", name: "X", result: []))
        coord.scanAll()
        for _ in 0..<50 {
            if case .completed = coord.state { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard case .completed = coord.state else {
            return XCTFail("Should be completed by now")
        }
    }
}
