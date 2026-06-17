import Foundation
import MacCleanKit
import OSLog

public actor CleaningEngine {
    public enum CleanMode: Sendable {
        case trash
        case permanent
        case dryRun
    }

    public struct CleanResult: Sendable {
        public let removedCount: Int
        public let freedBytes: UInt64
        public let errors: [CleanError]
        public let skippedCount: Int
    }

    public struct CleanError: Sendable {
        public let path: String
        public let error: String
    }

    /// Per-chunk-boundary snapshot of an in-flight Clean operation.
    /// The engine emits one of these to `onProgress` after each chunk
    /// finishes processing — never per-item (would be the perf bottleneck
    /// for 100k-item runs). The View should treat it as eventually-
    /// consistent: a final emission with `processedItems == totalItems`
    /// is the "done" marker for UI purposes, though the actual
    /// CleanResult arrives via the async return.
    public struct Progress: Sendable, Equatable {
        public let totalItems: Int
        public let processedItems: Int
        public let removedSoFar: Int
        public let freedBytesSoFar: UInt64

        public var fraction: Double {
            totalItems > 0 ? Double(processedItems) / Double(totalItems) : 0
        }
    }

    private let safetyGuard = SafetyGuard()
    private let logger = Logger(subsystem: MCConstants.bundleIdentifier, category: "CleaningEngine")

    public init() {}

    /// Trash / permanently delete / dry-run the given items.
    ///
    /// Large selections (chrome cache alone often has 20k+ entries) are
    /// processed in chunks of `MCConstants.cleanChunkSize` so the per-chunk
    /// SafetyGuard batch validation never trips on legitimate cleanups.
    /// Selections beyond `MCConstants.maxTotalItemsPerCleanOperation`
    /// (500k) are refused entirely as a runaway-protection — that's
    /// orders of magnitude above any realistic user scenario and signals
    /// a scanner bug rather than user intent.
    ///
    /// `onProgress` (optional): a Sendable callback invoked once per
    /// completed chunk with a Progress snapshot. Callers wiring this to
    /// a SwiftUI @State must hop to the main actor inside the closure
    /// (the engine runs on its own actor; calling @MainActor-isolated
    /// setters from the closure body without dispatching is unsafe).
    public func clean(
        items: [FileItem],
        mode: CleanMode = .trash,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async -> CleanResult {
        // Upper bound: refuse genuinely runaway selections cleanly.
        if items.count > MCConstants.maxTotalItemsPerCleanOperation {
            let msg = L10n.tr("操作超过 \(MCConstants.maxTotalItemsPerCleanOperation) 项上限（尝试处理：\(items.count) 项）。这通常表示扫描器存在异常。", "Operation exceeds limit of \(MCConstants.maxTotalItemsPerCleanOperation) items (attempted: \(items.count)). This usually indicates a scanner bug.")
            logger.error("\(msg, privacy: .public)")
            return CleanResult(
                removedCount: 0,
                freedBytes: 0,
                errors: [CleanError(path: "validation", error: msg)],
                skippedCount: items.count
            )
        }

        var removedCount = 0
        var freedBytes: UInt64 = 0
        var errors: [CleanError] = []
        var skippedCount = 0

        // Internal chunking: SafetyGuard.validateDeletion runs per chunk
        // (capped at MCConstants.maxFilesPerOperation), so even arbitrary-
        // size total selections never blow past the per-batch cap. Yield
        // between chunks so the UI runloop can repaint during long runs
        // (a real fix for the UI freezing on 50k+ cleanups will come
        // when we add a progress channel in a follow-up release).
        let chunkSize = MCConstants.cleanChunkSize
        var startIndex = 0
        var processedSoFar = 0
        while startIndex < items.count {
            if Task.isCancelled { break }
            let endIndex = min(startIndex + chunkSize, items.count)
            let chunk = Array(items[startIndex..<endIndex])
            startIndex = endIndex

            processChunk(
                chunk, mode: mode,
                removedCount: &removedCount,
                freedBytes: &freedBytes,
                errors: &errors,
                skippedCount: &skippedCount
            )
            processedSoFar += chunk.count

            // Emit per-chunk progress so the UI can render an honest
            // progress bar on long runs. Per-item emission would itself
            // become the bottleneck.
            onProgress?(Progress(
                totalItems: items.count,
                processedItems: processedSoFar,
                removedSoFar: removedCount,
                freedBytesSoFar: freedBytes
            ))

            // Give the runloop room to breathe between chunks.
            await Task.yield()
        }

        logger.info("Cleaning complete: \(removedCount) removed, \(freedBytes) bytes freed, \(errors.count) errors")

        return CleanResult(
            removedCount: removedCount,
            freedBytes: freedBytes,
            errors: errors,
            skippedCount: skippedCount
        )
    }

    /// One chunk's worth of cleanup. Batch-validates the chunk's paths,
    /// then per-item processes if validation passed. On batch failure
    /// (typically a protected path slipping through scanner-side filtering),
    /// the whole chunk is skipped with a single error — partial
    /// processing of a malformed chunk isn't worth the surprise.
    private func processChunk(
        _ chunk: [FileItem],
        mode: CleanMode,
        removedCount: inout Int,
        freedBytes: inout UInt64,
        errors: inout [CleanError],
        skippedCount: inout Int
    ) {
        let urls = chunk.map(\.url)
        do {
            try safetyGuard.validateDeletion(paths: urls)
        } catch {
            logger.error("Chunk validation failed: \(error.localizedDescription)")
            errors.append(CleanError(path: "validation", error: error.localizedDescription))
            skippedCount += chunk.count
            return
        }

        for item in chunk {
            if Task.isCancelled { break }

            do {
                try safetyGuard.validatePath(item.url)
            } catch {
                skippedCount += 1
                errors.append(CleanError(
                    path: item.url.path(percentEncoded: false),
                    error: error.localizedDescription
                ))
                continue
            }

            // For directories, totalFileAllocatedSize doesn't recurse —
            // Apple's API returns 0 for dirs. Compute the real on-disk
            // size by walking the subtree BEFORE we trash it (after,
            // the path is gone). Without this, freedBytes massively
            // undercounts: trashing ~/Library/Caches/com.foo/ shows
            // "Zero KB freed" even when the dir held 200 MB.
            let realSize: UInt64 = item.isDirectory
                ? Self.recursiveAllocatedSize(of: item.url)
                : item.size

            switch mode {
            case .dryRun:
                removedCount += 1
                freedBytes += realSize
                logOperation(path: item.url, size: realSize, dryRun: true)

            case .trash:
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                    removedCount += 1
                    freedBytes += realSize
                    logOperation(path: item.url, size: realSize, dryRun: false)
                } catch let nsError as NSError where Self.isBenignMissingFile(nsError) {
                    // Cache churn: scanner saw the file, but a daemon
                    // (or our own earlier processing) removed it before
                    // we got here. Not a failure to surface to the user.
                    skippedCount += 1
                    logSkip(path: item.url, reason: L10n.tr("已不存在", "already gone"))
                } catch {
                    let msg = error.localizedDescription
                    errors.append(CleanError(
                        path: item.url.path(percentEncoded: false), error: msg
                    ))
                    logError(path: item.url, reason: msg)
                }

            case .permanent:
                do {
                    try FileManager.default.removeItem(at: item.url)
                    removedCount += 1
                    freedBytes += realSize
                    logOperation(path: item.url, size: realSize, dryRun: false)
                } catch let nsError as NSError where Self.isBenignMissingFile(nsError) {
                    skippedCount += 1
                    logSkip(path: item.url, reason: L10n.tr("已不存在", "already gone"))
                } catch {
                    let msg = error.localizedDescription
                    errors.append(CleanError(
                        path: item.url.path(percentEncoded: false), error: msg
                    ))
                    logError(path: item.url, reason: msg)
                }
            }
        }
    }

    /// Walks `url` recursively (using FileManager.enumerator) and sums
    /// per-file allocated sizes. Returns 0 if the URL doesn't exist
    /// or the enumeration fails.
    private static func recursiveAllocatedSize(of url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: []
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey, .isRegularFileKey,
            ])
            if values?.isRegularFile == true {
                total += UInt64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    /// True if the error is "file doesn't exist" — benign because cache
    /// daemons regenerate constantly; a file the scanner saw 30s ago may
    /// already be gone, and that's not a "user-facing error."
    private static func isBenignMissingFile(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain &&
           (error.code == NSFileNoSuchFileError ||
            error.code == NSFileReadNoSuchFileError) {
            return true
        }
        if error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return true
        }
        return false
    }

    private nonisolated func logOperation(path: URL, size: UInt64, dryRun: Bool) {
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        let prefix = dryRun ? "[DRY-RUN]" : "[REMOVED]"
        appendLogLine("\(prefix) \(path.path(percentEncoded: false)) (\(sizeStr))")
    }

    private nonisolated func logError(path: URL, reason: String) {
        appendLogLine("[ERROR] \(path.path(percentEncoded: false)) — \(reason)")
    }

    private nonisolated func logSkip(path: URL, reason: String) {
        appendLogLine("[SKIP] \(path.path(percentEncoded: false)) — \(reason)")
    }

    /// Appends a timestamped line to `operations.log`. Best-effort —
    /// any I/O failure here is silent because we never want logging to
    /// abort the cleanup it's narrating.
    private nonisolated func appendLogLine(_ body: String) {
        let fm = FileManager.default
        let logDir = MCConstants.operationLogDir
        let logFile = MCConstants.operationLogFile

        if !fm.fileExists(atPath: logDir.path(percentEncoded: false)) {
            try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(body)\n"

        guard let data = line.data(using: .utf8) else { return }
        if fm.fileExists(atPath: logFile.path(percentEncoded: false)) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
}
