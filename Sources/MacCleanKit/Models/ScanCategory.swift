import Foundation

public enum ScanCategory: String, CaseIterable, Identifiable, Sendable {
    // System Junk
    case userCaches = "user_caches"
    case systemCaches = "system_caches"
    case userLogs = "user_logs"
    case systemLogs = "system_logs"
    case languageFiles = "language_files"
    case brokenPreferences = "broken_preferences"
    case brokenLoginItems = "broken_login_items"
    case documentVersions = "document_versions"
    case brokenDownloads = "broken_downloads"
    case iosDeviceBackups = "ios_device_backups"
    case oldUpdates = "old_updates"
    case universalBinaries = "universal_binaries"
    case xcodeJunk = "xcode_junk"
    case deletedUsers = "deleted_users"
    case unusedDiskImages = "unused_disk_images"
    case incompleteDownloads = "incomplete_downloads"
    case appLeftovers = "app_leftovers"
    case packageManagerCaches = "package_manager_caches"
    case ideCaches = "ide_caches"
    case aiToolCaches = "ai_tool_caches"

    // Mail
    case mailAttachments = "mail_attachments"

    // Trash
    case trashBins = "trash_bins"

    // Protection
    case malware = "malware"
    case browserPrivacy = "browser_privacy"
    case systemPrivacy = "system_privacy"

    // Files
    case largeFiles = "large_files"
    case oldFiles = "old_files"
    case duplicates = "duplicates"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .userCaches: L10n.tr("用户缓存文件", "User Cache Files", "Кэш пользователя")
        case .systemCaches: L10n.tr("系统缓存文件", "System Cache Files", "Системный кэш")
        case .userLogs: L10n.tr("用户日志文件", "User Log Files", "Журналы пользователя")
        case .systemLogs: L10n.tr("系统日志文件", "System Log Files", "Системные журналы")
        case .languageFiles: L10n.tr("语言文件", "Language Files", "Языковые файлы")
        case .brokenPreferences: L10n.tr("损坏的偏好设置", "Broken Preferences", "Повреждённые настройки")
        case .brokenLoginItems: L10n.tr("失效的登录项", "Broken Login Items", "Недействующие объекты входа")
        case .documentVersions: L10n.tr("文档版本", "Document Versions", "Версии документов")
        case .brokenDownloads: L10n.tr("残留下载文件", "Broken Downloads", "Остатки загрузок")
        case .iosDeviceBackups: L10n.tr("iOS 设备备份", "iOS Device Backups", "Резервные копии устройств iOS")
        case .oldUpdates: L10n.tr("旧更新文件", "Old Updates", "Старые обновления")
        case .universalBinaries: L10n.tr("通用二进制", "Universal Binaries", "Универсальные бинарные файлы")
        case .xcodeJunk: L10n.tr("Xcode 垃圾", "Xcode Junk", "Мусор Xcode")
        case .deletedUsers: L10n.tr("已删除用户数据", "Deleted Users", "Данные удалённых пользователей")
        case .unusedDiskImages: L10n.tr("未使用的磁盘映像", "Unused Disk Images", "Неиспользуемые образы дисков")
        case .incompleteDownloads: L10n.tr("未完成下载", "Incomplete Downloads", "Незавершённые загрузки")
        case .appLeftovers: L10n.tr("已删除应用的残留文件", "Leftovers from Deleted Apps", "Остатки удалённых приложений")
        case .packageManagerCaches: L10n.tr("包管理器缓存", "Package Manager Caches", "Кэш менеджеров пакетов")
        case .ideCaches: L10n.tr("IDE 与编辑器缓存", "IDE & Editor Caches", "Кэш IDE и редакторов")
        case .aiToolCaches: L10n.tr("AI 工具缓存", "AI Tool Caches", "Кэш AI-инструментов")
        case .mailAttachments: L10n.tr("邮件附件", "Mail Attachments", "Почтовые вложения")
        case .trashBins: L10n.tr("废纸篓", "Trash Bins", "Корзины")
        case .malware: L10n.tr("恶意软件", "Malware", "Вредоносное ПО")
        case .browserPrivacy: L10n.tr("浏览器隐私", "Browser Privacy", "Конфиденциальность браузеров")
        case .systemPrivacy: L10n.tr("系统隐私", "System Privacy", "Конфиденциальность системы")
        case .largeFiles: L10n.tr("大文件", "Large Files", "Большие файлы")
        case .oldFiles: L10n.tr("旧文件", "Old Files", "Старые файлы")
        case .duplicates: L10n.tr("重复文件", "Duplicates", "Дубликаты")
        }
    }

    /// One-line description shown under the category name in the results list.
    public var subtitle: String {
        switch self {
        case .userCaches: L10n.tr("应用临时文件，下次启动会重新生成。", "App temporary files. Regenerated next launch.", "Временные файлы приложений. Будут созданы заново при следующем запуске.")
        case .systemCaches: L10n.tr("由 macOS 管理的缓存，会自动重建。", "macOS-managed caches. Rebuilt automatically.", "Кэши под управлением macOS. Восстанавливаются автоматически.")
        case .userLogs: L10n.tr("应用写入的诊断日志。", "Diagnostic logs written by your apps.", "Диагностические журналы приложений.")
        case .systemLogs: L10n.tr("macOS 诊断日志。", "macOS diagnostic logs.", "Диагностические журналы macOS.")
        case .languageFiles: L10n.tr("应用内未使用的本地化语言资源。", "Unused localizations bundled with apps.", "Неиспользуемые локализации, встроенные в приложения.")
        case .brokenPreferences: L10n.tr("损坏或孤立的偏好设置文件。", "Corrupt or orphaned preference files.", "Повреждённые или оставшиеся без приложения файлы настроек.")
        case .brokenLoginItems: L10n.tr("指向已不存在应用的登录项。", "Login items pointing at apps that are gone.", "Объекты входа, ведущие к удалённым приложениям.")
        case .documentVersions: L10n.tr("旧的自动保存文档版本。", "Old autosaved document revisions.", "Старые автоматически сохранённые версии документов.")
        case .brokenDownloads: L10n.tr("失败或孤立下载留下的文件。", "Failed or orphaned download leftovers.", "Остатки неудачных или потерянных загрузок.")
        case .iosDeviceBackups: L10n.tr("iPhone 和 iPad 的本地备份。", "Local backups of iPhone and iPad devices.", "Локальные резервные копии устройств iPhone и iPad.")
        case .oldUpdates: L10n.tr("更新后遗留的安装包。", "Installer packages left behind after updating.", "Установочные пакеты, оставшиеся после обновлений.")
        case .universalBinaries: L10n.tr("应用二进制中未使用的 CPU 架构切片。", "Unused CPU slices inside app binaries.", "Неиспользуемые срезы архитектур CPU в бинарных файлах приложений.")
        case .xcodeJunk: L10n.tr("派生数据、归档和模拟器缓存。", "Derived data, archives, and simulator caches.", "Derived Data, архивы и кэши симуляторов.")
        case .deletedUsers: L10n.tr("已移除用户账户留下的数据。", "Leftover data from removed user accounts.", "Данные, оставшиеся от удалённых учётных записей.")
        case .unusedDiskImages: L10n.tr("曾经挂载但已不再需要的磁盘映像。", "Disk images you mounted once and forgot.", "Образы дисков, которые были смонтированы и больше не нужны.")
        case .incompleteDownloads: L10n.tr("未下载完成的文件。", "Partially downloaded files.", "Частично загруженные файлы.")
        case .appLeftovers: L10n.tr("已删除应用留下的支持文件。", "Support files from apps you've deleted.", "Служебные файлы удалённых приложений.")
        case .packageManagerCaches: L10n.tr("npm、Cargo、pip、Homebrew、Gradle 的可重建缓存。", "Regenerable caches from npm, Cargo, pip, Homebrew, and Gradle.", "Восстанавливаемые кэши npm, Cargo, pip, Homebrew и Gradle.")
        case .ideCaches: L10n.tr("代码编辑器的缓存（Cursor、Antigravity 等）。", "Caches from code editors like Cursor and Antigravity.", "Кэши редакторов кода, таких как Cursor и Antigravity.")
        case .aiToolCaches: L10n.tr("AI 编码工具的缓存（Claude、Codex）；不含历史与会话。", "Caches from AI coding tools (Claude, Codex). History and sessions excluded.", "Кэши AI-инструментов для программирования (Claude, Codex). История и сеансы не затрагиваются.")
        case .mailAttachments: L10n.tr("邮件附件的缓存副本。", "Saved copies of Mail attachments.", "Кэшированные копии почтовых вложений.")
        case .trashBins: L10n.tr("当前位于废纸篓中的项目。", "Items currently sitting in the Trash.", "Объекты, находящиеся в Корзине.")
        case .malware: L10n.tr("在磁盘上发现的已知恶意文件。", "Known malicious files found on disk.", "Известные вредоносные файлы, найденные на диске.")
        case .browserPrivacy: L10n.tr("浏览历史和跟踪数据；Cookie 与会话会保留。", "Browsing history and tracking data. Cookies and sessions stay.", "История браузера и данные отслеживания. Cookie и сеансы сохраняются.")
        case .systemPrivacy: L10n.tr("最近项目列表和其他隐私痕迹。", "Recent-items lists and other privacy traces.", "Списки недавних объектов и другие следы активности.")
        case .largeFiles: L10n.tr("占用空间最多的文件。", "The files taking up the most space.", "Файлы, занимающие больше всего места.")
        case .oldFiles: L10n.tr("长时间未打开的文件。", "Files you haven't opened in a long time.", "Файлы, которые давно не открывались.")
        case .duplicates: L10n.tr("同一文件的相同副本。", "Identical copies of the same file.", "Идентичные копии одного файла.")
        }
    }

    public var systemImage: String {
        switch self {
        case .userCaches, .systemCaches: "folder.badge.gearshape"
        case .userLogs, .systemLogs: "doc.text"
        case .languageFiles: "globe"
        case .brokenPreferences: "gearshape.triangle.fill"
        case .brokenLoginItems: "person.crop.circle.badge.exclamationmark"
        case .documentVersions: "doc.on.doc"
        case .brokenDownloads, .incompleteDownloads: "arrow.down.circle.dotted"
        case .iosDeviceBackups: "iphone"
        case .oldUpdates: "arrow.triangle.2.circlepath"
        case .universalBinaries: "cpu"
        case .xcodeJunk: "hammer"
        case .deletedUsers: "person.crop.circle.badge.minus"
        case .unusedDiskImages: "opticaldisc"
        case .appLeftovers: "shippingbox.and.arrow.backward"
        case .packageManagerCaches: "shippingbox"
        case .ideCaches: "macwindow"
        case .aiToolCaches: "sparkles"
        case .mailAttachments: "paperclip"
        case .trashBins: "trash"
        case .malware: "shield.lefthalf.filled.trianglebadge.exclamationmark"
        case .browserPrivacy: "safari"
        case .systemPrivacy: "hand.raised"
        case .largeFiles: "arrow.up.right.square"
        case .oldFiles: "clock.arrow.circlepath"
        case .duplicates: "plus.square.on.square"
        }
    }

    public var autoSelect: Bool {
        switch self {
        case .unusedDiskImages, .largeFiles, .oldFiles, .duplicates,
             .universalBinaries, .appLeftovers,
             .packageManagerCaches, .ideCaches, .aiToolCaches:
            // appLeftovers: deletes another app's leftover data; detection is
            // conservative but never auto-checked — the user reviews first.
            // universalBinaries: thinning rewrites the app's binaries in
            // place (lipo preserves their signatures; we never re-sign).
            // Still only reversible by re-downloading the app, so don't
            // pre-check — force explicit consent.
            false
        default:
            true
        }
    }
}
