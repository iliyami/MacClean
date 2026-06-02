import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit
import MacCleanTestSupport

final class FileTreeScannerAggregationTests: XCTestCase {
    func testAsyncAggregationSumsChildSizes() async throws {
        try await TestFixtures.withTempDir { dir in
            let a = dir.appending(path: "a")
            try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
            try Data(count: 1000).write(to: a.appending(path: "f1.bin"))
            try Data(count: 2000).write(to: dir.appending(path: "f2.bin"))

            let scanner = FileTreeScanner()
            let root = await scanner.scanWithSizeAggregation(root: dir)
            XCTAssertGreaterThanOrEqual(root.totalSize, 3000)
            XCTAssertLessThan(root.totalSize, 1_000_000, "no runaway aggregation")
        }
    }
}
