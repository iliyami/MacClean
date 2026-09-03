# Menu-bar widget persist (#138)

Date: 2026-08-26
Status: Design (approved for implementation)

## Problem

Issue #138: on Sonoma 14.8.9 / Intel MacBook Air, after setting the extra to
RAM usage, the menu-bar widget disappears and stays gone.

The RAM metric itself does not hide the icon. `MacCleanMenuApp` always renders
the sparkles template image; `MenuBarMetric.memoryUsage` only changes the
adjacent text (`RAM N%` or `RAM --`). A missing extra means the **helper
process is not running** (or macOS hid it in Control Center overflow — which
this PR cannot fix).

Two code-level failure modes, both already present:

1. **Mutual `exit(0)`.** The helper has two launch paths (`SMAppService.register`
   plus `NSWorkspace.openApplication`). `isHelperRunning()` can be false while
   LaunchServices is still spawning the SMAppService copy, so a second copy
   starts. Each `init` does `if any sibling { exit(0) }`. When both copies
   become visible to `NSWorkspace` at the same time, **both** exit. Intel
   machines widen that window. After that, nothing relaunches the helper until
   the next login or a main-app window appear that happens to start only one copy.

2. **No keep-alive.** If the helper crashes, `SMAppService.loginItem` does not
   restart it. The main app only re-registers on window `onAppear`. There is no
   `didTerminateApplication` observer.

## Goal

Keep exactly one `com.macclean.menu` process alive while the Settings toggle is
on, without fighting an explicit Quit from the extra, and without promising
that macOS will not hide extras in Control Center overflow.

## Non-goals

- Do not claim to fix Control Center / menu-bar overflow hiding.
- Do not change `MenuBarMetric` or RAM collection (`host_statistics64`).
- Do not mix in #137 (`task_for_pid` / process list memory).
- Do not add a LaunchAgent `KeepAlive` plist (new launch mechanism).
- Do not relaunch the helper when the main app is not running.
- Do not call `register()` / `unregister()` from unit tests.

## Approach

Pure policy in `MacCleanKit`:

- `MenuBarInstancePolicy.shouldExitAsDuplicate` — keep the oldest launchDate
  (then lowest PID). Exactly one survivor; never both-exit.
- `MenuBarKeepAlivePolicy.action` — enable + not running + not user-quit →
  wait once after register (so SMAppService can spawn), then
  `NSWorkspace.open`; disable → terminate; user-quit → do not relaunch.

Thin wiring:

- Helper `init` uses the instance policy instead of “any sibling → exit”.
- Extra **Quit Monitor** sets `menuBarWidgetUserQuit` in the shared defaults
  suite, then terminates.
- `setEnabled(true)` clears that flag (toggle / main-app launch still restore
  the extra, same as today).
- `MenuBarLauncher` waits a short grace after `register()` before opening.
- Main app observes `NSWorkspace.didTerminateApplicationNotification` for
  `com.macclean.menu` and relaunches only when the policy says so. Hop onto
  the main actor with `Task { @MainActor in }` (issue #58: never a
  completion handler that touches `@MainActor` state off-main).

## Honest product copy

PR and comments must say: if macOS hid the extra in Control Center overflow,
drag it back — this change does not control that. We fix the helper dying.

## Testing

Kit unit tests for both policies (two-process race, three instances, user-quit,
wait-then-launch, launch-in-flight). Source guards that the helper calls the
policy and that Quit sets the shared flag. No live `SMAppService` in tests.
