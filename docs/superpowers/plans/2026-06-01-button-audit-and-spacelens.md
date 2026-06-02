# Button Audit + SpaceLens UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up every dead/missing button found in a full-project audit, make the menu-bar tips deep-link to the right module, document the malware list, then give Smart Scan a real cleanup flow and fix SpaceLens (main-thread freeze + no zoom-out).

**Architecture:** Two PRs. **PR 1** is bug-fix-grade button wiring + a static regression guard so empty button actions can never ship again (patch bump → 1.6.2). **PR 2** is two real features — Smart Scan cleanup and SpaceLens — that need new logic and off-main-thread work (minor bump → 1.7.0). Both stay ≤ 1.7.x.

**Tech Stack:** Swift 6, SwiftUI + AppKit, XCTest, actors for off-main work, `CleanActions`/`CleaningEngine` for deletion, a `macclean://` URL scheme for deep links, the existing XPC privileged helper for root maintenance commands.

**GitHub issues:** #31 (SpaceLens freeze), #32 (Updater button), #33 (Uninstaller Reset), #34 (Launch Agent toggle), #35 (menu-bar deep-link), #36 (Free Up RAM), #37 (Smart Scan Clean), #38 (SpaceLens zoom-out), #39 (malware docs). **Deferred:** #40 (full verified in-place app install — future, own PR, 1.8.0).

**Final step (user-requested):** after both PRs' work is implemented, do a thorough self-review for conflicts — `git fetch`, check each branch rebases cleanly on `main`, no overlapping edits between PR1/PR2 left uncoordinated, and the full suite is green.

**Version sequencing:** assumes PR #30 (Trash fix, 1.6.1) merges first. PR 1 → 1.6.2, PR 2 → 1.7.0. Every code change bumps `VERSION` **and** `Sources/MacCleanKit/Constants.swift` `appVersion` together (CI guard: `scripts/check-version-sync.sh`).

**Local CI gate before every push (project rule):**
```bash
bash scripts/check-version-sync.sh && swift build && swift test
```

---

# PR 1 — Wire up dead buttons, menu-bar deep-links, malware docs (→ 1.6.2)

Branch off `origin/main`: `fix/wire-dead-buttons`.

Closes #32, #33, #34, #35, #36, #39.

---

### Task 1: Static regression guard — no empty `Button {}` actions in views

This is the red/green wrapper for the dead-button issues. It fails now (UpdaterView:71, UninstallerView:169) and forces every later task in this PR to actually wire its button.

**Files:**
- Test: `Tests/MacCleanTests/NoEmptyButtonActionsTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import Foundation

/// Guard against shipping a `Button("Label") {}` whose action is empty —
/// the exact class of bug behind issues #32 (Updater) and #33 (Uninstaller),
/// where a button rendered fine but did nothing. Mirrors the approach of
/// `CleanIsNotDryRunRegressionTests`: scan the view source, fail on offenders.
final class NoEmptyButtonActionsTests: XCTestCase {

    func testNoViewHasAnEmptyButtonAction() throws {
        let viewsDir = URL(filePath: #filePath)
            .deletingLastPathComponent()   // Tests/MacCleanTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appending(path: "Sources/MacClean/Views")

        // Matches `Button(...) {}` and `Button(...) { }` (empty trailing
        // closure) but NOT `Button(..., role: .cancel) { }` which is a
        // legitimate no-op dismiss inside an .alert.
        let emptyAction = #"Button\((?!.*role:\s*\.cancel)[^)]*\)\s*\{\s*\}"#

        var offenders: [String] = []
        let enumerator = FileManager.default.enumerator(at: viewsDir, includingPropertiesForKeys: nil)!
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if src.range(of: emptyAction, options: .regularExpression) != nil {
                offenders.append(url.lastPathComponent)
            }
        }

        XCTAssertTrue(offenders.isEmpty,
            "These views have a Button with an empty action — it looks live but does nothing: \(offenders)")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "NoEmptyButtonActionsTests/testNoViewHasAnEmptyButtonAction"`
Expected: FAIL — offenders include `UpdaterView.swift`, `UninstallerView.swift`.

- [ ] **Step 3: (No implementation in this task)** — Tasks 2 and 3 wire the offending buttons; this guard goes green once they do. Leave the test in place.

- [ ] **Step 4: Commit**

```bash
git add Tests/MacCleanTests/NoEmptyButtonActionsTests.swift
git commit -m "Add regression guard: no empty Button actions in views"
```

---

### Task 2: Updater "Update" button — route by source (MAS → App Store, Sparkle → download + reveal) (#32)

Match what dedicated updater apps do, scoped to fit ≤1.7.x: **Mac App Store** apps open the App Store updates page; **Sparkle** apps download the appcast's installer (DMG/ZIP) into `~/Downloads` and reveal it in Finder so the user drops it in. Full verified in-place install (download → verify EdDSA sig → replace `.app`) is deferred to **#40**. The route decision is a pure, testable function.

**Files:**
- Modify: `Sources/MacCleanKit/AppcastParser.swift` (also capture the `<enclosure url=…>` download URL)
- Modify: `Sources/MacClean/Modules/Updater/UpdaterModule.swift` (carry `downloadURL` on `AppUpdate`; add `UpdaterRoute` + `UpdaterActions`)
- Modify: `Sources/MacClean/Views/Applications/UpdaterView.swift:71`
- Test: `Tests/MacCleanKitTests/AppcastParserEnclosureTests.swift` (create), `Tests/MacCleanTests/UpdaterRouteTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

`Tests/MacCleanKitTests/AppcastParserEnclosureTests.swift`:

```swift
import XCTest
@testable import MacCleanKit

final class AppcastParserEnclosureTests: XCTestCase {
    func testParsesVersionAndDownloadURL() {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel><item>
            <enclosure url="https://example.com/App-4.3.dmg"
                       sparkle:shortVersionString="4.3"
                       sparkle:version="4300" length="123" type="application/octet-stream"/>
          </item></channel>
        </rss>
        """
        let parsed = AppcastParser().parseLatestItem(from: Data(xml.utf8))
        XCTAssertEqual(parsed.version, "4.3")
        XCTAssertEqual(parsed.downloadURL, URL(string: "https://example.com/App-4.3.dmg"))
    }
}
```

`Tests/MacCleanTests/UpdaterRouteTests.swift`:

```swift
import XCTest
import Foundation
@testable import MacClean

final class UpdaterRouteTests: XCTestCase {
    let dmg = URL(string: "https://example.com/App-4.3.dmg")!
    let appPath = URL(filePath: "/Applications/App.app")

    func testMacAppStoreAppRoutesToAppStore() {
        XCTAssertEqual(
            UpdaterActions.route(isMacAppStore: true, downloadURL: dmg, appPath: appPath),
            .appStore)
    }
    func testSparkleAppWithURLRoutesToDownload() {
        XCTAssertEqual(
            UpdaterActions.route(isMacAppStore: false, downloadURL: dmg, appPath: appPath),
            .download(dmg))
    }
    func testNoURLFallsBackToLaunchingTheApp() {
        XCTAssertEqual(
            UpdaterActions.route(isMacAppStore: false, downloadURL: nil, appPath: appPath),
            .launchApp(appPath))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AppcastParserEnclosureTests"` then `swift test --filter "UpdaterRouteTests"`
Expected: FAIL — `parseLatestItem` and `UpdaterActions` are undefined.

- [ ] **Step 3: Implement**

In `AppcastParser.swift`, capture the enclosure `url` alongside the version and add a combined entry point (keep `parseLatestVersion` for existing callers):

```swift
    private var latestDownloadURL: URL?

    /// Latest item's version + download URL in a single pass.
    public func parseLatestItem(from data: Data) -> (version: String?, downloadURL: URL?) {
        latestVersion = nil
        latestDownloadURL = nil
        inItem = false
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return (latestVersion, latestDownloadURL)
    }
```

In the existing `didStartElement`, extend the `enclosure` + `inItem` branch to also grab the URL once:

```swift
        if elementName == "enclosure", inItem {
            if let version = attributes["sparkle:shortVersionString"] ?? attributes["sparkle:version"],
               latestVersion == nil {
                latestVersion = version
            }
            if let urlStr = attributes["url"], let url = URL(string: urlStr), latestDownloadURL == nil {
                latestDownloadURL = url
            }
        }
```

In `UpdaterModule.swift`, add `downloadURL` to `AppUpdate` and populate it via `parseLatestItem`:

```swift
    public struct AppUpdate: Identifiable, Sendable {
        public let id: UUID = UUID()
        public let app: AppInfo
        public let currentVersion: String
        public let availableVersion: String?
        public let downloadURL: URL?
        public let updateSize: UInt64?
        public let hasUpdate: Bool
    }
```

In `checkApp`, replace the parse + return:

```swift
        let parser = AppcastParser()
        let (latestVersion, downloadURL) = parser.parseLatestItem(from: data)

        let currentVersion = app.version ?? "0"
        let hasUpdate = latestVersion != nil && latestVersion != currentVersion

        return AppUpdate(
            app: app,
            currentVersion: currentVersion,
            availableVersion: latestVersion,
            downloadURL: downloadURL,
            updateSize: nil,
            hasUpdate: hasUpdate
        )
```

> Any other `AppUpdate(...)` call site must add `downloadURL:`.

Append the route + actions to `UpdaterModule.swift`:

```swift
import AppKit

/// What the "Update" button does, chosen by how the app was installed.
/// Pure routing (testable) + a @MainActor executor (side-effecting).
public enum UpdaterRoute: Equatable {
    case appStore             // Mac App Store app → open App Store updates
    case download(URL)        // Sparkle app → download installer, reveal it
    case launchApp(URL)       // fallback: no download URL → open the app
}

public enum UpdaterActions {
    public static func route(isMacAppStore: Bool, downloadURL: URL?, appPath: URL) -> UpdaterRoute {
        if isMacAppStore { return .appStore }
        if let downloadURL { return .download(downloadURL) }
        return .launchApp(appPath)
    }

    /// A Mac App Store app ships a receipt at Contents/_MASReceipt/receipt.
    public static func isMacAppStoreApp(at appPath: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: appPath.appending(path: "Contents/_MASReceipt/receipt").path(percentEncoded: false))
    }

    @MainActor
    public static func perform(_ update: AppUpdateChecker.AppUpdate) {
        switch route(isMacAppStore: isMacAppStoreApp(at: update.app.path),
                     downloadURL: update.downloadURL, appPath: update.app.path) {
        case .appStore:
            if let url = URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(url) }
        case .download(let url):
            Task { await downloadAndReveal(url) }
        case .launchApp(let appURL):
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        }
    }

    /// Download the installer to ~/Downloads and reveal it in Finder.
    /// Falls back to opening the URL in the browser on any failure.
    @MainActor
    static func downloadAndReveal(_ url: URL) async {
        do {
            let (tmp, response) = try await URLSession.shared.download(from: url)
            let name = response.suggestedFilename ?? url.lastPathComponent
            let dest = MCConstants.downloads.appending(path: name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            NSWorkspace.shared.open(url)
        }
    }
}
```

In `UpdaterView.swift`, replace line 71:

```swift
                            Button("Update") { UpdaterActions.perform(update) }
```

> UX note (acceptable for this scope): the download has no inline progress yet — a spinner/disabled state during download is a nice follow-up but not required for #32.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "AppcastParserEnclosureTests"` and `swift test --filter "UpdaterRouteTests"` → PASS
Run: `swift test --filter "NoEmptyButtonActionsTests"` → UpdaterView no longer an offender.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacCleanKit/AppcastParser.swift Sources/MacClean/Modules/Updater/UpdaterModule.swift Sources/MacClean/Views/Applications/UpdaterView.swift Tests/MacCleanKitTests/AppcastParserEnclosureTests.swift Tests/MacCleanTests/UpdaterRouteTests.swift
git commit -m "Updater: route Update by source — App Store vs Sparkle download (#32)"
```

---

### Task 3: Uninstaller "Reset" button — clear selection (#33)

"Reset" sits next to "Uninstall" in the app-detail view; it should drop the selected app and return to the list.

**Files:**
- Modify: `Sources/MacClean/Views/Applications/UninstallerView.swift:169` (+ add `resetSelection()`)

- [ ] **Step 1: Confirm the guard covers it** — `NoEmptyButtonActionsTests` (Task 1) currently flags `UninstallerView.swift`. That is the red state for this task.

- [ ] **Step 2: Implement**

Add a method near the other private funcs in `UninstallerView`:

```swift
    private func resetSelection() {
        selectedApp = nil
        associatedFiles = []
        selectedFiles = []
        isLoadingFiles = false
    }
```

Replace line 169 `Button("Reset") {}` with:

```swift
                    Button("Reset") { resetSelection() }
```

- [ ] **Step 3: Run the guard to verify green**

Run: `swift test --filter "NoEmptyButtonActionsTests/testNoViewHasAnEmptyButtonAction"`
Expected: PASS — no offenders remain.

- [ ] **Step 4: Commit**

```bash
git add Sources/MacClean/Views/Applications/UninstallerView.swift
git commit -m "Uninstaller: wire Reset button to clear app selection (#33)"
```

---

### Task 4: Launch Agents enable/disable toggle (#34)

Add a toggle so users can disable e.g. "Zoom at login". `LaunchAgentsManager` gets a `toggleAgent` mirroring `LoginItemsManager.toggleItem` (flip the plist `Disabled` key). User agents only — system agents are read-only here (need root) and stay non-interactive.

**Files:**
- Modify: `Sources/MacClean/Modules/Optimization/OptimizationModule.swift` (add `toggleAgent`)
- Modify: `Sources/MacClean/Views/Performance/OptimizationView.swift` (add Toggle to `launchAgentsList`)
- Test: `Tests/MacCleanTests/LaunchAgentsManagerTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit
import MacCleanTestSupport

final class LaunchAgentsManagerTests: XCTestCase {
    func testToggleFlipsDisabledKeyInPlist() async throws {
        try await TestFixtures.withTempDir { dir in
            let plistURL = dir.appending(path: "com.example.zoom.plist")
            let plist: [String: Any] = ["Label": "com.example.zoom", "Disabled": false]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)

            let agent = LaunchAgentsManager.LaunchAgent(
                label: "com.example.zoom", path: plistURL,
                program: "/Applications/zoom.us.app", isSystem: false, isEnabled: true
            )
            let mgr = LaunchAgentsManager()
            try mgr.toggleAgent(agent, enabled: false)

            let after = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
            XCTAssertEqual(after["Disabled"] as? Bool, true)
        }
    }

    func testToggleRefusesSystemAgents() {
        let agent = LaunchAgentsManager.LaunchAgent(
            label: "com.apple.x", path: URL(filePath: "/Library/LaunchAgents/com.apple.x.plist"),
            program: nil, isSystem: true, isEnabled: true
        )
        XCTAssertThrowsError(try LaunchAgentsManager().toggleAgent(agent, enabled: false))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "LaunchAgentsManagerTests"`
Expected: FAIL — `toggleAgent` is undefined.

- [ ] **Step 3: Implement**

In `OptimizationModule.swift`, add to `LaunchAgentsManager`:

```swift
    public enum ToggleError: Error { case systemAgentReadOnly }

    /// Enable/disable a *user* launch agent by flipping its `Disabled`
    /// key — same mechanism as Login Items. System agents live in a
    /// root-owned directory and are refused here.
    public func toggleAgent(_ agent: LaunchAgent, enabled: Bool) throws {
        if agent.isSystem { throw ToggleError.systemAgentReadOnly }
        guard let data = try? Data(contentsOf: agent.path),
              var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }
        plist["Disabled"] = !enabled
        let newData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try newData.write(to: agent.path)
    }
```

In `OptimizationView.swift`, in `launchAgentsList`, replace the `if agent.isSystem { … "System" tag … }` trailing block so non-system agents get a toggle:

```swift
                    if agent.isSystem {
                        Text("System")
                            .font(.system(size: 10))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.orange.opacity(0.2)).clipShape(Capsule())
                    } else {
                        Toggle("", isOn: Binding(
                            get: { agent.isEnabled },
                            set: { newVal in
                                try? agentManager.toggleAgent(agent, enabled: newVal)
                                refresh()
                            }
                        ))
                        .toggleStyle(.switch)
                    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "LaunchAgentsManagerTests"` → PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MacClean/Modules/Optimization/OptimizationModule.swift Sources/MacClean/Views/Performance/OptimizationView.swift Tests/MacCleanTests/LaunchAgentsManagerTests.swift
git commit -m "Optimization: add enable/disable toggle for user launch agents (#34)"
```

---

### Task 5: Menu-bar tip CTAs deep-link to the right module (#35)

Register a `macclean://module/<id>` URL scheme. Menu-bar CTAs open the deep link; the main app routes the sidebar. Pure mapping is unit-tested; the wiring is thin.

**Files:**
- Modify: `Sources/MacClean/Views/Sidebar/SidebarView.swift` (add `deepLinkID` + `init?(deepLinkID:)` to `SidebarItem`)
- Modify: `Sources/MacClean/App/MacCleanApp.swift` (`.onOpenURL` handler)
- Modify: `Sources/MacCleanMenu/SystemStats/TipsEngine.swift` (`Tip.targetModuleID`, `TipAction.open(moduleID:)`)
- Modify: `Sources/MacCleanMenu/MacCleanMenuApp.swift:296` (call `TipAction.open(moduleID: tip.targetModuleID)`)
- Info.plist for the app target: register `CFBundleURLTypes` scheme `macclean` (see Step 3 note)
- Test: `Tests/MacCleanTests/DeepLinkRoutingTests.swift` (create), `Tests/MacCleanKitTests/TipTargetModuleTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

`Tests/MacCleanTests/DeepLinkRoutingTests.swift`:

```swift
import XCTest
@testable import MacClean

final class DeepLinkRoutingTests: XCTestCase {
    func testDeepLinkIDRoundTrips() {
        XCTAssertEqual(SidebarItem.systemJunk.deepLinkID, "system-junk")
        XCTAssertEqual(SidebarItem(deepLinkID: "system-junk"), .systemJunk)
        XCTAssertEqual(SidebarItem(deepLinkID: "trash-bins"), .trashBins)
        XCTAssertNil(SidebarItem(deepLinkID: "nonsense"))
    }
}
```

`Tests/MacCleanKitTests/TipTargetModuleTests.swift`:

```swift
import XCTest
@testable import MacCleanKit

// Pull the Tip type from the menu target's engine if it's accessible;
// if Tip lives in the menu target, move targetModuleID to a free function
// in MacCleanKit and test that instead. The mapping under test:
//   "trash_large" -> "trash-bins", "caches_large" -> "system-junk"
final class TipTargetModuleTests: XCTestCase {
    func testTipMapsToModule() {
        XCTAssertEqual(MenuTipRouting.moduleID(forTipID: "trash_large"), "trash-bins")
        XCTAssertEqual(MenuTipRouting.moduleID(forTipID: "caches_large"), "system-junk")
        XCTAssertNil(MenuTipRouting.moduleID(forTipID: "unknown"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "DeepLinkRoutingTests"` and `swift test --filter "TipTargetModuleTests"`
Expected: FAIL — `deepLinkID`, `SidebarItem(deepLinkID:)`, `MenuTipRouting` undefined.

- [ ] **Step 3: Implement**

In `SidebarView.swift`, add to `SidebarItem`:

```swift
    /// Stable slug used in `macclean://module/<id>` deep links.
    var deepLinkID: String {
        switch self {
        case .smartScan: "smart-scan"
        case .systemJunk: "system-junk"
        case .mailAttachments: "mail-attachments"
        case .trashBins: "trash-bins"
        case .malwareRemoval: "malware"
        case .privacy: "privacy"
        case .optimization: "optimization"
        case .maintenance: "maintenance"
        case .uninstaller: "uninstaller"
        case .updater: "updater"
        case .spaceLens: "space-lens"
        case .largeOldFiles: "large-old-files"
        case .duplicates: "duplicates"
        case .shredder: "shredder"
        }
    }

    init?(deepLinkID: String) {
        guard let match = Self.allCases.first(where: { $0.deepLinkID == deepLinkID }) else { return nil }
        self = match
    }
```

> If `SidebarItem` isn't already `CaseIterable`, add `CaseIterable` conformance.

In `MacCleanApp.swift`, on the top-level window content view, add:

```swift
        .onOpenURL { url in
            guard url.scheme == "macclean", url.host == "module",
                  let id = url.pathComponents.last,
                  let item = SidebarItem(deepLinkID: id) else { return }
            appState.selectedSidebarItem = item
        }
```

In `MacCleanMenu/SystemStats/TipsEngine.swift`, add a pure router (place in MacCleanKit if Tip isn't visible to tests — see test note) and extend `TipAction`:

```swift
public enum MenuTipRouting {
    /// Tip-id → sidebar module deep-link id. Keep in sync with the tip ids
    /// produced by `TipsEngine` (trash_large, caches_large).
    public static func moduleID(forTipID id: String) -> String? {
        switch id {
        case "trash_large": "trash-bins"
        case "caches_large": "system-junk"
        default: nil
        }
    }
}

public extension TipAction {
    @MainActor
    static func open(moduleID: String?) {
        guard let moduleID, let url = URL(string: "macclean://module/\(moduleID)") else {
            open()   // fallback: just foreground the app
            return
        }
        NSWorkspace.shared.open(url)
    }
}
```

In `MacCleanMenuApp.swift`, replace the tip CTA (line ~296):

```swift
                    Button { TipAction.open(moduleID: MenuTipRouting.moduleID(forTipID: tip.id)) } label: {
```

Register the scheme in the **app target's** `Info.plist` (the file the app bundle uses):

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key><string>com.macclean.deeplink</string>
    <key>CFBundleURLSchemes</key><array><string>macclean</string></array>
  </dict>
</array>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "DeepLinkRoutingTests"` and `swift test --filter "TipTargetModuleTests"` → PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MacClean/Views/Sidebar/SidebarView.swift Sources/MacClean/App/MacCleanApp.swift Sources/MacCleanMenu/SystemStats/TipsEngine.swift Sources/MacCleanMenu/MacCleanMenuApp.swift Tests/MacCleanTests/DeepLinkRoutingTests.swift Tests/MacCleanKitTests/TipTargetModuleTests.swift
git commit -m "Menu bar: deep-link tip CTAs to their module via macclean:// scheme (#35)"
```

> Manual verification (not unit-testable): run the menu bar app, click "Free Up Space" → main app opens on System Junk; click "Empty Trash" → opens on Trash Bins; the X still dismisses for 30 days.

---

### Task 6: Maintenance "Free Up RAM" — route root commands through the helper + honest failure (#36)

`purge` (`/usr/bin/purge`) needs root, so `Process` exits non-zero → `.failed` → a red `xmark.circle.fill` that looks like a tappable close button but is only a status icon. Classify root-requiring tasks, route them through the existing XPC helper, and surface the real error text so the status is no longer a mystery.

**Files:**
- Modify: `Sources/MacCleanKit/MaintenanceTask.swift` (add `requiresPrivilegedHelper`)
- Modify: `Sources/MacClean/Modules/Maintenance/MaintenanceModule.swift` (route via `XPCClient` when privileged)
- Modify: `Sources/MacClean/Views/Performance/MaintenanceView.swift` (show the error message under a failed task; keep the icon non-interactive)
- Test: `Tests/MacCleanKitTests/MaintenanceTaskPrivilegeTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MacCleanKit

final class MaintenanceTaskPrivilegeTests: XCTestCase {
    func testRootTasksAreFlaggedPrivileged() {
        XCTAssertTrue(MaintenanceTask.freeUpRAM.requiresPrivilegedHelper)
        XCTAssertTrue(MaintenanceTask.runMaintenanceScripts.requiresPrivilegedHelper)
        // Flush DNS / reindex spotlight do not need our helper.
        XCTAssertFalse(MaintenanceTask.flushDNSCache.requiresPrivilegedHelper)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "MaintenanceTaskPrivilegeTests"`
Expected: FAIL — `requiresPrivilegedHelper` undefined.

- [ ] **Step 3: Implement**

In `MaintenanceTask.swift`:

```swift
    /// True for tasks whose command needs root (purge, periodic, …).
    /// `MaintenanceExecutor` routes these through the privileged XPC
    /// helper instead of a plain `Process` (which would exit non-zero
    /// and surface a misleading red status icon — issue #36).
    public var requiresPrivilegedHelper: Bool {
        switch self {
        case .freeUpRAM, .runMaintenanceScripts, .repairDiskPermissions,
             .verifyStartupDisk, .thinTimeMachineSnapshots:
            true
        case .freeUpPurgeableSpace, .speedUpMail, .rebuildLaunchServices,
             .reindexSpotlight, .flushDNSCache:
            false
        }
    }
```

In `MaintenanceModule.swift` `execute(_:)`, route privileged tasks (use `XPCClient` from `Sources/MacClean/Services/XPCClient.swift`; confirm its method names and add a matching helper op if needed):

```swift
    public func execute(_ task: MaintenanceTask) async -> TaskResult {
        if case .speedUpMail = task { return await reindexMail() }

        if task.requiresPrivilegedHelper {
            return await runPrivileged(task)
        }
        guard let (command, args) = task.systemCommand else {
            return TaskResult(task: task, success: false, output: "",
                              error: "Task has no system command")
        }
        return await runProcess(task: task, command: command, args: args)
    }

    /// Run via the privileged helper. On any failure return a clear,
    /// user-facing message instead of a bare non-zero exit.
    private func runPrivileged(_ task: MaintenanceTask) async -> TaskResult {
        guard let (command, args) = task.systemCommand else {
            return TaskResult(task: task, success: false, output: "",
                              error: "Task has no system command")
        }
        do {
            let output = try await XPCClient.shared.runPrivilegedCommand(command, args)
            return TaskResult(task: task, success: true, output: output, error: nil)
        } catch {
            return TaskResult(task: task, success: false, output: "",
                error: "This task needs administrator access via the Mac Clean helper. \(error.localizedDescription)")
        }
    }
```

> If `XPCClient` has no generic `runPrivilegedCommand`, add an op to `Sources/MacCleanHelper/HelperOperations.swift` + the XPC protocol mirroring the existing `freeUpPurgeableSpace` op, and call that. Keep the helper's allow-list tight (only the exact maintenance executables above). **Changes to XPC helper operations require a security-conscious review** (see SECURITY.md).

In `MaintenanceView.swift`, show the failure reason and make clear the icon is status, not a button. Replace the `.failed` arm of `statusView` usage so the row renders the message:

```swift
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(message)        // hover shows the real reason; it is not a button
```

And under the task row, when failed, render the message text (small, wrapping) so users see *why* without hovering.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "MaintenanceTaskPrivilegeTests"` → PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MacCleanKit/MaintenanceTask.swift Sources/MacClean/Modules/Maintenance/MaintenanceModule.swift Sources/MacClean/Views/Performance/MaintenanceView.swift Tests/MacCleanKitTests/MaintenanceTaskPrivilegeTests.swift
git commit -m "Maintenance: run root tasks via helper, surface real errors (#36)"
```

> Manual verification: run "Free Up RAM" → succeeds (or shows a clear admin-access message); the failed-state icon is plainly a status indicator, not a dead button.

---

### Task 7: Document the malware detection list (#39)

Docs-only — no test (the skill allows this for pure documentation). Explain the curated/heuristic scope and invite contribution.

**Files:**
- Modify: `Sources/MacClean/Modules/Malware/MalwareModule.swift` (comment above `knownMalwareLocations`)
- Modify: the `MalwareSignatures` source (comment above the signature set)

- [ ] **Step 1: Add the comment**

Above `knownMalwareLocations()` in `MalwareModule.swift`:

```swift
    // NOTE ON SCOPE: Mac Clean is a community/open-source project, not a
    // commercial AV vendor. We deliberately do NOT ship a giant malware
    // database. Detection here is (1) a small curated list of well-known
    // adware/malware install locations + filename patterns, and (2) a few
    // heuristics for suspicious LaunchAgents. This catches common,
    // long-lived offenders without pretending to be a full anti-virus.
    // Contributors: PRs that expand the curated locations/signatures
    // (with a source/reference for each) are very welcome — see
    // MalwareSignatures.
```

Add an analogous comment above the signature set in `MalwareSignatures`.

- [ ] **Step 2: Build to confirm it still compiles**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/MacClean/Modules/Malware/MalwareModule.swift Sources/MacCleanKit/MalwareSignatures.swift
git commit -m "Malware: document the curated/heuristic detection scope (#39)"
```

---

### Task 8: PR 1 version bump + ship

**Files:**
- Modify: `VERSION`, `Sources/MacCleanKit/Constants.swift`

- [ ] **Step 1: Bump to 1.6.2**

Set `VERSION` to `1.6.2` and `appVersion` to `"1.6.2"`.

- [ ] **Step 2: Full local CI**

```bash
bash scripts/check-version-sync.sh && swift build && swift test
```
Expected: version sync OK; build clean; all tests pass.

- [ ] **Step 3: Commit, push, open PR**

```bash
git add VERSION Sources/MacCleanKit/Constants.swift
git commit -m "Bump 1.6.1 -> 1.6.2: wire dead buttons + menu-bar deep-links (#32 #33 #34 #35 #36 #39)"
git push -u origin fix/wire-dead-buttons
gh pr create --base main --title "Wire up dead buttons + menu-bar deep-links + malware docs (1.6.2)" \
  --body "Closes #32, #33, #34, #35, #36, #39. See docs/superpowers/plans/2026-06-01-button-audit-and-spacelens.md."
```

---

# PR 2 — Smart Scan real cleanup + SpaceLens (un-freeze + zoom-out) (→ 1.7.0)

Branch off `origin/main` (after PR 1 merges): `feat/smartscan-spacelens`.

Closes #31, #37, #38.

---

### Task 9: SpaceLens — move the tree walk off the main thread (#31)

`scanWithSizeAggregation` is a `nonisolated` synchronous walk; called inside the View's `@MainActor` `Task`, it freezes the UI. Make it actor-isolated `async` so it runs on the `FileTreeScanner` actor's executor (off main), and add progress + Cancel in the view.

**Files:**
- Modify: `Sources/MacClean/Core/Scanner/FileTreeScanner.swift` (`scanWithSizeAggregation` → actor-isolated `async`)
- Modify: `Sources/MacClean/Views/Files/SpaceLensView.swift` (await new API; add Cancel)
- Test: `Tests/MacCleanTests/FileTreeScannerAggregationTests.swift` (create or extend existing scanner tests)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit
import MacCleanTestSupport

final class FileTreeScannerAggregationTests: XCTestCase {
    func testAsyncAggregationSumsChildSizes() async throws {
        try await TestFixtures.withTempDir { dir in
            let a = dir.appending(path: "a"); try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
            try Data(count: 1000).write(to: a.appending(path: "f1.bin"))
            try Data(count: 2000).write(to: dir.appending(path: "f2.bin"))

            let scanner = FileTreeScanner()
            // New API is async + actor-isolated (runs off the main actor).
            let root = await scanner.scanWithSizeAggregation(root: dir)
            XCTAssertGreaterThanOrEqual(root.totalSize, 3000)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "FileTreeScannerAggregationTests"`
Expected: FAIL to compile — `scanWithSizeAggregation` is currently `nonisolated` synchronous, so `await` is flagged / signature mismatch once you change call sites. (If it still compiles as sync, the test documents the intended async signature for Step 3.)

- [ ] **Step 3: Implement**

In `FileTreeScanner.swift`, change the signature from:

```swift
    public nonisolated func scanWithSizeAggregation(root: URL) -> FileNode {
```

to an actor-isolated async method (drop `nonisolated`, add `async`):

```swift
    public func scanWithSizeAggregation(root: URL) async -> FileNode {
```

The body is unchanged; being actor-isolated means it executes on the scanner actor's executor (a background thread), never the main thread. Add a periodic `await Task.yield()` and an `if Task.isCancelled { break }` inside the enumeration loop so a Cancel actually stops it.

In `SpaceLensView.swift` `startScan()`, the call already uses `await scanner.scanWithSizeAggregation(root:)` — keep it, but store the `Task` so it can be cancelled and add a Cancel button in the `isScanning` branch:

```swift
    @State private var scanTask: Task<Void, Never>?
    // ...
    if isScanning {
        Spacer()
        ScanProgressRing(progress: 0.5, phase: "Scanning disk...", theme: .files)
        Button("Cancel") { scanTask?.cancel(); isScanning = false }
            .buttonStyle(.bordered).tint(.white).controlSize(.large)
        Spacer()
    }
```

and in `startScan()` wrap the work: `scanTask = Task { … existing body … }`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "FileTreeScannerAggregationTests"` → PASS
Run: `swift test` (full) → no regressions in existing scanner tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacClean/Core/Scanner/FileTreeScanner.swift Sources/MacClean/Views/Files/SpaceLensView.swift Tests/MacCleanTests/FileTreeScannerAggregationTests.swift
git commit -m "SpaceLens: run tree aggregation off the main thread + Cancel (#31)"
```

> Manual verification: scan a large folder — the window stays responsive (no beachball) and Cancel works.

---

### Task 10: SpaceLens — explicit zoom-out / up / home controls (#38)

Drilling into a folder is "zoom in"; today only the breadcrumb row gets you back. Extract navigation into a pure, testable model and add explicit **Up** and **Home** buttons.

**Files:**
- Create: `Sources/MacClean/Views/Files/SpaceLensNavigation.swift` (pure logic)
- Modify: `Sources/MacClean/Views/Files/SpaceLensView.swift` (Up/Home buttons; use the model)
- Test: `Tests/MacCleanTests/SpaceLensNavigationTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import Foundation
@testable import MacClean

final class SpaceLensNavigationTests: XCTestCase {
    let home = URL(filePath: "/Users/me")
    let caches = URL(filePath: "/Users/me/Library/Caches")
    let library = URL(filePath: "/Users/me/Library")

    func testDrillAppendsCrumb() {
        var nav = SpaceLensNavigation(root: home)
        nav.drillInto(library)
        nav.drillInto(caches)
        XCTAssertEqual(nav.current, caches)
        XCTAssertEqual(nav.breadcrumbs, [home, library, caches])
    }

    func testUpPopsOneLevel() {
        var nav = SpaceLensNavigation(root: home)
        nav.drillInto(library); nav.drillInto(caches)
        nav.up()
        XCTAssertEqual(nav.current, library)
        XCTAssertEqual(nav.breadcrumbs, [home, library])
    }

    func testUpAtRootIsNoOp() {
        var nav = SpaceLensNavigation(root: home)
        nav.up()
        XCTAssertEqual(nav.current, home)
        XCTAssertEqual(nav.breadcrumbs, [home])
    }

    func testHomeResetsToRoot() {
        var nav = SpaceLensNavigation(root: home)
        nav.drillInto(library); nav.drillInto(caches)
        nav.home()
        XCTAssertEqual(nav.current, home)
        XCTAssertEqual(nav.breadcrumbs, [home])
    }

    func testNavigateToCrumbTruncates() {
        var nav = SpaceLensNavigation(root: home)
        nav.drillInto(library); nav.drillInto(caches)
        nav.navigate(to: library)
        XCTAssertEqual(nav.current, library)
        XCTAssertEqual(nav.breadcrumbs, [home, library])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "SpaceLensNavigationTests"`
Expected: FAIL — `SpaceLensNavigation` undefined.

- [ ] **Step 3: Implement**

`Sources/MacClean/Views/Files/SpaceLensNavigation.swift`:

```swift
import Foundation

/// Pure navigation state for SpaceLens drill-down ("zoom"). Kept free of
/// SwiftUI so the back/up/home logic is unit-testable.
struct SpaceLensNavigation: Equatable {
    private(set) var breadcrumbs: [URL]

    init(root: URL) { breadcrumbs = [root] }

    var current: URL { breadcrumbs.last ?? breadcrumbs[0] }
    var canGoUp: Bool { breadcrumbs.count > 1 }

    mutating func drillInto(_ url: URL) { breadcrumbs.append(url) }

    mutating func up() {
        if breadcrumbs.count > 1 { breadcrumbs.removeLast() }
    }

    mutating func home() {
        if let root = breadcrumbs.first { breadcrumbs = [root] }
    }

    mutating func navigate(to url: URL) {
        if let i = breadcrumbs.firstIndex(of: url) {
            breadcrumbs = Array(breadcrumbs.prefix(through: i))
        }
    }
}
```

In `SpaceLensView.swift`, replace the ad-hoc `breadcrumbs`/`currentURL` `@State` with `@State private var nav = SpaceLensNavigation(root: MCConstants.home)`, drive `startScan()` off `nav.current`, and in the breadcrumb bar add leading controls:

```swift
                Button { nav.up(); startScan() } label: { Image(systemName: "chevron.up") }
                    .disabled(!nav.canGoUp)
                Button { nav.home(); startScan() } label: { Image(systemName: "house") }
```

Cell tap → `nav.drillInto(item.node.url); startScan()`. Crumb tap → `nav.navigate(to: url); startScan()`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "SpaceLensNavigationTests"` → PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MacClean/Views/Files/SpaceLensNavigation.swift Sources/MacClean/Views/Files/SpaceLensView.swift Tests/MacCleanTests/SpaceLensNavigationTests.swift
git commit -m "SpaceLens: add Up/Home zoom-out controls (#38)"
```

---

### Task 11: Smart Scan — real cleanup flow with selection, confirm, and Trash messaging (#37)

Replace the `runCleanup()` stub. The results screen lists what was found with mark/unmark, the user confirms, items move to the Trash via `CleanActions`, and the done screen explains they're recoverable in the Trash and Trash Bins can erase them permanently. Aggregation is extracted to a pure, testable helper.

**Files:**
- Create: `Sources/MacClean/Views/SmartScan/SmartScanCleanup.swift` (pure aggregation helper)
- Modify: `Sources/MacClean/Views/SmartScan/SmartScanView.swift` (selection state, results list, confirm alert, real cleanup, done copy)
- Test: `Tests/MacCleanTests/SmartScanCleanupTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit

final class SmartScanCleanupTests: XCTestCase {
    private func item(_ path: String, _ size: UInt64) -> FileItem {
        FileItem(url: URL(filePath: path), name: (path as NSString).lastPathComponent,
                 size: size, allocatedSize: size, isDirectory: false)
    }

    func testFlattensModuleResultsAcrossCategories() {
        let modules = [
            ModuleScanResult(moduleID: "systemJunk", moduleName: "System Junk",
                categories: [ScanResult(category: .userCaches, items: [item("/c/a", 100)])],
                scanDuration: 0),
            ModuleScanResult(moduleID: "trashBins", moduleName: "Trash Bins",
                categories: [ScanResult(category: .trashBins, items: [item("/t/b", 200)])],
                scanDuration: 0),
        ]
        let flat = SmartScanCleanup.allResults(from: modules)
        XCTAssertEqual(flat.count, 2)
        XCTAssertEqual(Set(flat.map(\.category)), [.userCaches, .trashBins])
    }

    func testAutoSelectedURLsAreEveryItemFromAutoSelectCategories() {
        let modules = [
            ModuleScanResult(moduleID: "systemJunk", moduleName: "System Junk",
                categories: [ScanResult(category: .userCaches, items: [item("/c/a", 100), item("/c/b", 100)], autoSelect: true)],
                scanDuration: 0),
        ]
        let urls = SmartScanCleanup.defaultSelection(from: modules)
        XCTAssertEqual(urls, Set([URL(filePath: "/c/a"), URL(filePath: "/c/b")]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "SmartScanCleanupTests"`
Expected: FAIL — `SmartScanCleanup` undefined.

- [ ] **Step 3: Implement**

`Sources/MacClean/Views/SmartScan/SmartScanCleanup.swift`:

```swift
import Foundation
import MacCleanKit

/// Pure helpers that turn Smart Scan's per-module results into the inputs
/// `CleanActions.executeUserClean` expects. Kept SwiftUI-free for testing.
enum SmartScanCleanup {
    static func allResults(from modules: [ModuleScanResult]) -> [ScanResult] {
        modules.flatMap(\.categories).filter { !$0.items.isEmpty }
    }

    /// Pre-check every item in auto-select categories (mirrors per-module views).
    static func defaultSelection(from modules: [ModuleScanResult]) -> Set<URL> {
        var urls: Set<URL> = []
        for result in allResults(from: modules) where result.autoSelect {
            urls.formUnion(result.items.map(\.url))
        }
        return urls
    }
}
```

In `SmartScanView.swift`:

1. Add state: `@State private var selectedItems: Set<URL> = []`, `@State private var cleanResults: [ScanResult] = []`, `@State private var showCleanConfirm = false`, `@State private var cleanTask: Task<Void, Never>?`.
2. On entering `.results`, set `cleanResults = SmartScanCleanup.allResults(from: moduleResults)` and `selectedItems = SmartScanCleanup.defaultSelection(from: moduleResults)`.
3. In `resultsView`, render a `FileListView(results: cleanResults, selectedItems: $selectedItems)` so the user can mark/unmark, and change the Clean button to confirm first:

```swift
            Button("Clean") { showCleanConfirm = true }
                .buttonStyle(SuperEllipseButtonStyle(
                    gradient: ModuleTheme.smartScan.buttonGradient,
                    size: CGSize(width: 140, height: 46)))
                .disabled(selectedItems.isEmpty)
                .alert("Clean \(selectedItems.count) items?", isPresented: $showCleanConfirm) {
                    Button("Cancel", role: .cancel) { }
                    Button("Clean", role: .destructive) { runCleanup() }
                } message: {
                    Text("Selected items will be moved to the Trash so you can recover them if needed.")
                }
```

4. Replace `runCleanup()` with the real implementation:

```swift
    private func runCleanup() {
        scanState = .cleaning(progress: 0)
        cleanTask = Task {
            let result = await CleanActions.executeUserClean(
                results: cleanResults,
                selectedItems: selectedItems,
                engine: appState.cleaningEngine,
                onProgress: { p in Task { @MainActor in
                    scanState = .cleaning(progress: p.fraction)
                } }
            )
            scanState = .done(freedSize: result.freedBytes)
        }
    }
```

5. Update `doneView` copy (short, useful, points to Trash Bins for permanent erase):

```swift
            Text("Moved to the Trash")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            SizeDisplay(size: freedSize, label: "ready to reclaim").foregroundStyle(.white)
            Text("These items are in your Trash — recover anything you need. To erase them for good, open Trash Bins and empty it.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center).frame(maxWidth: 420)
```

> Note: `.trashBins` items found by Smart Scan are routed to permanent deletion by `CleanActions` already (PR #30); the "recover from Trash" copy applies to the recoverable categories, which is the common case. Keep the copy accurate and short.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "SmartScanCleanupTests"` → PASS
Run: `swift test --filter "CleanActionsTests"` → still green (the production deletion path is already covered).

- [ ] **Step 5: Commit**

```bash
git add Sources/MacClean/Views/SmartScan/SmartScanCleanup.swift Sources/MacClean/Views/SmartScan/SmartScanView.swift Tests/MacCleanTests/SmartScanCleanupTests.swift
git commit -m "Smart Scan: real cleanup with selection, confirm, Trash messaging (#37)"
```

> Manual verification: scan, uncheck a couple items, Clean → confirm → files actually move to Trash; done screen points to Trash Bins.

---

### Task 12: PR 2 version bump + ship

**Files:**
- Modify: `VERSION`, `Sources/MacCleanKit/Constants.swift`

- [ ] **Step 1: Bump to 1.7.0** — set `VERSION` to `1.7.0` and `appVersion` to `"1.7.0"`.

- [ ] **Step 2: Full local CI**

```bash
bash scripts/check-version-sync.sh && swift build && swift test
```

- [ ] **Step 3: Commit, push, open PR**

```bash
git add VERSION Sources/MacCleanKit/Constants.swift
git commit -m "Bump 1.6.2 -> 1.7.0: Smart Scan cleanup + SpaceLens (#31 #37 #38)"
git push -u origin feat/smartscan-spacelens
gh pr create --base main --title "Smart Scan real cleanup + SpaceLens un-freeze & zoom-out (1.7.0)" \
  --body "Closes #31, #37, #38. See docs/superpowers/plans/2026-06-01-button-audit-and-spacelens.md."
```

---

## Self-Review notes

- **Spec coverage:** SpaceLens freeze → Task 9 (#31). Updater → Task 2 (#32). Uninstaller Reset → Task 3 (#33). Launch-agent toggle → Task 4 (#34). Menu-bar deep-link → Task 5 (#35). Free Up RAM + dead-looking X → Task 6 (#36). Smart Scan stub → Task 11 (#37). SpaceLens zoom-out → Task 10 (#38). Malware docs → Task 7 (#39). Static guard catches the whole class → Task 1.
- **Open risks to verify during execution (don't assume):**
  1. `AppInfo` initializer signature (Task 2/4 test literals) — match the real one in `Models/AppInfo.swift`.
  2. `SidebarItem` may need `CaseIterable` (Task 5).
  3. `XPCClient` API + whether a generic `runPrivilegedCommand` exists or a new helper op is required (Task 6) — **security-sensitive; warrants review**.
  4. Whether `MenuTipRouting`/`Tip` should live in MacCleanKit so both targets + tests see them (Task 5).
  5. `FileNode.totalSize` is populated by aggregation (Task 9 assertion).
- **Type consistency:** `SpaceLensNavigation` methods (`drillInto/up/home/navigate/current/canGoUp`) are used identically in test and view. `SmartScanCleanup.allResults/defaultSelection` match between test and view.
