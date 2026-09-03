# App permissions overview (#49)

Date: 2026-08-12
Status: Design (reframed 2026-08-19 after review on PR #133)

## Problem

macOS remembers which apps may use Camera, Microphone, Full Disk Access, Screen
Recording, and Automation. Users currently have to hunt those lists inside
System Settings. Issue #49 asked for a manager that could review/revoke them.

There is **no supported Apple API** to list other apps' TCC grants, and a
third-party app **cannot revoke** a grant. The supported change path is the
Privacy & Security pane.

## Goal

A Protection sidebar module **Permissions** (read-only overview):

1. Primary view: **by-app aggregation** — which app holds which grants, at a
   glance. System Settings lists by category; it does not do this well.
2. Every action is **Open in System Settings** for that category. Copy never
   says revoke/turn off/manage.
3. Best-effort list when user/system `TCC.db` is readable (typically Full Disk
   Access). If unreadable, keep category deep-links so the module is not a dead
   end, and explain that the by-app list needs FDA.

Not a `ScanModule`. Not in Smart Scan.

## Non-goals

- Do not write `TCC.db`. Do not disable SIP. Do not add a privileged helper.
- Do not call `tccutil reset`.
- Do not claim we can toggle a grant inside Mac Sai.
- Accessibility, Input Monitoring, Files & Folders, Photos, Contacts — follow-up.
- No `Localizable.strings` migration; `L10n.tr` only.

## Approach

Kit: `PrivacyPermission`, `TCCAccessParser`, `AppPermissionOverview.apps(from:)`
groups grants by client. MacClean: injected `AppPermissionsClient` (GRDB
read-only). UI: app sections with per-grant "Open in System Settings", plus a
footer of category deep-links.

Sidebar after Saved Wi-Fi (so ⌘7 stays Wi-Fi). Slug `app-permissions`. Title
`权限总览` / Permissions / Обзор разрешений.

## Testing

- Kit: URL per service; parser fixtures; by-app grouping (sort, path vs bundle).
- Client: injected reader; view source must not contain revoke wording.
- Deep link `app-permissions`. ⌘8 is Permissions; ⌘7 stays Saved Wi-Fi.
- Never open the live `TCC.db` in unit tests.
