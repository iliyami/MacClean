import XCTest
import Foundation
@testable import MacClean
import MacCleanKit

/// Tests for the `ScanCoordinator` state machine. Uses synthetic in-memory
/// modules that return predetermined results.
@MainActor
final class ScanCoordinatorTests: XCTestCase {

    // Per-test sandbox. The classic setUpWithError/tearDownWithError
    // approach trips Swift 6 strict concurrency on the CI macos-15
    // runner — XCTestCase declares those as nonisolated, but reaching
    // an @MainActor stored property from them violates isolation. We
    // create+destroy the tmp dir inline per test instead.
    private static func makeTmpRoot(for name: String = #function) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ScanCoordinatorTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - Fake modules

    struct FakeModule: ScanModule {
        let id: String
        let name: String
        let category: ModuleCategory
        let includedInSmartScan: Bool
        let result: [ScanResult]
        let delay: TimeInterval

        init(
            id: String, name: String, category: ModuleCategory = .cleanup,
            includedInSmartScan: Bool = true,
            result: [ScanResult] = [], delay: TimeInterval = 0
        ) {
            self.id = id; self.name = name; self.category = category
            self.includedInSmartScan = includedInSmartScan
            self.result = result; self.delay = delay
        }

        func scan() async -> [ScanResult] {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            return result
        }
    }

    /// Materializes real files of the requested size in `inRoot` so the
    /// CleanFilter (which drops non-existent / non-writable paths) keeps
    /// them in the aggregated results.
    private func makeItems(count: Int, eachSize: UInt64, inRoot: URL) -> [FileItem] {
        (0..<count).map { idx in
            let url = inRoot.appending(path: "f\(idx)")
            FileManager.default.createFile(
                atPath: url.path,
                contents: Data(count: Int(eachSize))
            )
            return FileItem(
                url: url,
                name: "f\(idx)", size: eachSize, allocatedSize: eachSize, isDirectory: false
            )
        }
    }

    // MARK: - State machine

    func testInitialStateIsIdle() {
        let c = ScanCoordinator()
        guard case .idle = c.state else {
            return XCTFail("Initial state should be idle, was \(c.state)")
        }
    }

    func testScanAllCompletesAndAggregates() async throws {
        let tmpRoot = try Self.makeTmpRoot()
        defer { try? FileManager.default.removeItem(at: tmpRoot) }
        let c = ScanCoordinator()
        c.registerModules([
            FakeModule(
                id: "a", name: "A",
                result: [ScanResult(category: .userCaches,
                                    items: makeItems(count: 5, eachSize: 100, inRoot: tmpRoot))]
            ),
            FakeModule(
                id: "b", name: "B",
                result: [ScanResult(category: .userLogs,
                                    items: makeItems(count: 3, eachSize: 200, inRoot: tmpRoot))]
            ),
        ])
        c.scanAll()

        // Wait for completion (poll the state — it's @MainActor)
        for _ in 0..<100 {
            if case .completed = c.state { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard case .completed(let results) = c.state else {
            return XCTFail("Expected completed, got \(c.state)")
        }
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(c.filesScanned, 8)
        XCTAssertEqual(c.totalSizeFound, 5*100 + 3*200)
    }

    func testScanAllExcludesHeavyModules() async throws {
        let tmpRoot = try Self.makeTmpRoot()
        defer { try? FileManager.default.removeItem(at: tmpRoot) }
        let c = ScanCoordinator()
        c.registerModules([
            FakeModule(
                id: "light", name: "Light",
                result: [ScanResult(category: .userCaches, items: makeItems(count: 1, eachSize: 1, inRoot: tmpRoot))]
            ),
            FakeModule(
                id: "heavy", name: "Heavy",
                includedInSmartScan: false,
                result: [ScanResult(category: .duplicates, items: makeItems(count: 100, eachSize: 1, inRoot: tmpRoot))]
            ),
        ])
        c.scanAll()

        for _ in 0..<100 {
            if case .completed = c.state { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard case .completed(let results) = c.state else {
            return XCTFail("Expected completed")
        }
        XCTAssertEqual(results.count, 1, "Heavy module should be skipped in scanAll()")
        XCTAssertEqual(results.first?.moduleID, "light")
    }

    func testScanAllIncludingHeavyRunsAll() async {
        let c = ScanCoordinator()
        c.registerModules([
            FakeModule(id: "light", name: "Light", result: []),
            FakeModule(id: "heavy", name: "Heavy", includedInSmartScan: false, result: []),
        ])
        c.scanAllIncludingHeavy()
        for _ in 0..<100 {
            if case .completed = c.state { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard case .completed(let results) = c.state else {
            return XCTFail("Expected completed")
        }
        XCTAssertEqual(results.count, 2)
    }

    func testScanCategoryRunsOnlyMatching() async {
        let c = ScanCoordinator()
        c.registerModules([
            FakeModule(id: "cleanup1", name: "C1", category: .cleanup, result: []),
            FakeModule(id: "protection1", name: "P1", category: .protection, result: []),
        ])
        c.scanCategory(.protection)
        for _ in 0..<100 {
            if case .completed = c.state { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard case .completed(let results) = c.state else {
            return XCTFail("Expected completed")
        }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.moduleID, "protection1")
    }

    func testScanSingleRunsOnlyNamedModule() async {
        let c = ScanCoordinator()
        c.registerModules([
            FakeModule(id: "a", name: "A", result: []),
            FakeModule(id: "b", name: "B", result: []),
            FakeModule(id: "c", name: "C", result: []),
        ])
        c.scanSingle("b")
        for _ in 0..<100 {
            if case .completed = c.state { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard case .completed(let results) = c.state else {
            return XCTFail("Expected completed")
        }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.moduleID, "b")
    }

    func testCancelReturnsToIdle() async {
        let c = ScanCoordinator()
        c.registerModule(FakeModule(id: "slow", name: "Slow", result: [], delay: 5))
        c.scanAll()
        // Briefly wait so the scan transitions to .scanning
        try? await Task.sleep(for: .milliseconds(50))
        c.cancel()
        // After cancel, state should be idle (regardless of in-flight task)
        guard case .idle = c.state else {
            return XCTFail("Expected idle after cancel, got \(c.state)")
        }
    }

    func testEmptyModuleListCompletesImmediately() async {
        let c = ScanCoordinator()
        c.scanAll()
        for _ in 0..<50 {
            if case .completed = c.state { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard case .completed(let results) = c.state else {
            return XCTFail("Expected completed")
        }
        XCTAssertTrue(results.isEmpty)
    }
}
