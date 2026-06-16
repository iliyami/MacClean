# Cleaning-list redesign (issue #85)

## Problem
The scan-results / "Ready to clean" list is too short and visually flat, making it a pain to review before deleting. Reference: Mole Desktop's grouped, taller, richer list.

## Constraint
Keep the virtualized `NSTableView` (`FileTableView`, from #74) — the list can hold tens of thousands of rows. This is an enhancement of the existing shared component, not a rebuild, so it lands on every results screen (SmartScan + each module).

## Changes

### MacCleanKit (pure, TDD)
- `ScanCategory.subtitle: String` — one-line description per category (e.g. user caches → "App temporary files. Regenerated next launch.").
- `FileListHeader`: add `selectedCount: Int` and `selectedSize: UInt64`; replace `allSelected: Bool` with `selection: SelectionState` (`none` / `mixed` / `all`) derived from `selectedCount` vs `fileCount`.
- `FileListRow.item` gains `appRunning: Bool`.
- `FileListRows.flatten(results:isExpanded:selectedItems:runningBundleIDs:)` — computes per-category `selectedCount`/`selectedSize`, derives `selection`, and marks each item `appRunning` when its owning bundle id is in `runningBundleIDs`.
- New `AppCacheOwnership.owningBundleID(for: URL) -> String?` — extracts a bundle id from `Caches/<id>/…`, `Containers/<id>/…`, and a small browser lookup (Arc, Chrome, …). Returns nil when undeterminable (best effort).

### MacClean (AppKit/SwiftUI)
- `FileTableView` header cell: subtitle line; count → `selected/total selected`; size → `selectedSize / totalSize`; checkbox supports `.mixed`.
- `FileTableView` item cell: inline **info** + **reveal** buttons; an **"App open"** pill when `appRunning`.
- `FileListView`: pass `runningBundleIDs` (from `NSWorkspace.runningApplications`) into `flatten`.
- `SmartScanView`: remove the `maxHeight: 280` cap so the list fills the window; restyle the footer to `X/Y selected` + a white `Permanently clean · <selectedSize>` pill.
- Per-group "card" look: approximate via group background + rounded top on header / bottom on last item + spacing between groups. Pixel-parity here is best-effort and may take iteration.

## Testing
- TDD the pure pieces: `flatten` (selected counts/sizes, selection state, appRunning), `AppCacheOwnership` path→bundle-id, `ScanCategory.subtitle` non-empty for all cases.
- Cells/visuals: build + manual dev-install eyeball.

## Out of scope / accepted caveats
- App-open detection is best-effort; caches that don't encode a bundle id show no badge.
- Group-card visuals approximate the mockup, not guaranteed pixel-perfect first pass.
