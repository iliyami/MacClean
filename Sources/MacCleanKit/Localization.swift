import Foundation

/// User-facing language for the Mac Sai interface.
///
/// We keep the preference in the shared defaults suite so the main app and the
/// menu-bar helper switch languages together.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en = "en"

    public static let defaultsKey = "appLanguage"
    public static let fallback: AppLanguage = .en

    public var id: String { rawValue }

    public var localeIdentifier: String { resolved.localeIdentifierForResolvedLanguage }

    private var localeIdentifierForResolvedLanguage: String {
        switch self {
        case .system:
            Self.systemPreferred.localeIdentifierForResolvedLanguage
        case .zhHans:
            "zh-Hans"
        case .en:
            "en"
        }
    }

    public var resolved: AppLanguage {
        switch self {
        case .system: Self.systemPreferred
        case .zhHans, .en: self
        }
    }

    public static var systemPreferred: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        let normalized = preferred.replacingOccurrences(of: "_", with: "-").lowercased()
        return normalized.hasPrefix("zh") ? .zhHans : .en
    }

    /// Label shown in the language picker. These are intentionally native names
    /// instead of going through `L10n.tr`, so users can always find their
    /// preferred language even if the current UI language is unfamiliar.
    public var pickerLabel: String {
        switch self {
        case .system: L10n.tr("跟随系统", "System")
        case .zhHans: "简体中文"
        case .en: "English"
        }
    }

    public static var current: AppLanguage {
        get {
            if let raw = SharedAppState.defaults.string(forKey: defaultsKey),
               let language = AppLanguage(rawValue: raw) {
                return language
            }
            if let raw = UserDefaults.standard.string(forKey: defaultsKey),
               let language = AppLanguage(rawValue: raw) {
                return language
            }
            return fallback
        }
        set {
            SharedAppState.defaults.set(newValue.rawValue, forKey: defaultsKey)
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    /// Set a product default without changing an existing user choice. Tests and
    /// command-line tools keep the English fallback, while the shipped apps call
    /// this on launch to follow the user's system language by default.
    public static func registerDefault(_ language: AppLanguage) {
        guard SharedAppState.defaults.string(forKey: defaultsKey) == nil,
              UserDefaults.standard.string(forKey: defaultsKey) == nil else { return }
        current = language
    }
}

/// Lightweight runtime localization used by both executables.
///
/// The project is mostly SwiftUI views plus model strings that were originally
/// hard-coded. A full `.strings` migration would require touching almost every
/// call site and packaging resource bundles for the custom app builder. This
/// helper keeps the current no-resource build flow while still allowing instant
/// Chinese/English switching at runtime.
public enum L10n {
    public static func tr(_ zhHans: String, _ english: @autoclosure () -> String) -> String {
        AppLanguage.current.resolved == .en ? english() : zhHans
    }

    public static func tr(_ zhHans: String) -> String {
        guard AppLanguage.current.resolved == .en else { return zhHans }
        return englishFallbacks[zhHans] ?? zhHans
    }

    /// Small fallback table for values that are assembled dynamically or flow
    /// through model properties. Most UI strings use the two-argument overload
    /// so the original English expression can live beside the Chinese text.
    private static let englishFallbacks: [String: String] = [
        "智能扫描": "Smart Scan",
        "系统垃圾": "System Junk",
        "邮件附件": "Mail Attachments",
        "废纸篓": "Trash Bins",
        "恶意软件清理": "Malware Removal",
        "隐私清理": "Privacy",
        "优化": "Optimization",
        "维护": "Maintenance",
        "卸载器": "Uninstaller",
        "应用更新": "Updater",
        "空间透视": "Space Lens",
        "大文件与旧文件": "Large & Old Files",
        "重复文件": "Duplicates",
        "文件粉碎": "Shredder",
        "设置": "Settings",
        "清理": "Cleanup",
        "防护": "Protection",
        "性能": "Performance",
        "应用": "Applications",
        "文件": "Files",
        "全部": "All",
        "未使用": "Unused",
        "第三方": "Third-party",
        "快速": "Quick",
        "平衡": "Balanced",
        "深度": "Deep",
        "开启": "enable",
        "关闭": "disable",
        "压缩包": "Archives",
        "已选择": "Selected",
        "运行中": "Running",
        "未知": "Unknown",
        "进度": "Progress",
        "释放内存": "Free Up RAM",
        "释放可清除空间": "Free Up Purgeable Space",
        "运行维护脚本": "Run Maintenance Scripts",
        "验证启动磁盘": "Verify Startup Disk",
        "加速邮件": "Speed Up Mail",
        "重建启动服务": "Rebuild Launch Services",
        "重建 Spotlight 索引": "Reindex Spotlight",
        "刷新 DNS 缓存": "Flush DNS Cache",
        "精简 Time Machine 快照": "Thin Time Machine Snapshots",
    ]
}
