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
/// On registration the system launches the helper immediately (no need
/// to call NSWorkspace.open). On unregister the helper is also stopped.
/// State is queryable via `status` so the Settings toggle can reflect
/// the truth of "is the widget actually running right now."
@MainActor
@Observable
public final class MenuBarLauncher {
    public enum LauncherError: Error, LocalizedError {
        case registrationFailed(String)
        case unregisterFailed(String)

        public var errorDescription: String? {
            switch self {
            case .registrationFailed(let msg):
                return L10n.tr("无法启用菜单栏小组件：\(msg)", "Couldn't enable the menu bar widget: \(msg)")
            case .unregisterFailed(let msg):
                return L10n.tr("无法停用菜单栏小组件：\(msg)", "Couldn't disable the menu bar widget: \(msg)")
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

    public var isRegistered: Bool {
        service.status == .enabled
    }

    public var status: SMAppService.Status {
        service.status
    }

    private init() {
        statusSnapshot = service.status
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
            launchHelperIfNotRunning()
        } else {
            terminateRunningHelper()
        }
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

    private func launchHelperIfNotRunning() {
        guard !isHelperRunning(), let url = helperAppURL() else { return }
        Task { @MainActor in await openHelper(at: url) }
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
