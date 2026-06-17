import AppKit
import MacCleanKit

/// Light/Dark/System override for the whole app, stored in UserDefaults
/// under `AppearanceManager.defaultsKey`. `.system` clears the override so
/// the app follows the OS appearance again.
///
/// The menu bar helper is a separate process and keeps following the
/// system appearance; this override applies to the main app only.
public enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: L10n.tr("跟随系统", "System")
        case .light: L10n.tr("浅色", "Light")
        case .dark: L10n.tr("深色", "Dark")
        }
    }

    /// nil means "follow the system" (clears `NSApp.appearance`).
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Applies the stored mode at launch and on picker changes. @MainActor
/// because `NSApp.appearance` is main-thread state; both call sites
/// (applicationDidFinishLaunching, SwiftUI onChange) are already on main.
/// Do NOT call from completion handlers (macOS 26 SIGTRAP, issue #58).
@MainActor
public enum AppearanceManager {
    public static let defaultsKey = "appearanceMode"

    public static var storedMode: AppearanceMode {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return AppearanceMode(rawValue: raw) ?? .system
    }

    public static func applyStored() {
        apply(storedMode)
    }

    public static func apply(_ mode: AppearanceMode) {
        NSApp.appearance = mode.nsAppearance
    }
}
