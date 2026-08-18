# Manage extensions, plug-ins, and preference panes (#53)

Date: 2026-08-13
Status: Design (approved — hybrid)

## Problem

Issue #53 asks Mac Sai to list third-party Safari/app extensions, Internet
plug-ins, and preference panes, then enable, disable, or remove them. Those
three objects do not share one lifecycle, and Apple will not let a third-party
app flip Safari extension elections.

## Goal

An Applications sidebar module **Extensions** that:

1. Lists third-party preference panes, Internet Plug-Ins, and Safari-family
   app extensions.
2. Moves **user-domain** panes / plug-ins / legacy Safari extension packages
   to the Trash through `SafetyGuard` + `CleaningEngine`.
3. Reveals **computer-domain** (`/Library/...`) panes and plug-ins in Finder
   (no admin `osascript` in v1).
4. For Safari `.appex` bundles nested in a host `.app`, offers **Open Safari
   Settings** and **Show Host App** only.

## Non-goals

- No in-app Safari enable/disable. `pluginkit -e` is a debug/dev switch;
  `SFSafariApplication.showPreferencesForExtension` only works inside the host
  app. Document this in the UI.
- Never delete an `.appex` (or anything) under `.app/Contents/` — that breaks
  codesign of the host app.
- No admin promotion for `/Library/PreferencePanes` or `/Library/Internet
  Plug-Ins`.
- Not a `ScanModule`. Not part of Smart Scan.
- No `Localizable.strings` migration; `L10n.tr` only.
- Do not put `password`, `secret`, `api_key`, or `token` in `Sources/` (CI grep).

## Three kinds of object

| Kind | Typical location | Remove in v1 |
|---|---|---|
| Preference pane (`.prefPane`) | `~/Library/PreferencePanes`, `/Library/PreferencePanes` | User-domain → Trash. Computer-domain → Reveal in Finder. |
| Internet Plug-In (`.plugin`, `.webplugin`) | `~/Library/Internet Plug-Ins`, `/Library/Internet Plug-Ins` | Same as panes. Folders are often empty (NPAPI is dead); still ship the section. |
| Safari / app extension (`.appex`) | `Host.app/Contents/PlugIns/` | List only. Open Safari Settings / Show Host App. |
| Legacy Safari package | `~/Library/Safari/Extensions` | User-domain → Trash (allowlisted). |

Third-party only: skip `com.apple.*`, `/System`, `/Library/Apple`.

## Removal policy (defense in depth)

Trash is allowed only when **all** of these hold:

- Path is under one of:
  - `~/Library/PreferencePanes`
  - `~/Library/Internet Plug-Ins`
  - `~/Library/Safari/Extensions`
- Resolved path is not under `/System`, `/usr`, `/bin`, `/sbin`, `/Library/Apple`.
- Path does **not** contain `.app/Contents/` (refused **before** `SafetyGuard`).
- Bundle ID does not start with `com.apple.`.

Any other path is `revealInFinder` (computer-domain panes/plug-ins) or `none`
(Safari `.appex`, Apple, unknown).

## Listing Safari extensions

Primary: scan `/Applications` and `~/Applications` for
`Contents/PlugIns/*.appex`, read `Info.plist`, keep rows whose
`NSExtension.NSExtensionPointIdentifier` is one of:

- `com.apple.Safari.extension`
- `com.apple.Safari.content-blocker`
- `com.apple.Safari.web-extension`

Optional overlay: parse `pluginkit -m -v` for `+` / `-` election. Inject I/O;
unit tests never call live `pluginkit` (sandbox often returns
`match: Connection invalid`).

## Placement

- Sidebar: Applications, **after Uninstaller**, before Updater.
- Slug: `extensions`.
- Icon: `puzzlepiece.extension`.
- On clean `main` this is the 10th module excluding Settings, so **⌘1–⌘9 do
  not shift**. Assert that in tests.

## Architecture

Pure Kit (`ManagedExtensions.swift`): models, Apple/third-party filter, path
policy, Info.plist catalog, `pluginkit` parser, trash-URL planner.

MacClean client: injected `listDirectory` / `readPlist` / `appBundles` /
`pluginKitOutput` / `openURL` / `reveal`. Live wiring uses `FileManager`,
`AppDiscovery.appBundles`, `NSWorkspace`, `CleanActions`.
