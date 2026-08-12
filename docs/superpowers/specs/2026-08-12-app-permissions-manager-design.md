# App permissions manager (#49)

Date: 2026-08-12
Status: Design (ready for implementation after user approval)

## Problem

macOS remembers which apps may use Camera, Microphone, Full Disk Access, Screen
Recording, and Automation. Users currently have to hunt those lists inside
System Settings. Issue #49 asks for CleanMyMac-style parity: see which apps hold
which grants, then review/revoke them.

There is **no supported Apple API** to list other apps' TCC grants. Apple DTS
treats `TCC.db` location and schema as an implementation detail
([forums/thread/740055](https://developer.apple.com/forums/thread/740055)).
WWDC26 Privacy Q&A states direct `TCC.db` access **will be restricted**
([forums/thread/833806](https://developer.apple.com/forums/thread/833806));
framework APIs only report **this** app's own permission.

The supported revoke path is the Privacy & Security pane. `tccutil reset`
([QA1906](https://developer.apple.com/library/archive/qa/qa1906/_index.html))
resets a whole service for **every** app unless a bundle id is passed; even
then it is a blunt reset, not a Settings toggle. Iliya's issue already forbids
in-app revoke: *“revoke by deep-linking the relevant Privacy & Security pane”*.

`PermissionManager` today only opens Full Disk Access
(`Privacy_AllFiles`). Privacy module cleans browser traces — it is not a TCC
manager. Current state: not implemented.

## Goal

A Protection sidebar module **App Permissions**:

1. Always show the five issue categories, each with **Open in System Settings**.
2. Best-effort list of granted apps when user/system `TCC.db` is readable
   (typically requires Full Disk Access for Mac Sai).
3. If the DB is unreadable (no FDA, sandbox, or macOS 26 lock-down), keep the
   five category cards and show the existing FDA empty-state CTA. The module
   must never be a dead end.

Not a `ScanModule`. Not in Smart Scan.

## Non-goals

- Do not write `TCC.db`. Do not disable SIP. Do not add a privileged helper.
- Do not call `tccutil reset` (too blunt; official docs reset *all* apps for a
  service).
- Do not claim we can toggle a grant inside Mac Sai.
- Accessibility, Input Monitoring, Files & Folders, Photos, Contacts — follow-up.
- No Smart Scan / `registerModules`.
- No `Localizable.strings` migration; `L10n.tr` only.
- No telemetry.

## Approach (recommended: hybrid hub)

### Kit (pure)

`PrivacyPermission` — the five services, TCC service id(s), Settings URL
fragment. URL builder returns the same scheme already used in
`PermissionManager`:

`x-apple.systempreferences:com.apple.preference.security?<fragment>`

Fragments: `Privacy_Camera`, `Privacy_Microphone`, `Privacy_AllFiles`,
`Privacy_ScreenCapture`, `Privacy_Automation`.

`TCCAccessRow` + `TCCAccessParser.grants(from:)` — map sqlite rows to
`AppPermissionGrant`. Keep `auth_value` 2 (allowed) and 3 (limited); drop 0
(denied) and unknown services. Automation keeps `indirect_object_identifier`
(controller → target). `client_type` 0 = bundle id, 1 = path.

### MacClean (I/O)

`AppPermissionsClient` with injected `readRows: (URL) throws -> [TCCAccessRow]`
and `openURL: (URL) -> Void`. Live reader: GRDB read-only on

- `~/Library/Application Support/com.apple.TCC/TCC.db` (camera, mic, automation)
- `/Library/Application Support/com.apple.TCC/TCC.db` (FDA, screen recording)

EPERM/EACCES → `needsFullDiskAccess`. Other open/schema failures →
`listingUnavailable`. Merge rows; never sudo.

Display name/icon via injected `NSWorkspace` lookup (bundle id or path). Missing
app → show the client string, subtitle “App not found”.

### UI

`AppPermissionsView` under Protection, patterned on `WiFiNetworksView` (not
`ModuleContainerView`). Header + Refresh. Five sections. Each section: count,
Open Settings, granted-app rows (or “None listed”). Banner when listing failed.
⌘R reloads. Deep link `macclean://module/app-permissions`.

Sidebar: after Privacy, before Saved Wi-Fi. Icon `lock.shield`. Title
`应用权限` / App Permissions / Разрешения приложений.

⌘1–⌘9: inserting after Privacy shifts digits 7–9 (⌘7 becomes App Permissions).
Document in the PR. Branch from upstream `main`, not from #132, so the PRs stay
independent; merge order may need a one-line sidebar conflict resolve.

## Testing

- Kit: URL per service; parser fixtures (allowed/denied/limited, unknown
  service, path client, automation target, empty).
- Client: injected reader — EPERM maps to FDA; rows map to grants; `openURL`
  called with the Kit URL (never live System Settings in CI).
- Deep link round-trip `app-permissions`.
- Keyboard digit 7 after insert (update `KeyboardShortcutRoutingTests`).
- Never open the live `TCC.db` in unit tests.

## Sources

- Issue: https://github.com/iliyami/MacSai/issues/49
- QA1906 `tccutil reset`: https://developer.apple.com/library/archive/qa/qa1906/_index.html
- DTS: TCC.db is not public API: https://developer.apple.com/forums/thread/740055
- WWDC26: TCC.db access restricted: https://developer.apple.com/forums/thread/833806
- Existing opener: `Sources/MacClean/Services/PermissionManager.swift`
