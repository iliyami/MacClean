# Community Feedback (#21) — Prioritized Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement, task-by-task. Steps use checkbox (`- [ ]`) syntax.
>
> **Status: PLAN FOR REVIEW — do not execute yet.** Written at the user's request to review the prioritized backlog before any code is written.

**Goal:** Address the remaining, not-yet-shipped points from community issue #21 (@Anatharias bulk feedback), grouped into four reviewable PRs in priority order.

**Source:** GitHub issue #21. The other community issue, #23 (merge with momenbasel/PureMac), is a project/collaboration decision for the maintainer, not a code task — out of scope here.

**Already shipped (no work needed — relay back to the reporter):**
- #21.2 Smart Scan review-before-clean — done in #43 (checkboxes + confirm).
- #21.8 Space Lens hang + back navigation — done in #43 (#31 off-main scan, #38 Up/Home).
- #21.7 Maintenance failure reason shown — done in #41 (#36, inline message + orange icon).
- #21.1 Large/Old files not auto-selected (the 615 GB data-loss fear) — `LargeOldFilesModule` already emits `autoSelect: false`; Smart Scan only pre-checks auto-select categories. Verify + reply; no code change.

**Tech stack:** Swift 6, SwiftUI + AppKit, XCTest. PR workflow + local-CI gate apply (`bash scripts/check-version-sync.sh && swift build && swift test`). Bump VERSION + `MCConstants.appVersion` together per PR.

**Suggested versions (confirm at execution):** PR A → 1.7.1, PR B → 1.7.2, PR C → 1.8.0, PR D → 1.8.1.

**Priority order & rationale:**
- **A (file-list interaction)** — touches every module, low risk, high daily-use payoff.
- **B (uninstaller)** — core feature; adds a real delete-confirmation safety gate.
- **C (scan persistence)** — prevents lost work; architectural, higher risk.
- **D (settings + polish)** — lower-frequency polish.

---

# PR A — File-list interaction: fold/unfold, whole-row click, Reveal in Finder (→ 1.7.1)

Branch `feat/filelist-interaction`. Addresses #21.6, #21.13, #21.14. All in `Sources/MacClean/Views/Shared/FileListView.swift` (used by every module), so the win is global.

**Current state (verified):** `FileListView` renders `List { ForEach(results) { Section { rows } header: { CategoryHeaderView } } }`. The header is a single `Toggle` wrapping the icon+name (so clicking the name toggles *select-all*, never folds). Rows (`FileRowView`) only toggle via the checkbox `Toggle`; tapping the row body does nothing. No context menu anywhere.

### Task A1: Collapsible categories (#21.6)

**Files:**
- Create: `Sources/MacClean/Views/Shared/FileListExpansion.swift` (pure collapse state)
- Modify: `Sources/MacClean/Views/Shared/FileListView.swift`
- Test: `Tests/MacCleanTests/FileListExpansionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MacClean
@testable import MacCleanKit

final class FileListExpansionTests: XCTestCase {
    func testCategoriesStartExpandedAndToggle() {
        var exp = FileListExpansion()
        XCTAssertTrue(exp.isExpanded(.userCaches))       // default: expanded
        exp.toggle(.userCaches)
        XCTAssertFalse(exp.isExpanded(.userCaches))      // collapsed
        exp.toggle(.userCaches)
        XCTAssertTrue(exp.isExpanded(.userCaches))       // expanded again
    }
    func testCollapseIsPerCategory() {
        var exp = FileListExpansion()
        exp.toggle(.trashBins)
        XCTAssertFalse(exp.isExpanded(.trashBins))
        XCTAssertTrue(exp.isExpanded(.userLogs))
    }
}
```

- [ ] **Step 2: Run → FAIL** (`FileListExpansion` undefined): `swift test --filter "FileListExpansionTests"`

- [ ] **Step 3: Implement the model**

`FileListExpansion.swift`:
```swift
import Foundation
import MacCleanKit

/// Per-category collapse state for FileListView. Categories are expanded by
/// default; we only store the collapsed ones (SwiftUI-free, unit-testable).
struct FileListExpansion {
    private var collapsed: Set<ScanCategory> = []
    func isExpanded(_ c: ScanCategory) -> Bool { !collapsed.contains(c) }
    mutating func toggle(_ c: ScanCategory) {
        if collapsed.contains(c) { collapsed.remove(c) } else { collapsed.insert(c) }
    }
}
```
> Requires `ScanCategory: Hashable` (it's already used as `ForEach id` so it is).

- [ ] **Step 4: Wire into FileListView** — add `@State private var expansion = FileListExpansion()`, render rows only when expanded, and give `CategoryHeaderView` a **leading, always-visible, larger disclosure chevron** that toggles collapse (separate from the select-all checkbox). Replace the `Section`/header so the name no longer triggers select-all:

```swift
ForEach(results, id: \.category) { result in
    Section {
        if expansion.isExpanded(result.category) {
            ForEach(result.items) { item in
                FileRowView(item: item, isSelected: selectedItems.contains(item.url),
                            onToggle: { toggle(item.url) })
            }
        }
    } header: {
        CategoryHeaderView(
            category: result.category, totalSize: result.totalSize, fileCount: result.fileCount,
            isExpanded: expansion.isExpanded(result.category),
            allSelected: result.items.allSatisfy { selectedItems.contains($0.url) },
            onToggleExpand: { withAnimation { expansion.toggle(result.category) } },
            onToggleAll: { toggleAll(result) }
        )
    }
}
```
In `CategoryHeaderView`, put the chevron first as its own button, then the select-all checkbox, then the name (name tap also calls `onToggleExpand`):
```swift
HStack(spacing: 8) {
    Button(action: onToggleExpand) {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 13, weight: .semibold)).frame(width: 18)
    }.buttonStyle(.plain)
    Toggle(isOn: Binding(get: { allSelected }, set: { _ in onToggleAll() })) { EmptyView() }
        .toggleStyle(.checkbox).labelsHidden()
    Image(systemName: category.systemImage).foregroundStyle(.secondary)
    Text(category.displayName).font(.headline)
        .contentShape(Rectangle()).onTapGesture(perform: onToggleExpand)
    Spacer()
    Text("\(fileCount) files").font(.caption).foregroundStyle(.tertiary)
    Text(FileSizeFormatter.format(totalSize)).font(.caption).foregroundStyle(.secondary).fontWeight(.medium)
}
```
Extract the existing toggle/toggle-all closures into private `toggle(_:)` / `toggleAll(_:)` methods on `FileListView`.

- [ ] **Step 5: Run → PASS**, `swift build`. Commit.

### Task A2: Whole-row click toggles selection (#21.13)

**Files:** Modify `FileListView.swift` (`FileRowView`).

- [ ] **Step 1:** Make the entire row a hit target that calls `onToggle` (not just the checkbox). Add to `FileRowView`'s root `HStack`:
```swift
.contentShape(Rectangle())
.onTapGesture { onToggle() }
```
The checkbox stays as a visual indicator (its binding still reflects `isSelected`). Verify tapping anywhere on the row toggles it.
- [ ] **Step 2:** `swift build`; manual check. (View-only; covered behaviorally by the existing selection flow — no separate unit test.) Commit.

### Task A3: Reveal in Finder context menu (#21.14)

**Files:** Modify `FileListView.swift` (`FileRowView`), add `import AppKit`.

- [ ] **Step 1: Failing test for the pure action target**

```swift
// In FileListExpansionTests.swift or a new RevealActionTests.swift
func testRevealTargetIsItemURL() {
    let url = URL(filePath: "/tmp/x.cache")
    XCTAssertEqual(FileRowReveal.target(for: url), url)
}
```

- [ ] **Step 2:** Add the trivial pure helper + context menu:
```swift
enum FileRowReveal { static func target(for url: URL) -> URL { url } }
```
On `FileRowView`'s root view:
```swift
.contextMenu {
    Button("Reveal in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([FileRowReveal.target(for: item.url)])
    }
}
```
- [ ] **Step 3:** Test PASS, `swift build`, commit.

### Task A4: PR A version bump + ship
- [ ] Bump VERSION + appVersion → 1.7.1; `bash scripts/check-version-sync.sh && swift build && swift test`; push; open PR (closes the #21.6/#21.13/#21.14 sub-points — reference #21).

---

# PR B — Uninstaller: confirm dialog, real icons, removable Apple apps (→ 1.7.2)

Branch `feat/uninstaller-ux`. Addresses #21.11, #21.10, #21.12. All in `Sources/MacClean/Views/Applications/UninstallerView.swift` (+ a SafetyGuard test).

**Current state (verified):** `uninstall(app)` trashes immediately on click (no confirmation — a spinner was added recently but no confirm). Rows/detail use SF Symbols (`app.fill`/`apple.logo`), not the real icon. Uninstall is gated by `if !app.isAppleApp`, so *all* Apple apps are unremovable.

### Task B1: Confirmation dialog before uninstall (#21.11)

**Files:** Modify `UninstallerView.swift`.

- [ ] **Step 1:** Add `@State private var appPendingUninstall: AppInfo?`. Change the Uninstall button to set it instead of calling `uninstall` directly:
```swift
Button("Uninstall") { appPendingUninstall = app }
```
Attach an alert on the detail view (SwiftUI `.alert` auto-centers on the window — fixes "not centered"):
```swift
.alert("Move \(appPendingUninstall?.name ?? "this app") to the Trash?",
       isPresented: Binding(get: { appPendingUninstall != nil },
                            set: { if !$0 { appPendingUninstall = nil } }),
       presenting: appPendingUninstall) { app in
    Button("Cancel", role: .cancel) { appPendingUninstall = nil }
    Button("Move to Trash", role: .destructive) { let a = app; appPendingUninstall = nil; uninstall(a) }
} message: { app in
    Text("\(app.name) and its \(associatedFiles.count) associated file(s) will be moved to the Trash. You can restore them from the Trash if needed.")
}
```
The existing `isUninstalling` spinner still applies once `uninstall` runs.
- [ ] **Step 2:** `swift build`; manual check (view-only). Commit.

### Task B2: Show real app icons (#21.10)

**Files:** Modify `UninstallerView.swift`.

- [ ] **Step 1:** Replace the SF-Symbol images in both the list row and the detail header with the real bundle icon via AppKit (reliable for any app):
```swift
Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path(percentEncoded: false)))
    .resizable().frame(width: 32, height: 32)
```
(Add `import AppKit` if missing.) Keep a graceful fallback if the path is gone.
- [ ] **Step 2:** `swift build`; manual check. Commit.

### Task B3: Allow removing non-critical Apple apps (#21.12)

**Files:** Modify `UninstallerView.swift`; Test: `Tests/MacCleanKitTests/SafetyGuardProtectedAppTests.swift` (create or extend).

- [ ] **Step 1: Failing test** (lock the policy — `SafetyGuard.isProtectedApp` already exists, driven by `MCConstants.protectedApps`):
```swift
import XCTest
@testable import MacCleanKit
final class SafetyGuardProtectedAppTests: XCTestCase {
    func testRemovableVsProtectedAppleApps() {
        let g = SafetyGuard()
        XCTAssertTrue(g.isProtectedApp("com.apple.finder"))     // never removable
        XCTAssertTrue(g.isProtectedApp("com.apple.Safari"))
        XCTAssertFalse(g.isProtectedApp("com.apple.garageband")) // removable
    }
}
```
- [ ] **Step 2: Run → confirm it passes already OR adjust** the `protectedApps` set if a critical app is missing. (GarageBand isn't in the set, so it's removable; Finder/Safari/etc. are.)
- [ ] **Step 3:** In `UninstallerView`, gate the Uninstall affordance on protection instead of "is Apple app". Add `private let safetyGuard = SafetyGuard()` and replace `if !app.isAppleApp { … Uninstall … }` with:
```swift
if !safetyGuard.isProtectedApp(app.bundleIdentifier) {
    // Uninstall / Reset buttons (or spinner)
} else {
    Text("Protected system app — can't be removed")
        .font(.system(size: 11)).foregroundStyle(.secondary)
}
```
Optionally show a subtle "Apple app" note when `app.isAppleApp && !protected`.
- [ ] **Step 4:** Test PASS, `swift build`, commit.

### Task B4: PR B version bump + ship
- [ ] Bump → 1.7.2; local CI; push; open PR (reference #21.10/.11/.12).

---

# PR C — Preserve scans when switching categories (→ 1.8.0)

Branch `feat/scan-persistence`. Addresses #21.3. **Architectural — higher risk.** Today each module view owns its own `@State results`, so navigating away discards the scan and its selection.

**Approach:** introduce a shared, observable results store on `AppState` keyed by module, and have the module views read/write it instead of local `@State`.

### Task C1: Results store (pure/observable, tested)

**Files:**
- Create: `Sources/MacClean/App/ScanResultsStore.swift`
- Modify: `Sources/MacClean/App/AppState.swift` (hold an instance)
- Test: `Tests/MacCleanTests/ScanResultsStoreTests.swift`

- [ ] **Step 1: Failing test**
```swift
import XCTest
@testable import MacClean
@testable import MacCleanKit
final class ScanResultsStoreTests: XCTestCase {
    func testStoreAndRetrieveByModule() {
        let store = ScanResultsStore()
        let r = [ScanResult(category: .userCaches, items: [])]
        store.set(results: r, selection: [URL(filePath: "/a")], for: .systemJunk)
        XCTAssertEqual(store.results(for: .systemJunk)?.count, 1)
        XCTAssertEqual(store.selection(for: .systemJunk), [URL(filePath: "/a")])
        XCTAssertNil(store.results(for: .trashBins))   // isolated per module
    }
    func testClear() {
        let store = ScanResultsStore()
        store.set(results: [], selection: [], for: .trashBins)
        store.clear(.trashBins)
        XCTAssertNil(store.results(for: .trashBins))
    }
}
```
- [ ] **Step 2: Implement** (`@Observable` final class keyed by `SidebarItem`, storing `(results, selection)`); add `let scanResultsStore = ScanResultsStore()` to `AppState`. Run → PASS.

### Task C2: Migrate one module view as the pattern (System Junk)
- [ ] Convert `SystemJunkView`/`SystemJunkViewModel` to read/write `appState.scanResultsStore` for `.systemJunk` instead of local `@State`. Verify scanning, switching away, and returning preserves results + selection. Commit. **Checkpoint for review before migrating the rest.**

### Task C3: Migrate remaining module views
- [ ] Apply the same pattern to Trash Bins, Mail Attachments, Malware, Privacy, Large & Old Files, Duplicates (the `[ScanResult]`-based views). One commit per view; manual verification each. (Uninstaller/Optimization/Maintenance/SpaceLens hold live state, not scan results — leave as-is or cache separately if desired.)

### Task C4: PR C version bump + ship
- [ ] Bump → 1.8.0; local CI; push; open PR (#21.3).

> Risk note: this changes state ownership across many views. Keep each view migration a separate commit; the store has unit tests, but the per-view wiring needs manual verification (scan → switch → return).

---

# PR D — Settings & consistency polish (→ 1.8.1)

Branch `feat/settings-polish`. Addresses #21.5, #21.9, #21.4.

### Task D1: User setting for preserved languages (#21.5)

**Files:**
- Modify: `Sources/MacCleanKit/Constants.swift` or a new `LanguagePreferences` in MacCleanKit (read from `UserDefaults`)
- Modify: `Sources/MacCleanKit/Categories/SimpleCategories.swift` (consume the user set, not the hardcoded one)
- Modify: `Sources/MacClean/Views/Settings/SettingsView.swift` (add a "Language cleanup" section)
- Test: `Tests/MacCleanKitTests/LanguagePreferencesTests.swift`

- [ ] **Step 1: Failing test** — the effective preserved set = built-in defaults (`en`, `Base`, …) ∪ user-kept languages; never empty:
```swift
func testEffectivePreservedMergesDefaultsAndUser() {
    let eff = LanguagePreferences.effectivePreserved(userKept: ["fr.lproj"])
    XCTAssertTrue(eff.contains("en.lproj"))   // defaults always kept
    XCTAssertTrue(eff.contains("Base.lproj"))
    XCTAssertTrue(eff.contains("fr.lproj"))   // user addition
}
```
- [ ] **Step 2:** Implement `LanguagePreferences` (defaults from current `preservedLanguages`, user additions from `UserDefaults` key `keptLanguages`); point `SimpleCategories` language-cleanup `excludePatterns` at `LanguagePreferences.effectivePreserved(...)`. Run → PASS.
- [ ] **Step 3:** Add a Settings section: a list of common languages with toggles (persist to `UserDefaults`). `swift build`, manual check. Commit.

### Task D2: Consistent primary-button placement (#21.9)
- [ ] Audit module views; the `ModuleContainerView`-based ones already share a layout. Align the custom-header views (`UpdaterView`, `OptimizationView`, `MaintenanceView`, `SpaceLensView`, `UninstallerView`, `SmartScanView`) to one convention: **primary action top-right in the header**. View-only; one commit; manual visual check across modules.

### Task D3: Sidebar toggle (#21.4)
- [ ] Investigate the "irrelevant" control — it's the native `NavigationSplitView` sidebar toggle. Decide: keep (standard macOS), or suppress via toolbar customization. Low priority; document the decision in the PR. (May be WONTFIX if it's the standard control.)

### Task D4: PR D version bump + ship
- [ ] Bump → 1.8.1; local CI; push; open PR (#21.4/.5/.9).

---

## Self-review notes
- **Coverage of #21's open points:** .3→PR C; .4→D3; .5→D1; .6→A1; .9→D2; .10→B2; .11→B1; .12→B3; .13→A2; .14→A3. Already shipped: .1, .2, .7, .8.
- **Risk ranking:** A low (one shared view + pure model), B low–medium (confirm flow + icon + policy), C medium–high (state ownership across views — migrate incrementally with a checkpoint), D low–medium.
- **Unknowns to confirm at execution:**
  1. `ScanCategory` Hashable conformance (used as ForEach id, so yes) for `FileListExpansion`.
  2. Whether `AppInfo.iconPath` is populated — plan uses `NSWorkspace.icon(forFile:)` to avoid depending on it.
  3. Exact list of module views that should participate in the scan cache (PR C) — start with System Junk as the reviewed pattern.
  4. `protectedApps` completeness before enabling Apple-app removal (B3) — review the set so nothing critical becomes removable.
- **Not a code task:** #23 (merge with PureMac) — maintainer decision; reply on the issue.
