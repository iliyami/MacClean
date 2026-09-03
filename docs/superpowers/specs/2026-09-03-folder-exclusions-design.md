# Folder exclusion list (#141)

Date: 2026-09-03
Status: Design (approved for implementation)

## Problem

Users want specific folders never touched by Mac Sai scans or cleanup
(e.g. an app’s offline cache). Issue #141 asks for a Settings list of
folder paths to exclude.

## Goal

Settings → **Excluded Folders**: add/remove absolute folder paths. Those
paths (and descendants) never appear in cleanup scan results and cannot
be deleted through CleaningEngine / Shredder / any SafetyGuard caller.

## Non-goals

- No SpaceLens browse hiding (browse-only module).
- No Uninstaller UI filtering of leftover rows (delete still refused).
- No security-scoped bookmarks / sandbox entitlements changes.
- No `Localizable.strings`; new copy uses `L10n.tr(zh, en, ru)`.
- Do not claim exclusions survive a full-disk wipe or other apps.

## Scope decisions

| Topic | Choice |
|---|---|
| Effect | Scan filter **and** SafetyGuard delete refusal (incl. Shredder) |
| Allowed roots | Under `$HOME` or `/Volumes/…` only |
| Matching | Path prefix with `/` boundary + firmlink canonicalize |
| Persistence | `UserDefaults.standard` string array (like `LanguagePreferences`) |
| Cap | 50 folders; refuse excluding `$HOME` itself or `/Volumes` root |

## Approach

Pure Kit:

1. **`PathExclusion`** — `isInside(path, root:)`, `isExcluded(url, by:)`,
   normalize/canonicalize via `SafetyGuard.canonicalizeMacOSFirmlinks`.
2. **`FolderExclusionPreferences`** — load/store paths; `candidateDecision`
   for Add (allow / reject reason); prune descendants when an ancestor is
   already listed; injectable `UserDefaults` + home path for tests.
3. **`CleanFilter`** — `filteringUncleanable` also drops excluded URLs
   (injected `excludedFolders` defaulting to prefs).
4. **`SafetyGuard`** — new `SafetyError.userExcluded`; `validatePath`
   accepts optional `excludedFolders` (defaults to prefs).

MacClean:

- Settings section: list + Add (NSOpenPanel, directories only) + Remove.
- `ScanCoordinator` second-pass filter uses the same CleanFilter helper.
- `DuplicatesModule.scanDisplayGroups` also drops excluded cleanable copies.

## Honest product copy

Buttons and caption say excluded folders are skipped by scans and **cannot
be deleted** by Mac Sai. They do not protect against other apps or Finder.

## Testing

Kit unit tests for path matching (boundary, firmlinks, home vs volumes,
reject system / home itself), prefs round-trip, CleanFilter drop, SafetyGuard
refusal. Source guard that Settings mentions excluded folders. No live
NSOpenPanel in tests.
