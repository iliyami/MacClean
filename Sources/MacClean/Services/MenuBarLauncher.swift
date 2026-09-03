import Foundation
import AppKit
import ServiceManagement
import MacCleanKit

/// Registers / unregisters the menu bar widget as a login item via
/// `SMAppService.loginItem(identifier:)`. The identifier is the bundle id
/// of the helper app embedded at
/// `Mac Sai.app/Contents/Library/LoginItems/MacCleanMenu.app/`. macOS
/// looks at that exact path to find the helper, so the bundling in
/// `scripts/build-dmg.sh` must match.
///
/// On registration the system *may* launch the helper; with ad-hoc signed
/// builds it often does not. `setEnabled(true)` therefore waits a short
/// grace and opens via NSWorkspace if the helper is still missing. On
/// unregister the helper is stopped. A terminate observer relaunches it
/// if the Settings toggle is still on and the user did not quit the extra.
@MainActor
@Observable
public final class MenuBarLauncher {
    public enum LauncherError: Error, LocalizedError {
        case registrationFailed(String)
        case unregisterFailed(String)

        public var errorDescription: String? {
            switch self {
            case .registrationFailed(let msg):
                return L10n.tr("无法启用菜单栏小组件：\(msg)", "Couldn't enable the menu bar widget: \(msg)", "Не удалось включить виджет в строке меню: \(msg)")
            case .unregisterFailed(let msg):
                return L10n.tr("无法停用菜单栏小组件：\(msg)", "Couldn't disable the menu bar widget: \(msg)", "Не удалось отключить виджет в строке меню: \(msg)")
            }
        }
    }

    public static let shared = MenuBarLauncher()

    public internal(set) var lastError: LauncherError?

    /// True while a register/unregister XPC round-trip is in flight; the
    /// Settings toggle shows a spinner and disables itself instead of
    /// blocking the main thread on backgroundtaskmanagementd.
    public internal(set) var isBusy = false

    /// Observable mirror of `service.status`, refreshed after every
    /// `setEnabled` operation. `SMAppService.status` is a live computed
    /// value with no change notifications; the old Settings UI force-
    /// rebuilt the whole Form (`.id(refreshTick)`) to work around that,
    /// which is exactly the jank this snapshot removes.
    public internal(set) var statusSnapshot: SMAppService.Status = .notRegistered

    private let service = SMAppService.loginItem(identifier: MCConstants.menuBundleIdentifier)
    private var helperTerminationObserver: NSObjectProtocol?
    private var isLaunchingHelper = false

    public var isRegistered: Bool {
        service.status == .enabled
    }

    public var status: SMAppService.Status {
        service.status
    }

    private init() {
        statusSnapshot = service.status
        startWatchingHelperTermination()
    }

    /// Relaunch the helper if it dies unexpectedly while the Settings toggle
    /// is on. Idempotent. The observer hops onto the main actor with
    /// `Task { @MainActor in }` — do not replace that with a completion
    /// handler that touches `@MainActor` state (issue #58).
    public func startWatchingHelperTermination() {
        guard helperTerminationObserver == nil else { return }
        helperTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == MCConstants.menuBundleIdentifier
            else { return }
            Task { @MainActor in
                await MenuBarLauncher.shared.ensureHelperRunningIfPreferred()
            }
        }
    }

    /// Watchdog entry: launch the helper if the preference is on, it is not
    /// running, and the user did not quit it from the extra. Does **not**
    /// call `SMAppService.register()` — that stays on the enable path so a
    /// crash cannot spam backgroundtaskmanagementd.
    public func ensureHelperRunningIfPreferred() async {
        let enabled = UserDefaults.standard.object(forKey: MenuBarKeepAlive.preferenceKey) as? Bool ?? true
        await reconcileHelper(
            preferenceEnabled: enabled,
            afterRegister: false,
            honorUserQuit: true
        )
    }

    public func register() throws {
        do {
            try service.register()
            lastError = nil
        } catch {
            let wrapped = LauncherError.registrationFailed(error.localizedDescription)
            lastError = wrapped
            throw wrapped
        }
    }

    public func unregister() throws {
        do {
            try service.unregister()
            lastError = nil
        } catch {
            let wrapped = LauncherError.unregisterFailed(error.localizedDescription)
            lastError = wrapped
            throw wrapped
        }
    }

    /// Best-effort enable; swallows errors so app launch can't be
    /// blocked by a Settings-level "show in menu bar" preference flip
    /// going sideways. The error surfaces via `lastError` and the
    /// Settings UI can prompt the user to retry.
    ///
    /// Two-step on enable:
    ///   1. SMAppService.register() — auto-start at login (the "real"
    ///      reason for the API).
    ///   2. NSWorkspace.openApplication() — launch the helper NOW.
    ///
    /// Step 2 exists because SMAppService is finicky with ad-hoc
    /// signed builds (the path Homebrew users get). It can return
    /// `.enabled` from `register()` without macOS actually launching
    /// the helper — the system intends to launch it at next login
    /// but won't kick it off in the current session. We want the
    /// widget visible the moment the toggle flips, so we kick it
    /// directly via NSWorkspace. Idempotent: skips if already running.
    /// Minimum time `isBusy` stays true. The XPC round-trip often finishes
    /// in tens of ms; a spinner that flashes in and out for one frame reads
    /// as a glitch, not feedback. Holding it for a beat makes the toggle
    /// feel deliberate.
    static let minimumBusyDuration: Duration = .milliseconds(450)

    public func setEnabled(_ enabled: Bool) async {
        isBusy = true
        let started = ContinuousClock.now
        defer { isBusy = false }
        // register()/unregister() block on an XPC round-trip to
        // backgroundtaskmanagementd (the visible "toggle lag"), so they run
        // off the main actor. The detached task touches no @MainActor state
        // (issue #58 rule); results come back here, on the main actor.
        let failure: String? = await Task.detached(priority: .userInitiated) {
            let service = SMAppService.loginItem(identifier: MCConstants.menuBundleIdentifier)
            do {
                if enabled { try service.register() } else { try service.unregister() }
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        lastError = failure.map {
            enabled ? .registrationFailed($0) : .unregisterFailed($0)
        }
        if enabled {
            MenuBarKeepAlive.setUserQuit(false, defaults: SharedAppState.defaults)
        }
        await reconcileHelper(
            preferenceEnabled: enabled,
            afterRegister: enabled,
            honorUserQuit: false
        )
        statusSnapshot = service.status
        // Pad sub-minimum operations so the spinner doesn't flash for a
        // single frame (see minimumBusyDuration).
        let elapsed = ContinuousClock.now - started
        if elapsed < Self.minimumBusyDuration {
            try? await Task.sleep(for: Self.minimumBusyDuration - elapsed)
        }
    }

    /// Path to the bundled `MacCleanMenu.app` helper. Returns `nil`
    /// when running under `swift run` (no .app wrapper around us),
    /// which is fine — dev workflow is `swift run MacCleanMenu`
    /// directly.
    public func helperAppURL() -> URL? {
        let helper = Bundle.main.bundleURL
            .appending(path: "Contents")
            .appending(path: "Library")
            .appending(path: "LoginItems")
            .appending(path: "MacCleanMenu.app")
        guard FileManager.default.fileExists(atPath: helper.path) else { return nil }
        return helper
    }

    private func isHelperRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == MCConstants.menuBundleIdentifier
        }
    }

    /// Align the running helper with the preference. `afterRegister` waits
    /// once so SMAppService can spawn before we open a second copy.
    /// `honorUserQuit` is true for the watchdog (don't undo Quit Monitor)
    /// and false for the Settings toggle / launch re-sync.
    func reconcileHelper(
        preferenceEnabled: Bool,
        afterRegister: Bool,
        honorUserQuit: Bool
    ) async {
        var waited = !afterRegister
        let userQuit = honorUserQuit && MenuBarKeepAlive.isUserQuit(SharedAppState.defaults)
        while true {
            switch MenuBarKeepAlivePolicy.action(
                preferenceEnabled: preferenceEnabled,
                helperIsRunning: isHelperRunning(),
                userQuit: userQuit,
                alreadyWaitedAfterRegister: waited,
                launchInFlight: isLaunchingHelper
            ) {
            case .none:
                return
            case .waitThenRecheck:
                try? await Task.sleep(for: MenuBarKeepAlivePolicy.smAppServiceLaunchGrace)
                waited = true
            case .launch:
                guard let url = helperAppURL() else { return }
                isLaunchingHelper = true
                defer { isLaunchingHelper = false }
                await openHelper(at: url)
                return
            case .terminate:
                terminateRunningHelper()
                return
            }
        }
    }

    /// Launch the bundled helper at `url`, recording any failure in `lastError`.
    ///
    /// Deliberately uses the **async** `openApplication` overload, never the
    /// completion-handler one. LaunchServices fires that completion handler on
    /// its own dispatch queue (`com.apple.launchservices.open-queue`), and
    /// because `MenuBarLauncher` is `@MainActor` the trailing closure is
    /// inferred main-actor-isolated. On the macOS 26 runtime the closure's
    /// main-actor executor assertion *traps* (SIGTRAP) the instant it runs
    /// off-main — that is issue #58. Older runtimes silently tolerated it,
    /// which is why the crash only surfaced for users on macOS 26.
    ///
    /// Awaiting inside this `@MainActor` method resumes the continuation back
    /// on the main actor, so the `lastError` write is safe. Do NOT reintroduce
    /// a completion handler that touches `@MainActor` state here.
    func openHelper(at url: URL) async {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false   // Don't steal focus from the main app
        config.hides = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        } catch {
            lastError = .registrationFailed(error.localizedDescription)
        }
    }

    private func terminateRunningHelper() {
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier == MCConstants.menuBundleIdentifier {
            app.terminate()
        }
    }
}
