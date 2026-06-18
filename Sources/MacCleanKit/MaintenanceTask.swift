import Foundation

/// The set of maintenance tasks Mac Sai knows how to run. Pure data — the
/// actual `Process` execution happens in `MaintenanceExecutor` in the
/// MacClean target.
public enum MaintenanceTask: String, CaseIterable, Identifiable, Sendable {
    case freeUpRAM = "Free Up RAM"
    case freeUpPurgeableSpace = "Free Up Purgeable Space"
    case runMaintenanceScripts = "Run Maintenance Scripts"
    // NOTE: "Repair Disk Permissions" was removed (issue #82). Apple deleted
    // the `diskutil repairPermissions` verb in OS X 10.11 El Capitan, so the
    // task could only ever fail on supported macOS. Repairing system
    // permissions is obsolete under SIP + the sealed System volume, and the
    // home-folder alternative (`diskutil resetUserPermissions`) is undocumented,
    // Apple-deprecated, slow, and ACL-incomplete — not fit for a one-click tool.
    case verifyStartupDisk = "Verify Startup Disk"
    case speedUpMail = "Speed Up Mail"
    case rebuildLaunchServices = "Rebuild Launch Services"
    case reindexSpotlight = "Reindex Spotlight"
    case flushDNSCache = "Flush DNS Cache"
    case thinTimeMachineSnapshots = "Thin Time Machine Snapshots"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .freeUpRAM: L10n.tr("释放内存", rawValue)
        case .freeUpPurgeableSpace: L10n.tr("释放可清除空间", rawValue)
        case .runMaintenanceScripts: L10n.tr("运行维护脚本", rawValue)
        case .verifyStartupDisk: L10n.tr("验证启动磁盘", rawValue)
        case .speedUpMail: L10n.tr("加速邮件", rawValue)
        case .rebuildLaunchServices: L10n.tr("重建启动服务", rawValue)
        case .reindexSpotlight: L10n.tr("重建 Spotlight 索引", rawValue)
        case .flushDNSCache: L10n.tr("刷新 DNS 缓存", rawValue)
        case .thinTimeMachineSnapshots: L10n.tr("精简 Time Machine 快照", rawValue)
        }
    }

    public var icon: String {
        switch self {
        case .freeUpRAM: "memorychip"
        case .freeUpPurgeableSpace: "internaldrive"
        case .runMaintenanceScripts: "terminal"
        case .verifyStartupDisk: "checkmark.shield"
        case .speedUpMail: "envelope"
        case .rebuildLaunchServices: "arrow.triangle.2.circlepath"
        case .reindexSpotlight: "magnifyingglass"
        case .flushDNSCache: "network"
        case .thinTimeMachineSnapshots: "clock.arrow.circlepath"
        }
    }

    public var description: String {
        switch self {
        case .freeUpRAM:
            L10n.tr("清理非活动内存，为当前应用释放更多空间", "Purge inactive memory to give active apps more breathing room")
        case .freeUpPurgeableSpace:
            L10n.tr("通过精简低优先级本地快照回收可清除磁盘空间", "Reclaim purgeable disk space by thinning low-priority local snapshots")
        case .runMaintenanceScripts:
            L10n.tr("执行 macOS 内置的每日、每周和每月维护任务", "Execute macOS built-in daily, weekly, and monthly maintenance routines")
        case .verifyStartupDisk:
            L10n.tr("检查启动磁盘的文件系统完整性", "Check file system integrity of the boot disk")
        case .speedUpMail:
            L10n.tr("重建“邮件”数据库索引，以修复搜索和性能问题", "Reindex the Mail.app database to fix search and performance issues")
        case .rebuildLaunchServices:
            L10n.tr("修复 Finder 的文件类型与应用打开方式数据库", "Repair Finder's file-type-to-application mapping database")
        case .reindexSpotlight:
            L10n.tr("重建 Spotlight 搜索索引，提高搜索准确性", "Rebuild the Spotlight search index for improved search accuracy")
        case .flushDNSCache:
            L10n.tr("清除本地 DNS 缓存并强制重新解析", "Clear the local DNS cache and force fresh lookups")
        case .thinTimeMachineSnapshots:
            L10n.tr("缩减本地 Time Machine 快照以回收磁盘空间", "Reduce local Time Machine snapshot sizes to reclaim disk space")
        }
    }

    /// How much disruption to expect from running this task.
    ///
    /// `.safe` — runs and finishes; the user's experience doesn't change.
    /// `.advanced` — has side effects the user will notice for minutes/hours
    /// after the task itself "succeeds." Must require explicit consent
    /// before being run; must not be included in bulk "run all" operations.
    public enum Severity: Sendable {
        case safe
        case advanced
    }

    public var severity: Severity {
        switch self {
        // Read-only or trivially reversible — run on click.
        case .freeUpRAM,                // purge inactive memory
             .freeUpPurgeableSpace,     // deletes only files marked purgeable
             .verifyStartupDisk,        // read-only check
             .flushDNSCache,            // re-resolves in ms
             .runMaintenanceScripts:    // Apple-blessed periodic routines
            .safe

        // Real side effects — must show the user what to expect.
        case .speedUpMail,              // rebuilds Mail envelope index
             .rebuildLaunchServices,    // wipes app/file-type DB — hours of broken double-clicks
             .reindexSpotlight,         // wipes Spotlight index — search dies for hours
             .thinTimeMachineSnapshots: // deletes local TM snapshots
            .advanced
        }
    }

    /// Plain-English description of what the user will EXPERIENCE during
    /// and after this task runs. Shown in the confirmation modal before
    /// an advanced task is dispatched. Always written in the user's voice,
    /// never in implementation language.
    public var sideEffects: String {
        switch self {
        case .freeUpRAM:
            L10n.tr("曾被换出的应用回到前台时可能需要片刻恢复。", "Apps that had memory paged out may take a moment to come back to foreground.")
        case .freeUpPurgeableSpace:
            L10n.tr("仅移除 macOS 已标记可清理的 Time Machine 本地快照；不会删除你主动需要的内容。", "Time Machine local snapshots that macOS already flagged for cleanup are removed; nothing the user actively needs is deleted.")
        case .runMaintenanceScripts:
            L10n.tr("通常没有可见影响——这些脚本与 macOS 夜间自动运行的维护脚本相同。", "No visible effect — these are the same scripts macOS runs on its own overnight.")
        case .verifyStartupDisk:
            L10n.tr("会产生几分钟磁盘活动。该操作为只读，无论结果如何都不会更改磁盘内容。", "A few minutes of disk activity. Read-only — nothing on disk is changed regardless of the outcome.")
        case .speedUpMail:
            L10n.tr("“邮件”应用的搜索索引会从头重建。重建完成前，邮件搜索和未读数可能不准确（大型邮箱通常需 10–30 分钟）。", "Mail.app's search index is rebuilt from scratch. Mail search and unread counts will be wrong until the rebuild finishes (typically 10–30 minutes on a large mailbox).")
        case .rebuildLaunchServices:
            L10n.tr("macOS 的“哪类文件由哪个应用打开”数据库会被清除并重建。完成前（通常数小时），双击文件可能失败或打开错误应用，默认应用设置可能重置，Spotlight 启动应用也可能不可用。重启可加快恢复。", "macOS's database of \"which app opens which file type\" is erased and rebuilt. Until it finishes (often several hours), double-clicking files may fail or open the wrong app, default-app settings may reset, and launching apps via Spotlight may not work. A reboot speeds this up.")
        case .reindexSpotlight:
            L10n.tr("Spotlight 的整个搜索索引会被清除并重建。数小时内 Spotlight 搜索可能返回空结果（主目录越大耗时越久），系统搜索和智能文件夹也会受影响。", "Spotlight's entire search index is erased and rebuilt. Spotlight search will return empty results for several hours (longer for large home directories). System search and Smart Folders are affected too.")
        case .flushDNSCache:
            L10n.tr("浏览器和其他网络应用会在下次请求时重新解析主机名，影响通常只有毫秒级。", "Browsers and other network apps re-resolve hostnames on next request — milliseconds of impact.")
        case .thinTimeMachineSnapshots:
            L10n.tr("会删除本地 Time Machine 快照以释放空间。远程或备份盘上的快照不受影响，你仍可从 Time Machine 备份恢复。", "Local Time Machine snapshots are deleted to free disk space. Remote/backup-drive snapshots are unaffected; you can still restore from the Time Machine backup itself.")
        }
    }

    /// True for tasks whose command needs root (purge, periodic, …). The
    /// executor runs these via the standard macOS admin-auth prompt
    /// (`do shell script … with administrator privileges`) so they actually
    /// execute, instead of failing as a plain unprivileged `Process`.
    public var requiresAdmin: Bool {
        switch self {
        // Need root to actually run. `tmutil thinlocalsnapshots` and
        // `mdutil -E` both silently fail without it (issue #82: reindex was
        // wrongly unprivileged, which is the report's likely second error).
        case .freeUpRAM, .freeUpPurgeableSpace, .runMaintenanceScripts,
             .reindexSpotlight, .thinTimeMachineSnapshots:
            true
        // `diskutil verifyVolume /` runs read-only without root, so don't
        // burden the user with a password prompt for it (issue #82).
        case .verifyStartupDisk, .speedUpMail, .rebuildLaunchServices,
             .flushDNSCache:
            false
        }
    }

    /// The system executable + arguments that implement this task.
    /// Pure data — the MacClean target's `MaintenanceExecutor` uses this
    /// to invoke `Process`. Tasks that aren't a simple command (e.g., Mail
    /// reindex which deletes a specific file) return `nil`.
    public var systemCommand: (executable: String, arguments: [String])? {
        switch self {
        case .freeUpRAM:
            ("/usr/sbin/purge", [])
        case .freeUpPurgeableSpace:
            // Thin low-urgency (1) local snapshots to actually reclaim
            // purgeable space. The old `diskutil apfs listSnapshots /` only
            // listed them and freed nothing (issue #82). Aggressive thinning
            // lives in `thinTimeMachineSnapshots` (urgency 4).
            ("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "1"])
        case .runMaintenanceScripts:
            ("/usr/sbin/periodic", ["daily", "weekly", "monthly"])
        case .verifyStartupDisk:
            ("/usr/sbin/diskutil", ["verifyVolume", "/"])
        case .speedUpMail:
            nil
        case .rebuildLaunchServices:
            ("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
             ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"])
        case .reindexSpotlight:
            ("/usr/bin/mdutil", ["-E", "/"])
        case .flushDNSCache:
            ("/usr/bin/dscacheutil", ["-flushcache"])
        case .thinTimeMachineSnapshots:
            ("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "4"])
        }
    }
}
