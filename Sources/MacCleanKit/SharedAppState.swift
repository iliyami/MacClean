import Foundation

/// Inter-process state shared between the main Mac Sai app and the
/// menu bar widget. We use a named `UserDefaults` suite — both processes
/// open the same suite by name, macOS backs it with a single plist at
/// `~/Library/Preferences/com.macclean.shared.plist`, and writes from
/// one process show up in the other on the next read.
///
/// App Groups would be the canonical macOS pattern, but a named suite is
/// simpler and works regardless of signing. We keep it now that Mac Sai
/// is Developer ID signed and notarized, since the shared state is small,
/// JSON-serializable, and not security-sensitive.
public enum SharedAppState {
    public static let suiteName = "com.macclean.shared"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Protection status (Phase 2)

    public struct ProtectionStatus: Codable, Sendable, Equatable {
        public let lastScanDate: Date
        public let threatsFound: Int
        public let scanDepth: String

        public init(lastScanDate: Date, threatsFound: Int, scanDepth: String) {
            self.lastScanDate = lastScanDate
            self.threatsFound = threatsFound
            self.scanDepth = scanDepth
        }

        /// Localizes both the stable values written by current releases and
        /// display strings persisted by older English/Chinese builds.
        public var localizedScanDepth: String {
            switch scanDepth.lowercased() {
            case "quick", "快速", "быстро":
                L10n.tr("快速", "Quick", "Быстро")
            case "balanced", "平衡", "сбалансированно":
                L10n.tr("平衡", "Balanced", "Сбалансированно")
            case "deep", "深度", "глубоко":
                L10n.tr("深度", "Deep", "Глубоко")
            default:
                scanDepth
            }
        }

        /// Stale = last scan was more than 7 days ago. The menu glyph
        /// goes yellow at this threshold so users notice they haven't
        /// run a malware scan in a while.
        public var isStale: Bool {
            Date().timeIntervalSince(lastScanDate) > 7 * 24 * 3600
        }
    }

    private static let protectionStatusKey = "protectionStatus"

    public static var protectionStatus: ProtectionStatus? {
        get {
            guard let data = defaults.data(forKey: protectionStatusKey) else { return nil }
            return try? JSONDecoder().decode(ProtectionStatus.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: protectionStatusKey)
            } else {
                defaults.removeObject(forKey: protectionStatusKey)
            }
        }
    }

    // MARK: - Tip dismissals (Phase 5)

    /// Tips the user dismissed with "don't show again" — keyed by a
    /// stable tip-id string. Re-suggesting an explicitly-dismissed tip
    /// is annoying so we suppress them for 30 days.
    private static let tipDismissalsKey = "tipDismissals"

    public static func dismissTip(id: String) {
        var current = tipDismissals
        current[id] = Date()
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: tipDismissalsKey)
        }
    }

    public static var tipDismissals: [String: Date] {
        guard let data = defaults.data(forKey: tipDismissalsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    public static func isTipDismissed(id: String, suppressionWindow: TimeInterval = 30 * 24 * 3600) -> Bool {
        guard let when = tipDismissals[id] else { return false }
        return Date().timeIntervalSince(when) < suppressionWindow
    }

    // MARK: - Notification suppression (Phase 4)

    /// One-time notifications (battery health below threshold, etc.)
    /// shouldn't re-fire every minute. We record the kind+date here so
    /// the threshold watcher can throttle.
    private static let notificationLogKey = "notificationLog"

    public static func recordNotification(kind: String) {
        var current = notificationLog
        current[kind] = Date()
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: notificationLogKey)
        }
    }

    public static var notificationLog: [String: Date] {
        guard let data = defaults.data(forKey: notificationLogKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    /// `true` if the last notification of this kind fired within the
    /// throttle window. Disk-low alerts use a short window (15 min);
    /// battery-health/cycle alerts use a long one (7 days).
    public static func recentlyNotified(kind: String, throttle: TimeInterval) -> Bool {
        guard let when = notificationLog[kind] else { return false }
        return Date().timeIntervalSince(when) < throttle
    }
}
