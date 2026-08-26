import Foundation

/// Snapshot of one `com.macclean.menu` process for duplicate arbitration.
public struct MenuBarInstance: Equatable, Sendable {
    public let pid: Int32
    public let launchDate: Date?

    public init(pid: Int32, launchDate: Date?) {
        self.pid = pid
        self.launchDate = launchDate
    }
}

/// Decides whether this helper process should exit because another copy is
/// already running.
///
/// The previous check was `if any sibling { exit(0) }`. When SMAppService and
/// NSWorkspace both launched a copy, both processes saw each other and both
/// exited — the menu-bar extra vanished (issue #138). The rule here is a total
/// order: oldest `launchDate` wins, then lowest PID, so exactly one survivor.
public enum MenuBarInstancePolicy {
    public static func shouldExitAsDuplicate(
        selfPID: Int32,
        selfLaunchDate: Date?,
        siblings: [MenuBarInstance]
    ) -> Bool {
        guard !siblings.isEmpty else { return false }
        let selfInstance = MenuBarInstance(pid: selfPID, launchDate: selfLaunchDate)
        let keeper = (siblings + [selfInstance]).min { rank($0) < rank($1) }
        return keeper?.pid != selfPID
    }

    /// Missing launch dates sort as distant future so a process whose
    /// `launchDate` is known (already running) beats one LaunchServices has
    /// not populated yet. Two unknowns fall through to lowest PID. The pair
    /// stays a total order, so exactly one keeper.
    private static func rank(_ instance: MenuBarInstance) -> (Date, Int32) {
        (instance.launchDate ?? .distantFuture, instance.pid)
    }
}

/// Shared-suite flag so an explicit **Quit Monitor** is not undone by the
/// main app's terminate observer. Injected `UserDefaults` keeps tests off
/// the real `com.macclean.shared` plist.
public enum MenuBarKeepAlive {
    public static let userQuitKey = "menuBarWidgetUserQuit"
    public static let preferenceKey = "showMenuBarWidget"

    public static func isUserQuit(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: userQuitKey)
    }

    public static func setUserQuit(_ value: Bool, defaults: UserDefaults) {
        defaults.set(value, forKey: userQuitKey)
    }
}

/// What the main app should do to keep the helper aligned with the Settings
/// toggle. Pure: no `NSWorkspace` / `SMAppService`.
public enum MenuBarKeepAlivePolicy {
    public enum Action: Equatable, Sendable {
        case none
        case waitThenRecheck
        case launch
        case terminate
    }

    /// Grace so `SMAppService.register()` can spawn the helper before we
    /// `NSWorkspace.open` a second copy (the race that used to mutual-exit).
    public static let smAppServiceLaunchGrace: Duration = .milliseconds(500)

    public static func action(
        preferenceEnabled: Bool,
        helperIsRunning: Bool,
        userQuit: Bool,
        alreadyWaitedAfterRegister: Bool,
        launchInFlight: Bool
    ) -> Action {
        if !preferenceEnabled {
            return helperIsRunning ? .terminate : .none
        }
        if helperIsRunning || userQuit || launchInFlight {
            return .none
        }
        if !alreadyWaitedAfterRegister {
            return .waitThenRecheck
        }
        return .launch
    }
}
