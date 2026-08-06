# Duplicate Consolidation (DiskDedupe-style) Design

Issue: #65. Reclaim space from duplicate groups **without deleting any copy** by
replacing redundant copies with APFS clones of a chosen master. Every path keeps
working independently (copy-on-write); identical files stop costing N times their
size.

## Goal

Add a "Consolidate" mode to the Duplicates module alongside the existing
delete-based cleanup. In consolidate mode, the copies the user selects are
replaced in place with APFS clones of the kept master, so all paths remain but
the group stops consuming redundant storage.

## Non-goals (v1)

- Cross-volume consolidation (clones cannot span volumes).
- Non-APFS volumes (HFS+ hard links have riskier semantics for editable files).
- Teaching the scanner not to re-flag already-consolidated groups as reclaimable
  (needs `st_blocks` / clone-ID heuristics). Documented follow-up. Until then a
  re-scan simply shows ~0 reclaimable for a consolidated group, which is
  correct, just not hidden.

## Architecture

Two isolated layers.

### 1. `FileConsolidator` (MacCleanKit, pure, no SwiftUI)

Owns all filesystem risk. No UI or global state, so it is exhaustively testable
against the real APFS temp volume.

```
enum ConsolidationOutcome: Equatable, Sendable {
    case reclaimed(bytes: UInt64)
    case skipped(SkipReason)
    case failed(String)          // message for the activity log
}

enum SkipReason: Equatable, Sendable {
    case contentChanged          // master/copy differ now (changed since scan)
    case notSameVolume
    case cloningUnsupported      // volume is not APFS / no clone support
    case notRegularFile          // symlink, directory, or bundle
    case notWritable
    case protectedPath           // SafetyGuard would refuse it
}

struct ConsolidationSummary: Equatable, Sendable {
    var reclaimedBytes: UInt64
    var consolidatedCount: Int
    var skipped: [(url: URL, reason: SkipReason)]
    var failed: [(url: URL, message: String)]
}
```

#### Single-pair operation: `consolidate(master:copy:) -> ConsolidationOutcome`

The copy is only ever replaced by a byte-identical clone, and only via an atomic
rename, so a failure at any step leaves the original copy intact.

1. **Eligibility** (return `.skipped(reason)` on any failure):
   - `master` and `copy` are regular files (not directory, bundle, or symlink)
     via `URLResourceValues` `.isRegularFileKey` + `.isSymbolicLinkKey`, and
     `copy` is not a package (`.isPackageKey`).
   - Same volume: compare `st_dev` from `lstat` on both. Else `.notSameVolume`.
   - `copy`'s volume supports cloning:
     `copy.resourceValues(forKeys: [.volumeSupportsFileCloningKey])`. Else
     `.cloningUnsupported`.
   - `copy` and its parent directory are writable (`FileManager.isWritableFile`).
     Else `.notWritable`.
   - `copy` is not a SafetyGuard-protected path. Else `.protectedPath`.
2. **Re-verify identical NOW**: full-hash `master` and `copy` again (reuse
   `DuplicatesModule.fullHash`). If they differ, `.skipped(contentChanged)`.
   This is the TOCTOU guard, matching the app's re-resolve-before-delete policy.
3. **Snapshot** the copy's current POSIX mode + mtime and its allocated size
   (`st_blocks * 512`, the number reported as reclaimed).
4. **Clone**: `clonefile(masterPath, tempPath, 0)` where `tempPath` is a unique
   `.<name>.consolidate-<uuid>` in the copy's own directory (same volume, so the
   later rename is atomic). `clonefile` refuses to overwrite, and the temp name
   is unique, so there is no clobber risk. On failure -> `.failed`.
5. **Verify the clone**: full-hash `tempPath`; must equal the master hash.
   Mismatch -> unlink temp, `.failed`.
6. **Preserve identity**: apply the snapshotted mode + mtime to `tempPath` so the
   visible file keeps its own metadata rather than the master's.
7. **Atomic swap**: `rename(tempPath, copyPath)`. POSIX rename is atomic on one
   volume. On failure -> unlink temp, `.failed`; original copy untouched.
8. Return `.reclaimed(bytes: snapshottedAllocatedSize)`.

Reported reclaimed bytes is the copy's on-disk allocated size, which is accurate
for a genuinely redundant copy. If a user re-consolidates a group whose copies
are already clones, the number overstates the real (near-zero) saving because
detecting pre-existing shared extents is the deferred scanner concern. The
operation stays correct (no corruption); only the reported figure is optimistic
in that edge case.

Safety property: even if another process holds `copy` open, the swap is safe. The
old inode's content is byte-identical to the new clone, so a stale open handle
sees the same bytes.

#### Batch: `consolidate(groups:) -> ConsolidationSummary`

Input is a list of `(master: URL, copies: [URL])`. Iterates every copy, calls the
single-pair op, aggregates. Checks `Task.isCancelled` between items and stops
early (matching the cancel behaviour just shipped in #124). Pure aggregation, no
UI.

#### Dry-run estimate: `estimateReclaimable(groups:) -> UInt64`

Sums the allocated size of each eligible selected copy without writing anything.
Powers the confirmation preview. Eligibility reuses step 1 only.

### 2. `DuplicatesView` mode toggle (UI)

- New `@State private var actionMode: DuplicatesActionMode = .remove`
  (`enum DuplicatesActionMode { case remove, consolidate }`).
- A segmented `Picker` above the results: "Remove duplicates" | "Consolidate".
- Selection semantics are unchanged: per group, the one kept copy is the master;
  the selected copies are the ones acted on (deleted in remove mode, cloned in
  consolidate mode).
- Consolidate action:
  - Confirmation modal shows the dry-run estimate ("Keeps all copies, frees about
    X") from `estimateReclaimable`.
  - Runs `FileConsolidator.consolidate(groups:)` on a background `Task` with the
    existing progress affordance and the retained-task cancel pattern.
  - Done screen reports `reclaimedBytes`, `consolidatedCount`, and a compact list
    of skipped reasons (grouped) so nothing fails silently.
- Groups that are entirely ineligible for consolidation (cross-volume /
  non-APFS) show a one-line note and are excluded from the consolidate action but
  remain deletable in remove mode. Mixed groups consolidate the eligible copies
  and report the rest as skipped.

## Data flow

```
scan (existing) -> duplicate groups -> user selects copies + picks mode
  remove mode:      selected copies -> CleaningEngine (existing delete path)
  consolidate mode: (master = kept copy, copies = selected) per group
                    -> FileConsolidator.consolidate(groups:)
                    -> ConsolidationSummary -> done screen
```

## Error handling

- Per-copy isolation: a skip or failure never aborts the batch.
- Every skip/failure is surfaced on the done screen and written to the existing
  activity log (path + reason/message), consistent with the delete path.
- The confirmation preview never writes; it only estimates.

## Testing (TDD)

`FileConsolidator` is tested against the real APFS temp volume.

Deterministic:
- Two identical files -> both still exist and are byte-identical, master
  untouched, returned `reclaimed` equals the old copy's allocated size, and the
  copy keeps its own mtime/permissions (not the master's).
- Differing files -> `.skipped(contentChanged)`, both untouched.
- Copy is a symlink / directory / bundle -> `.skipped(notRegularFile)`.
- Idempotent second run -> no corruption, files still identical (the reported
  reclaimed figure may be optimistic on the second run, as noted above; the test
  asserts integrity, not the byte count).
- Batch with a mixed group (one eligible + one changed) -> summary aggregates
  reclaimed and skipped correctly, cancellation honoured between items.
- `estimateReclaimable` sums eligible copies and writes nothing (verify file
  bytes + mtimes unchanged after calling it).

Real space-reclaim proof (guards against "it just copied instead of cloned",
since a plain copy is also identical + independent):
- Create a master and identical copy of a moderately large file (about 20 MB),
  record `statfs` free space, consolidate, assert free space rose by most of the
  file size (tolerance, e.g. >= 70%). A non-clone copy-over would net roughly
  zero. Marked so it can be skipped if a run is on a non-APFS volume.

Eligibility predicates (`sameVolume`, `supportsCloning`, `isRegularFile`) are
factored as small pure helpers so their branches are unit-testable without
constructing every filesystem condition.

## Files

- `Sources/MacCleanKit/FileConsolidator.swift` (new) - the backend + types.
- `Tests/MacCleanTests/FileConsolidatorTests.swift` (new) - the suite above.
- `Sources/MacClean/Views/Files/DuplicatesView.swift` - mode toggle, consolidate
  action, done-screen reporting.
- `VERSION` + `Sources/MacCleanKit/Constants.swift` - minor bump (new feature).
