import Foundation
import ServiceManagement
import MacCleanKit

/// Registers / unregisters the main app as a login item via
/// `SMAppService.mainApp`. Mirrors `MenuBarLauncher`: best-effort
/// `setEnabled`, errors surfaced through `lastError` for the Settings UI.
///
/// Under `swift run` (no .app bundle) registration fails and the error
/// shows in Settings; same dev-workflow caveat as the widget toggle.
@MainActor
@Observable
public final class LaunchAtLoginManager {
    public enum LaunchAtLoginError: Error, LocalizedError {
        case updateFailed(enabling: Bool, message: String)

        public var errorDescription: String? {
            switch self {
            case .updateFailed(let enabling, let message):
                let action = enabling ? L10n.tr("开启") : L10n.tr("关闭")
                return L10n.tr("无法\(action)开机自动启动：\(message)", "Couldn't \(action) launch at login: \(message)")
            }
        }
    }

    public static let shared = LaunchAtLoginManager()

    public internal(set) var lastError: LaunchAtLoginError?

    /// True while a register/unregister XPC round-trip is in flight; the
    /// Settings toggle shows a spinner and disables itself instead of
    /// blocking the main thread on backgroundtaskmanagementd.
    public internal(set) var isBusy = false

    /// Observable mirror of `SMAppService.mainApp.status`, refreshed after
    /// every operation. `SMAppService.status` is a live computed value with
    /// no change notifications, so views read this snapshot.
    public internal(set) var status: SMAppService.Status = .notRegistered

    public var isEnabled: Bool { status == .enabled }

    private init() {
        status = SMAppService.mainApp.status
    }

    /// Minimum time `isBusy` stays true. The XPC round-trip often finishes
    /// in tens of ms; a spinner that flashes in and out for one frame reads
    /// as a glitch, not feedback. Holding it for a beat makes the toggle
    /// feel deliberate.
    static let minimumBusyDuration: Duration = .milliseconds(450)

    public func setEnabled(_ enabled: Bool) async {
        isBusy = true
        let started = ContinuousClock.now
        defer { isBusy = false }
        // register()/unregister() block on an XPC round-trip (the visible
        // "toggle lag"), so they run off the main actor. The detached task
        // touches no @MainActor state (issue #58 rule); the result comes
        // back here, on the main actor.
        let failure: String? = await Task.detached(priority: .userInitiated) {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        lastError = failure.map { .updateFailed(enabling: enabled, message: $0) }
        status = SMAppService.mainApp.status
        // Pad sub-minimum operations so the spinner doesn't flash for a
        // single frame (see minimumBusyDuration).
        let elapsed = ContinuousClock.now - started
        if elapsed < Self.minimumBusyDuration {
            try? await Task.sleep(for: Self.minimumBusyDuration - elapsed)
        }
    }
}
