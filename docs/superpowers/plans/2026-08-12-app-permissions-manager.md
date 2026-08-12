# App Permissions Manager (#49) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Protection module that lists the five TCC categories from issue #49, shows granted apps when `TCC.db` is readable, and always deep-links revoke to System Settings.

**Architecture:** Pure mapping/URL/parser in MacCleanKit. GRDB + `NSWorkspace` injected in MacClean. SwiftUI list like Saved Wi-Fi, not a ScanModule.

**Tech Stack:** Swift 6, SwiftUI, XCTest, GRDB (read-only), `x-apple.systempreferences` URLs already used by `PermissionManager`.

## Global Constraints

- One feature per PR (CONTRIBUTING). Branch from upstream `main`, not from `feat/forget-wifi-networks`.
- Business logic in MacCleanKit; I/O in MacClean with injected closures.
- Never write `TCC.db`. Never call `tccutil`. Never sudo / osascript for this module.
- Unit tests must not open the live TCC databases.
- `L10n.tr(zh, en, ru)` for new copy. Sidebar title also in `englishFallbacks` / `russianFallbacks`.
- No telemetry / network.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for `swift test`.
- Commit author is the user; do not leave a Cursor co-author trailer.

## Files

| File | Role |
|---|---|
| `Sources/MacCleanKit/AppPermissions.swift` | `PrivacyPermission`, `TCCAccessRow`, `AppPermissionGrant`, parser, Settings URL |
| `Tests/MacCleanKitTests/AppPermissionsTests.swift` | Parser + URL fixtures |
| `Sources/MacClean/Modules/AppPermissions/AppPermissionsClient.swift` | GRDB read-only + open URL |
| `Tests/MacCleanTests/AppPermissionsClientTests.swift` | Injected I/O |
| `Sources/MacClean/Views/Protection/AppPermissionsView.swift` | UI |
| `Sources/MacClean/Views/Sidebar/SidebarView.swift` | New item after Privacy |
| `Sources/MacClean/App/ContentView.swift` | Route |
| `Sources/MacCleanKit/Localization.swift` | Sidebar fallbacks |
| `Tests/MacCleanTests/DeepLinkRoutingTests.swift` | `app-permissions` |
| `Tests/MacCleanTests/KeyboardShortcutRoutingTests.swift` | ⌘7 |

---

### Task 1: Kit model, URLs, parser

**Files:**
- Create: `Sources/MacCleanKit/AppPermissions.swift`
- Test: `Tests/MacCleanKitTests/AppPermissionsTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: types below

```swift
public enum PrivacyPermission: String, CaseIterable, Sendable, Identifiable {
    case camera, microphone, fullDiskAccess, screenRecording, automation
    public var id: String { rawValue }
    public var tccServiceIDs: Set<String> { /* see implementation */ }
    public var settingsFragment: String { /* Privacy_Camera, … */ }
}

public enum AppPermissionsSettings {
    public static let schemePrefix = "x-apple.systempreferences:com.apple.preference.security?"
    public static func url(for permission: PrivacyPermission) -> URL
}

public struct TCCAccessRow: Equatable, Sendable {
    public var service: String
    public var client: String
    public var clientType: Int
    public var authValue: Int
    public var indirectObjectIdentifier: String?
}

public struct AppPermissionGrant: Equatable, Hashable, Sendable, Identifiable {
    public var id: String { "\(permission.rawValue)|\(client)|\(indirectObjectIdentifier ?? "")" }
    public let permission: PrivacyPermission
    public let client: String
    public let clientIsPath: Bool
    public let isLimited: Bool
    public let indirectObjectIdentifier: String?
}

public enum TCCAccessParser {
    public static func grants(from rows: [TCCAccessRow]) -> [AppPermissionGrant]
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MacCleanKit

final class AppPermissionsTests: XCTestCase {

    func testSettingsURLsMatchPermissionManagerScheme() {
        XCTAssertEqual(
            AppPermissionsSettings.url(for: .fullDiskAccess).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )
        XCTAssertEqual(
            AppPermissionsSettings.url(for: .camera).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        )
        XCTAssertEqual(
            AppPermissionsSettings.url(for: .microphone).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
        XCTAssertEqual(
            AppPermissionsSettings.url(for: .screenRecording).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
        XCTAssertEqual(
            AppPermissionsSettings.url(for: .automation).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )
    }

    func testParserKeepsAllowedAndLimitedDropsDeniedAndUnknown() {
        let rows = [
            TCCAccessRow(service: "kTCCServiceCamera", client: "com.foo.cam", clientType: 0, authValue: 2, indirectObjectIdentifier: nil),
            TCCAccessRow(service: "kTCCServiceCamera", client: "com.foo.denied", clientType: 0, authValue: 0, indirectObjectIdentifier: nil),
            TCCAccessRow(service: "kTCCServiceMicrophone", client: "com.foo.limited", clientType: 0, authValue: 3, indirectObjectIdentifier: nil),
            TCCAccessRow(service: "kTCCServiceBogus", client: "com.foo.x", clientType: 0, authValue: 2, indirectObjectIdentifier: nil),
        ]
        let grants = TCCAccessParser.grants(from: rows)
        XCTAssertEqual(grants.map(\.client), ["com.foo.cam", "com.foo.limited"])
        XCTAssertEqual(grants[0].permission, .camera)
        XCTAssertFalse(grants[0].isLimited)
        XCTAssertEqual(grants[1].permission, .microphone)
        XCTAssertTrue(grants[1].isLimited)
        XCTAssertFalse(grants[0].clientIsPath)
    }

    func testParserPathClientAndAutomationTarget() {
        let rows = [
            TCCAccessRow(service: "kTCCServiceSystemPolicyAllFiles", client: "/usr/bin/rsync", clientType: 1, authValue: 2, indirectObjectIdentifier: nil),
            TCCAccessRow(service: "kTCCServiceAppleEvents", client: "com.foo.script", clientType: 0, authValue: 2, indirectObjectIdentifier: "com.apple.finder"),
        ]
        let grants = TCCAccessParser.grants(from: rows)
        XCTAssertEqual(grants.count, 2)
        XCTAssertEqual(grants[0].permission, .fullDiskAccess)
        XCTAssertTrue(grants[0].clientIsPath)
        XCTAssertEqual(grants[1].permission, .automation)
        XCTAssertEqual(grants[1].indirectObjectIdentifier, "com.apple.finder")
    }

    func testParserTreatsDashIndirectObjectAsNone() {
        let row = TCCAccessRow(service: "kTCCServiceCamera", client: "com.foo", clientType: 0, authValue: 2, indirectObjectIdentifier: "UNUSED")
        // Camera has no target; parser must still keep the grant.
        XCTAssertEqual(TCCAccessParser.grants(from: [row]).count, 1)
    }

    func testParserEmpty() {
        XCTAssertTrue(TCCAccessParser.grants(from: []).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppPermissionsTests`
Expected: FAIL — `AppPermissions` types not found.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/MacCleanKit/AppPermissions.swift`:

```swift
import Foundation

public enum PrivacyPermission: String, CaseIterable, Sendable, Identifiable {
    case camera
    case microphone
    case fullDiskAccess
    case screenRecording
    case automation

    public var id: String { rawValue }

    public var tccServiceIDs: Set<String> {
        switch self {
        case .camera: ["kTCCServiceCamera"]
        case .microphone: ["kTCCServiceMicrophone"]
        case .fullDiskAccess: ["kTCCServiceSystemPolicyAllFiles"]
        case .screenRecording: ["kTCCServiceScreenCapture"]
        case .automation: ["kTCCServiceAppleEvents"]
        }
    }

    public var settingsFragment: String {
        switch self {
        case .camera: "Privacy_Camera"
        case .microphone: "Privacy_Microphone"
        case .fullDiskAccess: "Privacy_AllFiles"
        case .screenRecording: "Privacy_ScreenCapture"
        case .automation: "Privacy_Automation"
        }
    }

    public static func matching(service: String) -> PrivacyPermission? {
        allCases.first { $0.tccServiceIDs.contains(service) }
    }
}

public enum AppPermissionsSettings {
    public static let schemePrefix = "x-apple.systempreferences:com.apple.preference.security?"

    public static func url(for permission: PrivacyPermission) -> URL {
        URL(string: schemePrefix + permission.settingsFragment)!
    }
}

public struct TCCAccessRow: Equatable, Sendable {
    public var service: String
    public var client: String
    public var clientType: Int
    public var authValue: Int
    public var indirectObjectIdentifier: String?

    public init(service: String, client: String, clientType: Int, authValue: Int, indirectObjectIdentifier: String?) {
        self.service = service
        self.client = client
        self.clientType = clientType
        self.authValue = authValue
        self.indirectObjectIdentifier = indirectObjectIdentifier
    }
}

public struct AppPermissionGrant: Equatable, Hashable, Sendable, Identifiable {
    public var id: String {
        "\(permission.rawValue)|\(client)|\(indirectObjectIdentifier ?? "")"
    }
    public let permission: PrivacyPermission
    public let client: String
    public let clientIsPath: Bool
    public let isLimited: Bool
    public let indirectObjectIdentifier: String?

    public init(
        permission: PrivacyPermission,
        client: String,
        clientIsPath: Bool,
        isLimited: Bool,
        indirectObjectIdentifier: String?
    ) {
        self.permission = permission
        self.client = client
        self.clientIsPath = clientIsPath
        self.isLimited = isLimited
        self.indirectObjectIdentifier = indirectObjectIdentifier
    }
}

public enum TCCAccessParser {
    /// `auth_value`: 0 denied, 2 allowed, 3 limited (Big Sur+ schema).
    public static func grants(from rows: [TCCAccessRow]) -> [AppPermissionGrant] {
        var seen: Set<String> = []
        var result: [AppPermissionGrant] = []
        for row in rows {
            guard let permission = PrivacyPermission.matching(service: row.service) else { continue }
            guard row.authValue == 2 || row.authValue == 3 else { continue }
            let client = row.client.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !client.isEmpty else { continue }
            let target = normalizedIndirect(row.indirectObjectIdentifier, permission: permission)
            let grant = AppPermissionGrant(
                permission: permission,
                client: client,
                clientIsPath: row.clientType == 1,
                isLimited: row.authValue == 3,
                indirectObjectIdentifier: target
            )
            if seen.insert(grant.id).inserted {
                result.append(grant)
            }
        }
        return result
    }

    private static func normalizedIndirect(_ raw: String?, permission: PrivacyPermission) -> String? {
        guard permission == .automation else { return nil }
        guard let raw, !raw.isEmpty, raw != "UNUSED", raw != "NONE" else { return nil }
        return raw
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppPermissionsTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MacCleanKit/AppPermissions.swift Tests/MacCleanKitTests/AppPermissionsTests.swift
git commit -m "$(cat <<'EOF'
Fix #49: add TCC permission parser and Settings URL builder

Map camera/mic/FDA/screen/automation rows in Kit so listing stays testable without opening the live TCC database.
EOF
)"
```

---

### Task 2: MacClean client (injected GRDB / openURL)

**Files:**
- Create: `Sources/MacClean/Modules/AppPermissions/AppPermissionsClient.swift`
- Test: `Tests/MacCleanTests/AppPermissionsClientTests.swift`

**Interfaces:**
- Consumes: `TCCAccessParser`, `AppPermissionsSettings`, `PrivacyPermission`
- Produces: `AppPermissionsClient.load()` / `openSettings(for:)`

User DB path: `NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"`
System DB path: `"/Library/Application Support/com.apple.TCC/TCC.db"`

SQL (bound, not concatenated user input):

```sql
SELECT service, client, client_type, auth_value, indirect_object_identifier
FROM access
```

If `indirect_object_identifier` is missing, retry without that column and pass `nil`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MacClean
import MacCleanKit

final class AppPermissionsClientTests: XCTestCase {

    func testLoadMergesRowsFromBothDatabases() async {
        let user = [
            TCCAccessRow(service: "kTCCServiceCamera", client: "com.foo.cam", clientType: 0, authValue: 2, indirectObjectIdentifier: nil),
        ]
        let system = [
            TCCAccessRow(service: "kTCCServiceSystemPolicyAllFiles", client: "com.foo.fda", clientType: 0, authValue: 2, indirectObjectIdentifier: nil),
        ]
        let client = AppPermissionsClient(
            userDatabaseURL: URL(filePath: "/tmp/user-tcc.db"),
            systemDatabaseURL: URL(filePath: "/tmp/system-tcc.db"),
            readRows: { url in
                if url.path.hasSuffix("user-tcc.db") { return user }
                if url.path.hasSuffix("system-tcc.db") { return system }
                return []
            },
            openURL: { _ in }
        )
        let snapshot = await client.load()
        XCTAssertEqual(snapshot.listing, .loaded)
        XCTAssertEqual(Set(snapshot.grants.map(\.client)), ["com.foo.cam", "com.foo.fda"])
    }

    func testLoadMapsPermissionDeniedToNeedsFullDiskAccess() async {
        struct Denied: Error {}
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM), userInfo: nil)
        let client = AppPermissionsClient(
            userDatabaseURL: URL(filePath: "/tmp/user-tcc.db"),
            systemDatabaseURL: URL(filePath: "/tmp/system-tcc.db"),
            readRows: { _ in throw posix },
            openURL: { _ in }
        )
        let snapshot = await client.load()
        XCTAssertEqual(snapshot.listing, .needsFullDiskAccess)
        XCTAssertTrue(snapshot.grants.isEmpty)
    }

    func testLoadMapsOtherErrorsToListingUnavailable() async {
        struct Boom: Error {}
        let client = AppPermissionsClient(
            userDatabaseURL: URL(filePath: "/tmp/user-tcc.db"),
            systemDatabaseURL: URL(filePath: "/tmp/system-tcc.db"),
            readRows: { _ in throw Boom() },
            openURL: { _ in }
        )
        let snapshot = await client.load()
        XCTAssertEqual(snapshot.listing, .unavailable)
        XCTAssertTrue(snapshot.grants.isEmpty)
    }

    func testOpenSettingsUsesKitURL() async {
        var opened: URL?
        let client = AppPermissionsClient(
            userDatabaseURL: URL(filePath: "/tmp/u"),
            systemDatabaseURL: URL(filePath: "/tmp/s"),
            readRows: { _ in [] },
            openURL: { opened = $0 }
        )
        client.openSettings(for: .camera)
        XCTAssertEqual(opened, AppPermissionsSettings.url(for: .camera))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppPermissionsClientTests`
Expected: FAIL — `AppPermissionsClient` not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/MacClean/Modules/AppPermissions/AppPermissionsClient.swift`:

```swift
import Foundation
import GRDB
import MacCleanKit

enum AppPermissionsListing: Equatable, Sendable {
    case loaded
    case needsFullDiskAccess
    case unavailable
}

struct AppPermissionsSnapshot: Equatable, Sendable {
    var grants: [AppPermissionGrant]
    var listing: AppPermissionsListing
}

struct AppPermissionsClient: Sendable {
    var userDatabaseURL: URL
    var systemDatabaseURL: URL
    var readRows: @Sendable (URL) throws -> [TCCAccessRow]
    var openURL: @Sendable (URL) -> Void

    static func live() -> AppPermissionsClient {
        let home = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
        return AppPermissionsClient(
            userDatabaseURL: home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db"),
            systemDatabaseURL: URL(filePath: "/Library/Application Support/com.apple.TCC/TCC.db"),
            readRows: { url in try Self.readAccessRows(at: url) },
            openURL: { NSWorkspace.shared.open($0) }
        )
    }

    func load() async -> AppPermissionsSnapshot {
        var rows: [TCCAccessRow] = []
        var sawDenied = false
        var sawOther = false
        for url in [userDatabaseURL, systemDatabaseURL] {
            do {
                rows.append(contentsOf: try readRows(url))
            } catch {
                if Self.isPermissionDenied(error) { sawDenied = true }
                else { sawOther = true }
            }
        }
        let grants = TCCAccessParser.grants(from: rows)
        if !grants.isEmpty || (!sawDenied && !sawOther) {
            return AppPermissionsSnapshot(grants: grants, listing: .loaded)
        }
        if sawDenied { return AppPermissionsSnapshot(grants: [], listing: .needsFullDiskAccess) }
        return AppPermissionsSnapshot(grants: [], listing: .unavailable)
    }

    func openSettings(for permission: PrivacyPermission) {
        openURL(AppPermissionsSettings.url(for: permission))
    }

    func openFullDiskAccessSettings() {
        openSettings(for: .fullDiskAccess)
    }

    private static func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EPERM) || ns.code == Int(EACCES) {
            return true
        }
        if let posix = error as? POSIXError, posix.code == .EPERM || posix.code == .EACCES {
            return true
        }
        return false
    }

    private static func readAccessRows(at url: URL) throws -> [TCCAccessRow] {
        var config = Configuration()
        config.readonly = true
        let db = try DatabaseQueue(path: url.path, configuration: config)
        return try db.read { db in
            let sqlWithIndirect = """
                SELECT service, client, client_type, auth_value, indirect_object_identifier
                FROM access
                """
            do {
                return try Row.fetchAll(db, sql: sqlWithIndirect).map { row in
                    TCCAccessRow(
                        service: row["service"] ?? "",
                        client: row["client"] ?? "",
                        clientType: row["client_type"] ?? 0,
                        authValue: row["auth_value"] ?? 0,
                        indirectObjectIdentifier: row["indirect_object_identifier"]
                    )
                }
            } catch {
                let sql = "SELECT service, client, client_type, auth_value FROM access"
                return try Row.fetchAll(db, sql: sql).map { row in
                    TCCAccessRow(
                        service: row["service"] ?? "",
                        client: row["client"] ?? "",
                        clientType: row["client_type"] ?? 0,
                        authValue: row["auth_value"] ?? 0,
                        indirectObjectIdentifier: nil
                    )
                }
            }
        }
    }
}
```

If `load()` currently returns `.needsFullDiskAccess` when **both** DBs fail with EPERM even though that is correct — keep it. If **one** DB is readable, listing is `.loaded` with whatever grants we got (user DB often readable for camera/mic even when system DB is not).

Adjust the merge rule if tests require: any successful read → `.loaded`; only if **every** read failed with EPERM → `.needsFullDiskAccess`; only other errors → `.unavailable`. Update Task 2 tests if the first test's `readRows` never throws — both succeed → `.loaded`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppPermissionsClientTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MacClean/Modules/AppPermissions/AppPermissionsClient.swift Tests/MacCleanTests/AppPermissionsClientTests.swift
git commit -m "$(cat <<'EOF'
Fix #49: read TCC grants through an injected client

List camera/mic from the user DB and FDA/screen from the system DB without writing either file. Permission errors become the Full Disk Access empty state.
EOF
)"
```

---

### Task 3: Sidebar, deep link, keyboard, view

**Files:**
- Modify: `Sources/MacClean/Views/Sidebar/SidebarView.swift` — insert `case appPermissions = "应用权限"` immediately after `.privacy`
- Modify: `Sources/MacClean/App/ContentView.swift` — `case .appPermissions: AppPermissionsView()`
- Modify: `Sources/MacCleanKit/Localization.swift` — english/russian fallbacks for `应用权限`
- Modify: `Tests/MacCleanTests/DeepLinkRoutingTests.swift`
- Modify: `Tests/MacCleanTests/KeyboardShortcutRoutingTests.swift` — digit 7 is `.appPermissions` when this branch has no Wi-Fi item; if Wi-Fi is already on `main`, digit 7 is App Permissions and 8 is Wi-Fi
- Create: `Sources/MacClean/Views/Protection/AppPermissionsView.swift`

**Interfaces:**
- Consumes: `AppPermissionsClient.live()`, `PrivacyPermission.allCases`, snapshot grants
- Produces: sidebar slug `app-permissions`

- [ ] **Step 1: Write the failing routing tests**

In `DeepLinkRoutingTests.testDeepLinkIDRoundTrips` add:

```swift
XCTAssertEqual(SidebarItem.appPermissions.deepLinkID, "app-permissions")
XCTAssertEqual(SidebarItem(deepLinkID: "app-permissions"), .appPermissions)
```

In `KeyboardShortcutRoutingTests.testShortcutDigitsMapFirstNineModulesExcludingSettings` replace the Wi-Fi-only assertion if this branch is from `main` without #50:

```swift
XCTAssertEqual(SidebarItem.item(forShortcutDigit: 7), .appPermissions)
```

If `feat/forget-wifi-networks` has already landed on the base, keep Wi-Fi and assert:

```swift
XCTAssertEqual(SidebarItem.item(forShortcutDigit: 7), .appPermissions)
XCTAssertEqual(SidebarItem.item(forShortcutDigit: 8), .wifiNetworks)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DeepLinkRoutingTests --filter KeyboardShortcutRoutingTests`
Expected: FAIL — no `appPermissions` case.

- [ ] **Step 3: Wire sidebar + view**

`SidebarItem` additions (mirror `.wifiNetworks`):

- `deepLinkID`: `"app-permissions"`
- `icon`: `"lock.shield"`
- `theme` / `section`: `.protection`

`AppPermissionsView` (same chrome as `WiFiNetworksView`):

- Title `L10n.tr("应用权限", "App Permissions", "Разрешения приложений")`
- Subtitle: listing is best-effort; revoke happens in System Settings; FDA may be required to see the app list.
- Refresh button; `respondsToModuleShortcuts(onScan: { Task { await reload() } }, canScan: !isLoading)`
- If `listing == .needsFullDiskAccess`: lock banner + `Open Settings` calling `client.openFullDiskAccessSettings()` (reuse copy from `ModuleContainerView.permissionDeniedView`)
- If `listing == .unavailable`: short message that macOS blocked the database; category Open buttons still work
- `ForEach(PrivacyPermission.allCases)` sections: header with localized name, grant count, `Open Settings` → `client.openSettings(for:)`
- Rows: display `client` (bundle id or path); if automation target present, `"\(client) → \(target)"`; limited badge
- Empty section: `L10n.tr("未列出任何应用", "No apps listed", "Приложения не показаны")`

Localized permission names:

| case | zh | en | ru |
|---|---|---|---|
| camera | 相机 | Camera | Камера |
| microphone | 麦克风 | Microphone | Микрофон |
| fullDiskAccess | 完全磁盘访问权限 | Full Disk Access | Полный доступ к диску |
| screenRecording | 屏幕录制 | Screen Recording | Запись экрана |
| automation | 自动化 | Automation | Автоматизация |

Do not resolve icons in tests. Live view may call `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` for a display name; keep that inside the view or a tiny helper, not the Kit parser.

- [ ] **Step 4: Run tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DeepLinkRoutingTests --filter KeyboardShortcutRoutingTests --filter AppPermissions`
Expected: PASS

- [ ] **Step 5: Full suite + commit**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: 0 failures.

```bash
git add Sources/MacClean/Views/Sidebar/SidebarView.swift \
  Sources/MacClean/App/ContentView.swift \
  Sources/MacClean/Views/Protection/AppPermissionsView.swift \
  Sources/MacCleanKit/Localization.swift \
  Tests/MacCleanTests/DeepLinkRoutingTests.swift \
  Tests/MacCleanTests/KeyboardShortcutRoutingTests.swift
git commit -m "$(cat <<'EOF'
Fix #49: add App Permissions module under Protection

Show the five privacy categories and deep-link each one to System Settings. List granted apps when TCC is readable; otherwise keep the Open Settings path and the Full Disk Access prompt.
EOF
)"
```

---

### Task 4: Verification and PR

- [ ] **Step 1: Spec coverage check**

Confirm the PR includes: five categories, Settings URLs matching `PermissionManager` for FDA, no `tccutil`, no TCC writes, not a ScanModule, deep link, ⌘R, FDA empty state, parser tests with denied/unknown/automation.

- [ ] **Step 2: Manual check (running app)**

- Protection → App Permissions → five sections visible without FDA.
- Each Open Settings lands on the matching Privacy pane (or Privacy & Security if the fragment is ignored on that OS).
- With FDA granted to Mac Sai: camera/mic (and FDA/screen if the system DB is readable) show real bundle ids.
- ⌘R reloads. `macclean://module/app-permissions` selects the module.

- [ ] **Step 3: Open PR** (`gh pr create --repo iliyami/MacSai`) using CONTRIBUTING sections Summary / Changes / Test Plan / Checklist. `Fixes #49`. No Cursor mention. Note the ⌘7–⌘9 shift.

---

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| macOS 26 blocks `TCC.db` even with FDA | No per-app list | Category hub + Settings links still ship |
| Settings URL fragments drift | Opens wrong pane | Same scheme as existing `PermissionManager`; FDA URL already in production |
| Schema without `auth_value` | Read fails | Platform is macOS 14+; fallback SQL without `indirect_object_identifier` only |
| Merge conflict with #132 (Wi-Fi) | Sidebar order | Independent PR from `main`; insert App Permissions after Privacy |

## Checkpoint: Complete

- [ ] Kit tests pass without touching live TCC
- [ ] Client tests never call `NSWorkspace` / GRDB in the injected path
- [ ] `swift test` 0 failures
- [ ] PR focused on #49 only
