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
        case .userCaches: L10n.tr("用户缓存文件", "User Cache Files")
        case .systemCaches: L10n.tr("系统缓存文件", "System Cache Files")
        case .userLogs: L10n.tr("用户日志文件", "User Log Files")
        case .systemLogs: L10n.tr("系统日志文件", "System Log Files")
        case .languageFiles: L10n.tr("语言文件", "Language Files")
        case .brokenPreferences: L10n.tr("损坏的偏好设置", "Broken Preferences")
        case .brokenLoginItems: L10n.tr("失效的登录项", "Broken Login Items")
        case .documentVersions: L10n.tr("文档版本", "Document Versions")
        case .brokenDownloads: L10n.tr("残留下载文件", "Broken Downloads")
        case .iosDeviceBackups: L10n.tr("iOS 设备备份", "iOS Device Backups")
        case .oldUpdates: L10n.tr("旧更新文件", "Old Updates")
        case .universalBinaries: L10n.tr("通用二进制", "Universal Binaries")
        case .xcodeJunk: L10n.tr("Xcode 垃圾", "Xcode Junk")
        case .deletedUsers: L10n.tr("已删除用户数据", "Deleted Users")
        case .unusedDiskImages: L10n.tr("未使用的磁盘映像", "Unused Disk Images")
        case .incompleteDownloads: L10n.tr("未完成下载", "Incomplete Downloads")
        case .appLeftovers: L10n.tr("已删除应用的残留文件", "Leftovers from Deleted Apps")
        case .mailAttachments: L10n.tr("邮件附件", "Mail Attachments")
        case .trashBins: L10n.tr("废纸篓", "Trash Bins")
        case .malware: L10n.tr("恶意软件", "Malware")
        case .browserPrivacy: L10n.tr("浏览器隐私", "Browser Privacy")
        case .systemPrivacy: L10n.tr("系统隐私", "System Privacy")
        case .largeFiles: L10n.tr("大文件", "Large Files")
        case .oldFiles: L10n.tr("旧文件", "Old Files")
        case .duplicates: L10n.tr("重复文件", "Duplicates")
        }
    }

    /// One-line description shown under the category name in the results list.
    public var subtitle: String {
        switch self {
        case .userCaches: L10n.tr("应用临时文件，下次启动会重新生成。", "App temporary files. Regenerated next launch.")
        case .systemCaches: L10n.tr("由 macOS 管理的缓存，会自动重建。", "macOS-managed caches. Rebuilt automatically.")
        case .userLogs: L10n.tr("应用写入的诊断日志。", "Diagnostic logs written by your apps.")
        case .systemLogs: L10n.tr("macOS 诊断日志。", "macOS diagnostic logs.")
        case .languageFiles: L10n.tr("应用内未使用的本地化语言资源。", "Unused localizations bundled with apps.")
        case .brokenPreferences: L10n.tr("损坏或孤立的偏好设置文件。", "Corrupt or orphaned preference files.")
        case .brokenLoginItems: L10n.tr("指向已不存在应用的登录项。", "Login items pointing at apps that are gone.")
        case .documentVersions: L10n.tr("旧的自动保存文档版本。", "Old autosaved document revisions.")
        case .brokenDownloads: L10n.tr("失败或孤立下载留下的文件。", "Failed or orphaned download leftovers.")
        case .iosDeviceBackups: L10n.tr("iPhone 和 iPad 的本地备份。", "Local backups of iPhone and iPad devices.")
        case .oldUpdates: L10n.tr("更新后遗留的安装包。", "Installer packages left behind after updating.")
        case .universalBinaries: L10n.tr("应用二进制中未使用的 CPU 架构切片。", "Unused CPU slices inside app binaries.")
        case .xcodeJunk: L10n.tr("派生数据、归档和模拟器缓存。", "Derived data, archives, and simulator caches.")
        case .deletedUsers: L10n.tr("已移除用户账户留下的数据。", "Leftover data from removed user accounts.")
        case .unusedDiskImages: L10n.tr("曾经挂载但已不再需要的磁盘映像。", "Disk images you mounted once and forgot.")
        case .incompleteDownloads: L10n.tr("未下载完成的文件。", "Partially downloaded files.")
        case .appLeftovers: L10n.tr("已删除应用留下的支持文件。", "Support files from apps you've deleted.")
        case .mailAttachments: L10n.tr("邮件附件的缓存副本。", "Saved copies of Mail attachments.")
        case .trashBins: L10n.tr("当前位于废纸篓中的项目。", "Items currently sitting in the Trash.")
        case .malware: L10n.tr("在磁盘上发现的已知恶意文件。", "Known malicious files found on disk.")
        case .browserPrivacy: L10n.tr("浏览历史和跟踪数据；Cookie 与会话会保留。", "Browsing history and tracking data. Cookies and sessions stay.")
        case .systemPrivacy: L10n.tr("最近项目列表和其他隐私痕迹。", "Recent-items lists and other privacy traces.")
        case .largeFiles: L10n.tr("占用空间最多的文件。", "The files taking up the most space.")
        case .oldFiles: L10n.tr("长时间未打开的文件。", "Files you haven't opened in a long time.")
        case .duplicates: L10n.tr("同一文件的相同副本。", "Identical copies of the same file.")
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
             .universalBinaries, .appLeftovers:
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
