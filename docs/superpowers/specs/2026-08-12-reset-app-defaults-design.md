# Reset an app to defaults (#52)

Date: 2026-08-12
Status: Design (approved for implementation)

## Problem

The Uninstaller’s **Reset** button only clears the current selection in the UI
(`resetSelection()`). Issue #52 asks for a real “fresh-install state” action:
clear an app’s caches, preferences, and saved state **without** removing the
`.app` bundle.

## Goal

Replace the misleading Reset control with **Reset to Defaults**: trash only
user-library files that restore factory settings. The app stays installed.
All deletion goes through `SafetyGuard` + `CleaningEngine` via `CleanActions`
(trash-first, never `.dryRun`).

## Non-goals

- No new sidebar module.
- Do not delete the app bundle, LaunchAgents/Daemons, plug-ins, preference
  panes, privileged helpers, or Application Support / Containers (those hold
  licenses, databases, and documents).
- No change to uninstall behaviour or `SafetyGuard` protected-path lists.
- No `Localizable.strings` migration; new copy uses `L10n.tr`.

## Approach

Pure policy in `MacCleanKit.AppResetPolicy` classifies each associated file:

| Decision | Paths |
|---|---|
| **resetable** | `~/Library/Caches`, `Preferences`, `Saved Application State`, `Logs`, `Cookies`, `HTTPStorages`, `WebKit` |
| **keepBundle** | the `.app` itself or anything inside it |
| **keepUserData** | Application Support, Containers, Group Containers, Application Scripts |
| **keepSystemIntegration** | LaunchAgents, plug-ins, helpers, anything else |

`AppReset.plan` (MacClean, same shape as `AppUninstaller.plan`) intersects the
user’s checkbox selection with resetable files. Empty plan → button disabled.

Protected Apple apps **can** be reset (caches/prefs only). They still cannot
be uninstalled.

UI: confirmation alert (quit-first note), then `CleanActions.executeUserClean`.
Reload associated files; keep the app selected. Surface engine errors.

## Testing

Kit unit tests for classification (including prefix-boundary and “never the
bundle”). MacClean tests for `AppReset.plan`. Adversarial: Application Support,
Containers, LaunchAgents, and the bundle must never enter the plan.
