import Foundation

/// User-facing language for the Mac Sai interface.
///
/// We keep the preference in the shared defaults suite so the main app and the
/// menu-bar helper switch languages together.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case ru = "ru"
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
        case .ru:
            "ru"
        case .zhHans:
            "zh-Hans"
        case .en:
            "en"
        }
    }

    public var resolved: AppLanguage {
        switch self {
        case .system: Self.systemPreferred
        case .ru, .zhHans, .en: self
        }
    }

    public static var systemPreferred: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        return preferredLanguage(for: preferred)
    }

    static func preferredLanguage(for identifier: String) -> AppLanguage {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        switch normalized.split(separator: "-", maxSplits: 1).first {
        case "ru": return .ru
        case "zh": return .zhHans
        default: return .en
        }
    }

    /// Label shown in the language picker. These are intentionally native names
    /// instead of going through `L10n.tr`, so users can always find their
    /// preferred language even if the current UI language is unfamiliar.
    public var pickerLabel: String {
        switch self {
        case .system: L10n.tr("跟随系统", "System", "Системный")
        case .ru: "Русский"
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
/// Chinese/English/Russian switching at runtime.
public enum L10n {
    /// Keeps newly added strings usable until a Russian translation is supplied.
    /// Existing localized strings use the three-argument overload below.
    public static func tr(_ zhHans: String, _ english: @autoclosure () -> String) -> String {
        switch AppLanguage.current.resolved {
        case .zhHans: zhHans
        case .system, .en: english()
        case .ru: russianFallbacks[zhHans] ?? english()
        }
    }

    public static func tr(
        _ zhHans: String,
        _ english: @autoclosure () -> String,
        _ russian: @autoclosure () -> String
    ) -> String {
        switch AppLanguage.current.resolved {
        case .system, .en: english()
        case .ru: russian()
        case .zhHans: zhHans
        }
    }

    public static func tr(_ zhHans: String) -> String {
        switch AppLanguage.current.resolved {
        case .system, .en:
            englishFallbacks[zhHans] ?? zhHans
        case .ru:
            russianFallbacks[zhHans] ?? englishFallbacks[zhHans] ?? zhHans
        case .zhHans:
            zhHans
        }
    }

    /// Selects the Russian noun form for a non-negative count.
    /// Examples: 1 файл, 2 файла, 5 файлов, 11 файлов, 21 файл.
    public static func russianPlural(
        _ count: Int,
        one: String,
        few: String,
        many: String
    ) -> String {
        let magnitude = count.magnitude
        let mod10 = magnitude % 10
        let mod100 = magnitude % 100

        if mod10 == 1, mod100 != 11 { return one }
        if (2...4).contains(mod10), !(12...14).contains(mod100) { return few }
        return many
    }

    /// Small fallback table for values that are assembled dynamically or flow
    /// through model properties. Most UI strings use the three-argument overload
    /// so every supported translation lives beside the original expression.
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

    private static let russianFallbacks: [String: String] = [
        "智能扫描": "Умное сканирование",
        "系统垃圾": "Системный мусор",
        "邮件附件": "Почтовые вложения",
        "废纸篓": "Корзины",
        "恶意软件清理": "Удаление угроз",
        "隐私清理": "Конфиденциальность",
        "优化": "Оптимизация",
        "维护": "Обслуживание",
        "卸载器": "Удаление приложений",
        "应用更新": "Обновления",
        "空间透视": "Карта диска",
        "大文件与旧文件": "Большие и старые файлы",
        "重复文件": "Дубликаты",
        "文件粉碎": "Уничтожение файлов",
        "设置": "Настройки",
        "清理": "Очистка",
        "防护": "Защита",
        "性能": "Производительность",
        "应用": "Приложения",
        "文件": "Файлы",
        "全部": "Все",
        "未使用": "Неиспользуемые",
        "第三方": "Сторонние",
        "快速": "Быстро",
        "平衡": "Сбалансированно",
        "深度": "Глубоко",
        "开启": "включить",
        "关闭": "отключить",
        "压缩包": "Архивы",
        "已选择": "Выбрано",
        "运行中": "Работает",
        "未知": "Неизвестно",
        "进度": "Ход выполнения",
        "可用磁盘空间": "Свободное место на диске",
        "GPU 使用率": "Загрузка GPU",
        "内存使用率": "Использование памяти",
        "电池温度": "Температура аккумулятора",
        "菜单栏显示": "Показатель в строке меню",
        "选择应用图标旁显示的紧凑数值。GPU 或电池温度不可用时显示 --。":
            "Выберите компактный показатель рядом со значком приложения. Если данные GPU или температуры аккумулятора недоступны, отображается --.",
        "释放内存": "Освободить оперативную память",
        "释放可清除空间": "Освободить место, доступное для очистки",
        "运行维护脚本": "Запустить скрипты обслуживания",
        "验证启动磁盘": "Проверить загрузочный диск",
        "加速邮件": "Ускорить Почту",
        "重建启动服务": "Перестроить Launch Services",
        "重建 Spotlight 索引": "Перестроить индекс Spotlight",
        "刷新 DNS 缓存": "Очистить кэш DNS",
        "精简 Time Machine 快照": "Проредить снимки Time Machine",
    ]
}
