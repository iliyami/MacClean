import Foundation
import MacCleanKit

/// Single source of truth for "user clicked Clean."
///
/// Every view that has a Clean button MUST route through here. By centralizing
/// the call to `CleaningEngine` we guarantee:
///   1. Deletion is never silently `.dryRun` (which would report success
///      without touching the filesystem). Almost everything goes to `.trash`
///      so it stays recoverable — the one exception is `.trashBins`, which
///      is `.permanent`: those items are ALREADY in ~/.Trash, and
///      `FileManager.trashItem` on an already-trashed file is a silent
///      no-op (succeeds, but leaves the file in place), so emptying the
///      Trash requires an actual `removeItem`.
///   2. Item-filtering logic (intersect scan results with user selection) is
///      identical across every module, so behavior can't drift per-view.
///   3. There's exactly one place to audit when reviewing the deletion path.
///
/// This existed to fix the regression where every view was passing `.dryRun`
/// — see `CleanIsNotDryRunRegressionTests` for the static guard that prevents
/// the bug from coming back, and `CleanActionsTests` for the behavioral
/// verification that the engine actually moves files.
public enum CleanActions {

    /// Execute a user-initiated Clean operation against the given engine.
    /// Used by views that display `[ScanResult]` with per-item selection.
    ///
    /// Routes by category:
    ///   - `.universalBinaries` items are thinned in place via
    ///     `ThinBinaryOperation` — trashing an app's executable would break it.
    ///   - `.trashBins` items are deleted with `.permanent` mode: they already
    ///     live in ~/.Trash, where re-trashing them is a no-op, so emptying the
    ///     Trash means actually removing them.
    ///   - everything else goes through `engine.clean(..., .trash)` so it stays
    ///     recoverable from the Trash.
    @discardableResult
    public static func executeUserClean(
        results: [ScanResult],
        selectedItems: Set<URL>,
        engine: CleaningEngine,
        onProgress: (@Sendable (CleaningEngine.Progress) -> Void)? = nil
    ) async -> CleaningEngine.CleanResult {
        var trashItems: [FileItem] = []
        var permanentItems: [FileItem] = []
        var thinItems: [FileItem] = []
        for result in results {
            for item in result.items where selectedItems.contains(item.url) {
                switch result.category {
                case .universalBinaries:
                    thinItems.append(item)
                case .trashBins:
                    permanentItems.append(item)
                default:
                    trashItems.append(item)
                }
            }
        }

        // Dedup ancestors/descendants before dispatch. Scanner emits both
        // a directory AND every file inside it as separate items. Without
        // this filter the engine trashes the directory in one move,
        // then loops through every descendant — each of which now
        // points at a path that no longer exists, producing
        // "no such file" errors per descendant (one user reported 49,918
        // of them on a single Smart Scan). Keep ancestors; drop anything
        // whose URL lives under one. Applies equally to the permanent
        // (empty-Trash) path, where removeItem on the parent takes its
        // subtree with it.
        let dedupedTrashItems = Self.prunedToParents(trashItems)
        let dedupedPermanentItems = Self.prunedToParents(permanentItems)

        // In practice a single view supplies items of one kind (the Trash
        // Bins view is all `.trashBins`; every other view has none), so at
        // most one of these two engine calls does real work — wiring
        // onProgress to both is safe and never double-drives the bar.
        let trashResult = await engine.clean(items: dedupedTrashItems, mode: .trash,
                                             onProgress: onProgress)
        let permanentResult = await engine.clean(items: dedupedPermanentItems, mode: .permanent,
                                                 onProgress: onProgress)
        let thinResult = await thinSelectedBinaries(thinItems)
        return CleaningEngine.CleanResult(
            removedCount: trashResult.removedCount + permanentResult.removedCount + thinResult.removedCount,
            freedBytes: trashResult.freedBytes + permanentResult.freedBytes + thinResult.freedBytes,
            errors: trashResult.errors + permanentResult.errors + thinResult.errors,
            skippedCount: trashResult.skippedCount + permanentResult.skippedCount + thinResult.skippedCount
        )
    }

    /// Runs `ThinAppBundleOperation` against each item (item.url = bundle
    /// path) and folds the per-bundle outcomes into a
    /// `CleaningEngine.CleanResult` so the caller's "X items, Y MB freed"
    /// UI summary keeps working uniformly.
    private static func thinSelectedBinaries(
        _ items: [FileItem]
    ) async -> CleaningEngine.CleanResult {
        guard !items.isEmpty else {
            return CleaningEngine.CleanResult(
                removedCount: 0, freedBytes: 0, errors: [], skippedCount: 0
            )
        }
        let op = ThinAppBundleOperation()
        let targetArch = BundleHostInfo.current.hostArch
        var bundleCount = 0
        var savedBytes: UInt64 = 0
        var errors: [CleaningEngine.CleanError] = []
        for item in items {
            do {
                let r = try await op.thin(bundle: item.url, to: targetArch)
                bundleCount += 1
                savedBytes += r.bytesSaved
                for (path, msg) in r.perBinaryErrors {
                    errors.append(CleaningEngine.CleanError(
                        path: path, error: L10n.tr("二进制精简失败：\(msg)", "binary thin failed: \(msg)")
                    ))
                }
            } catch {
                errors.append(CleaningEngine.CleanError(
                    path: item.url.path(percentEncoded: false),
                    error: L10n.tr("应用包精简失败：\(error.localizedDescription)", "bundle thin failed: \(error.localizedDescription)")
                ))
            }
        }
        return CleaningEngine.CleanResult(
            removedCount: bundleCount,
            freedBytes: savedBytes,
            errors: errors,
            skippedCount: 0
        )
    }

    /// Execute a user-initiated Clean operation against a flat list of items.
    /// Used by the Uninstaller, which surfaces `[FileItem]` (associated files
    /// for a single app) rather than `[ScanResult]`.
    @discardableResult
    public static func executeUserClean(
        items: [FileItem],
        selectedItems: Set<URL>,
        engine: CleaningEngine,
        onProgress: (@Sendable (CleaningEngine.Progress) -> Void)? = nil
    ) async -> CleaningEngine.CleanResult {
        let filtered = items.filter { selectedItems.contains($0.url) }
        let deduped = Self.prunedToParents(filtered)
        return await engine.clean(items: deduped, mode: .trash,
                                  onProgress: onProgress)
    }

    /// Returns `items` with any FileItem whose URL is a strict descendant
    /// of another FileItem's URL removed. Trashing the ancestor takes
    /// the descendants with it; dispatching the descendants separately
    /// just produces "no such file" errors once the parent's gone.
    ///
    /// O(n log n): sort by path length ascending, then sweep — for each
    /// item, drop it iff any already-kept item's path is a prefix
    /// (ending at a `/` boundary).
    static func prunedToParents(_ items: [FileItem]) -> [FileItem] {
        guard items.count > 1 else { return items }
        let sorted = items.sorted {
            $0.url.path(percentEncoded: false).count < $1.url.path(percentEncoded: false).count
        }
        var keptPaths: [String] = []
        keptPaths.reserveCapacity(sorted.count)
        var kept: [FileItem] = []
        kept.reserveCapacity(sorted.count)
        for item in sorted {
            let path = item.url.path(percentEncoded: false)
            // Look for an ancestor among already-kept paths. Boundary
            // check on '/' prevents "/foo" matching "/foobar".
            let hasAncestor = keptPaths.contains { ancestor in
                path != ancestor &&
                path.hasPrefix(ancestor) &&
                (ancestor.hasSuffix("/") || path.dropFirst(ancestor.count).first == "/")
            }
            if !hasAncestor {
                kept.append(item)
                keptPaths.append(path)
            }
        }
        return kept
    }
}
