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
        case .userCaches: "User Cache Files"
        case .systemCaches: "System Cache Files"
        case .userLogs: "User Log Files"
        case .systemLogs: "System Log Files"
        case .languageFiles: "Language Files"
        case .brokenPreferences: "Broken Preferences"
        case .brokenLoginItems: "Broken Login Items"
        case .documentVersions: "Document Versions"
        case .brokenDownloads: "Broken Downloads"
        case .iosDeviceBackups: "iOS Device Backups"
        case .oldUpdates: "Old Updates"
        case .universalBinaries: "Universal Binaries"
        case .xcodeJunk: "Xcode Junk"
        case .deletedUsers: "Deleted Users"
        case .unusedDiskImages: "Unused Disk Images"
        case .incompleteDownloads: "Incomplete Downloads"
        case .mailAttachments: "Mail Attachments"
        case .trashBins: "Trash Bins"
        case .malware: "Malware"
        case .browserPrivacy: "Browser Privacy"
        case .systemPrivacy: "System Privacy"
        case .largeFiles: "Large Files"
        case .oldFiles: "Old Files"
        case .duplicates: "Duplicates"
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
             .universalBinaries:
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
