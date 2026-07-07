import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit
import MacCleanTestSupport

/// Integration tests for `CleaningEngine`. These use real tmp directories
/// because the engine's job is to interact with the filesystem; mocking
/// `FileManager` would only test stub behavior, not the actual outcomes.
final class CleaningEngineTests: XCTestCase {

    /// The engine refuses anything outside the safe paths (`~/Library/Caches` etc.).
    /// To exercise it we need a fake item URL that's under userCaches but actually
    /// points at our tmp file via a symlink trick — too fragile. Instead, we test
    /// the engine by giving it inputs we know `SafetyGuard` allows.
    ///
    /// Strategy: write tmp files under `~/Library/Caches/MacCleanTest-<uuid>/`
    /// for the duration of the test, then clean them up.

    private static let testCachesRoot = MCConstants.userCaches
        .appending(path: "MacCleanTest-\(UUID().uuidString)")

    private static func makeTestDir() throws -> URL {
        let dir = MCConstants.userCaches
            .appending(path: "MacCleanTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cleanupTestDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeFileItem(at url: URL, size: UInt64 = 0) -> FileItem {
        FileItem(
            url: url,
            name: url.lastPathComponent,
            size: size,
            allocatedSize: size,
            isDirectory: false
        )
    }

    // MARK: - Dry-run mode

    func testDryRunNeverDeletes() async throws {
        let dir = try Self.makeTestDir()
        defer { Self.cleanupTestDir(dir) }

        let file = dir.appending(path: "dryrun.cache")
        try TestFixtures.writeFile(at: file, size: 1234)

        let engine = CleaningEngine()
        let result = await engine.clean(items: [makeFileItem(at: file, size: 1234)], mode: .dryRun)

        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.freedBytes, 1234)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)),
                      "File must still exist after dry-run")
    }

    func testDryRunReportsCountsCorrectly() async throws {
        let dir = try Self.makeTestDir()
        defer { Self.cleanupTestDir(dir) }

        var items: [FileItem] = []
        for i in 0..<10 {
            let url = dir.appending(path: "f\(i).cache")
            try TestFixtures.writeFile(at: url, size: 100)
            items.append(makeFileItem(at: url, size: 100))
        }

        let result = await CleaningEngine().clean(items: items, mode: .dryRun)
        XCTAssertEqual(result.removedCount, 10)
        XCTAssertEqual(result.freedBytes, 1000)
        for item in items {
            XCTAssertTrue(FileManager.default.fileExists(atPath: item.url.path(percentEncoded: false)))
        }
    }

    // MARK: - One unsafe path must not cancel the whole clean (#104)

    func testOneUnsafePathDoesNotSkipTheWholeChunk() async throws {
        // Reporter #104: a single printer-PPD symlink that resolved outside its
        // location made SafetyGuard reject the whole batch, so the engine
        // skipped the ENTIRE selection and cleaned nothing (while reporting
        // "done"). A safe file alongside it must still be cleaned.
        let dir = try Self.makeTestDir()
        defer { Self.cleanupTestDir(dir) }

        let good = dir.appending(path: "good.cache")
        try TestFixtures.writeFile(at: good, size: 500)

        // A symlink whose target resolves to a different location, the exact
        // shape SafetyGuard's symlink check rejects (like the CUPS PPD symlink).
        let badLink = dir.appending(path: "printer.ppd")
        try FileManager.default.createSymbolicLink(
            at: badLink, withDestinationURL: URL(fileURLWithPath: "/private/etc/hosts"))

        let items = [makeFileItem(at: good, size: 500), makeFileItem(at: badLink)]
        let result = await CleaningEngine().clean(items: items, mode: .dryRun)

        XCTAssertEqual(result.removedCount, 1, "the safe file must still be cleaned")
        XCTAssertEqual(result.freedBytes, 500)
        XCTAssertEqual(result.errors.count, 1, "only the unsafe path should error")
        XCTAssertTrue(result.errors.first?.path.contains("printer.ppd") ?? false,
                      "the error should name the offending path, not the whole chunk")
    }

    // MARK: - Trash mode

    func testTrashModeMovesToTrash() async throws {
        let dir = try Self.makeTestDir()
        defer { Self.cleanupTestDir(dir) }

        let file = dir.appending(path: "trash-me.cache")
        try TestFixtures.writeFile(at: file, size: 500)

        let engine = CleaningEngine()
        let result = await engine.clean(items: [makeFileItem(at: file, size: 500)], mode: .trash)

        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.freedBytes, 500)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)),
                       "File should no longer be at the original path")
    }

    // MARK: - Permanent mode

    func testPermanentModeRemoves() async throws {
        let dir = try Self.makeTestDir()
        defer { Self.cleanupTestDir(dir) }

        let file = dir.appending(path: "permanent.cache")
        try TestFixtures.writeFile(at: file, size: 200)

        let engine = CleaningEngine()
        let result = await engine.clean(items: [makeFileItem(at: file, size: 200)], mode: .permanent)

        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.freedBytes, 200)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    // MARK: - Error handling

    /// SPEC: a file the scanner saw but that's gone by clean time
    /// (typical for cache daemons that regenerate constantly) is a
    /// benign skip, NOT a user-visible error. Cache churn is normal;
    /// surfacing thousands of "no such file" errors mislead the user
    /// into thinking the cleanup was broken when nothing was wrong.
    func testMissingFileIsBenignSkip_notError() async throws {
        let dir = try Self.makeTestDir()
        defer { Self.cleanupTestDir(dir) }

        let missingFile = dir.appending(path: "never-existed.cache")
        let result = await CleaningEngine().clean(
            items: [makeFileItem(at: missingFile, size: 0)],
            mode: .trash
        )

        XCTAssertEqual(result.errors.count, 0,
            "missing files between scan and clean must be silent skips, " +
            "not user-facing errors — cache daemons churn constantly")
        XCTAssertEqual(result.skippedCount, 1, "the missing file is counted as skipped")
        XCTAssertEqual(result.removedCount, 0)
    }

    func testSafetyValidationBlocksWholeBatch() async {
        let unsafeItem = FileItem(
            url: URL(filePath: "/System/Library/CoreServices/Finder.app"),
            name: "Finder.app",
            size: 100,
            allocatedSize: 100,
            isDirectory: true
        )
        let result = await CleaningEngine().clean(items: [unsafeItem], mode: .dryRun)
        XCTAssertEqual(result.removedCount, 0)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertFalse(result.errors.isEmpty)
    }

    // MARK: - Spec: arbitrary-size selections must be processed
    //
    // Real users have caches with 50k-200k entries (Chrome alone, etc).
    // The engine MUST process every item the user selected, not refuse the
    // whole batch wholesale. Internal chunking keeps the per-chunk safety
    // net at MCConstants.maxFilesPerOperation while letting total size be
    // bounded only by maxTotalItemsPerCleanOperation.

    /// SPEC: a 12,000-item selection (above the old 10k per-batch cap)
    /// processes every item — no single batch-level rejection.
    func testEngine_processesSelectionsAboveOldPerBatchCap() async {
        let items = (0..<12_000).map {
            FileItem(
                url: MCConstants.userCaches.appending(path: "macclean-spec-large-batch-\($0)"),
                name: "f\($0)",
                size: 1,
                allocatedSize: 1,
                isDirectory: false
            )
        }
        let result = await CleaningEngine().clean(items: items, mode: .dryRun)

        // dryRun always reports success on items that pass per-item
        // validation; user-cache paths are safe → all 12k should be
        // "removed" (counted) in dryRun mode.
        XCTAssertEqual(result.removedCount, 12_000,
            "every item the user selected must be processed; old behavior " +
            "rejected the whole batch when count > maxFilesPerOperation")
        XCTAssertEqual(result.skippedCount, 0,
            "no per-item validation failure expected for user-cache paths")
    }

    /// SPEC: a genuinely runaway selection (> maxTotalItemsPerCleanOperation)
    /// is refused cleanly with a single, informative error message — not
    /// a generic "validation failed" line. The UI surfaces this directly.
    func testEngine_refusesGenuinelyRunawaySelections() async {
        // Build just over the upper bound. Note: the spec is about
        // BEHAVIOR (refuse + informative message), not the exact number.
        let count = MCConstants.maxTotalItemsPerCleanOperation + 1
        let items = (0..<count).map { i in
            FileItem(
                url: MCConstants.userCaches.appending(path: "runaway-\(i)"),
                name: "f\(i)",
                size: 0,
                allocatedSize: 0,
                isDirectory: false
            )
        }
        let result = await CleaningEngine().clean(items: items, mode: .dryRun)

        XCTAssertEqual(result.removedCount, 0,
                       "runaway batch must be refused entirely, not partially processed")
        XCTAssertEqual(result.errors.count, 1,
                       "exactly one user-facing error explaining the limit")
        let msg = result.errors.first?.error ?? ""
        XCTAssertTrue(
            msg.contains("\(MCConstants.maxTotalItemsPerCleanOperation)") ||
            msg.localizedCaseInsensitiveContains("too many") ||
            msg.localizedCaseInsensitiveContains("limit"),
            "error message must reference the limit so the UI can show it: got '\(msg)'"
        )
    }

    // MARK: - Spec: progress reporting

    /// SPEC: when an `onProgress` callback is supplied, the engine emits
    /// at chunk boundaries. The callback is invoked with monotonically
    /// non-decreasing `processedItems`. Final callback's processedItems
    /// equals totalItems for a non-cancelled run.
    func testEngine_emitsProgressAtChunkBoundaries() async {
        let items = (0..<15_000).map {
            FileItem(
                url: MCConstants.userCaches.appending(path: "progress-spec-\($0)"),
                name: "f\($0)",
                size: 1,
                allocatedSize: 1,
                isDirectory: false
            )
        }

        // Capture all emissions via a thread-safe collector.
        let collector = ProgressCollector()
        let result = await CleaningEngine().clean(
            items: items, mode: .dryRun,
            onProgress: { progress in collector.append(progress) }
        )

        XCTAssertEqual(result.removedCount, 15_000)

        let snapshots = await collector.snapshots
        XCTAssertGreaterThanOrEqual(snapshots.count, 3,
            "15k items with chunk size 5k should emit at least 3 progress snapshots")
        XCTAssertEqual(snapshots.last?.processedItems, 15_000,
            "final emission must report totalItems processed for a non-cancelled run")
        // Monotonicity
        var lastProcessed = -1
        for snap in snapshots {
            XCTAssertEqual(snap.totalItems, 15_000,
                "totalItems must be stable across emissions")
            XCTAssertGreaterThanOrEqual(snap.processedItems, lastProcessed,
                "processedItems must never decrease")
            lastProcessed = snap.processedItems
        }
    }

    /// SPEC: progress emission stops on cancellation. The last emitted
    /// snapshot before the cancel has processedItems < totalItems.
    func testEngine_progressStopsOnCancellation() async throws {
        let items = (0..<60_000).map {
            FileItem(
                url: MCConstants.userCaches.appending(path: "cancel-progress-\($0)"),
                name: "f\($0)",
                size: 1,
                allocatedSize: 1,
                isDirectory: false
            )
        }

        let collector = ProgressCollector()
        let engine = CleaningEngine()
        let task = Task {
            await engine.clean(items: items, mode: .dryRun,
                               onProgress: { collector.append($0) })
        }
        try await Task.sleep(for: .milliseconds(5))
        task.cancel()
        _ = await task.value

        let snapshots = await collector.snapshots
        // Some progress may have emitted (a chunk or two) before cancel.
        // The KEY assertion: progress did NOT report 100% completion.
        if let last = snapshots.last {
            XCTAssertLessThan(last.processedItems, last.totalItems,
                "after cancellation, the last progress snapshot must reflect a partial state")
        }
    }

    /// Sendable thread-safe collector for progress snapshots emitted from
    /// the engine actor. Plain array + lock keeps the callback Sendable
    /// without dragging an actor type into the test setup.
    private actor ProgressCollector {
        private(set) var snapshots: [CleaningEngine.Progress] = []
        nonisolated func append(_ p: CleaningEngine.Progress) {
            Task { await self.add(p) }
        }
        private func add(_ p: CleaningEngine.Progress) { snapshots.append(p) }
    }

    /// SPEC: if the surrounding Task is cancelled mid-cleanup, the engine
    /// stops at the next safe boundary and returns a partial result —
    /// it doesn't hang or run to completion.
    func testEngine_cancellationHaltsCleanly() async throws {
        // Enough items that a few chunks have to run; cancellation should
        // catch us between chunks.
        let items = (0..<50_000).map {
            FileItem(
                url: MCConstants.userCaches.appending(path: "cancel-spec-\($0)"),
                name: "f\($0)",
                size: 1,
                allocatedSize: 1,
                isDirectory: false
            )
        }

        let engine = CleaningEngine()
        let task = Task { await engine.clean(items: items, mode: .dryRun) }
        // Give the engine a head start, then cancel.
        try await Task.sleep(for: .milliseconds(5))
        task.cancel()
        let result = await task.value

        XCTAssertLessThan(result.removedCount, items.count,
            "cancellation must stop processing before the whole selection is done")
    }

    // MARK: - Empty input

    func testEmptyInputProducesNoErrors() async {
        let result = await CleaningEngine().clean(items: [], mode: .dryRun)
        XCTAssertEqual(result.removedCount, 0)
        XCTAssertEqual(result.freedBytes, 0)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.skippedCount, 0)
    }

    // MARK: - Operation log

    func testOperationLogWritten() async throws {
        let dir = try Self.makeTestDir()
        defer { Self.cleanupTestDir(dir) }

        let file = dir.appending(path: "logged-cleanup.cache")
        try TestFixtures.writeFile(at: file, size: 42)

        _ = await CleaningEngine().clean(items: [makeFileItem(at: file, size: 42)], mode: .dryRun)

        let logFile = MCConstants.operationLogFile
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile.path(percentEncoded: false)),
                      "Operation log should exist after a clean operation")

        let contents = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        XCTAssertTrue(contents.contains("[DRY-RUN]"),
                      "Dry-run operations should be marked [DRY-RUN] in the log")
    }
}
