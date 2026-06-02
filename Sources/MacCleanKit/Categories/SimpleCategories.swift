import Foundation

// MARK: - Simple data-only categories
//
// Each of these declares *what* to scan via a `[ScanTarget]`. They contain no
// system interaction and are exhaustively testable from MacCleanKit tests.
// The actual scanning happens in `TargetedScanner` (in the MacClean target).

public struct UserCacheCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.userCaches
    public var targets: [ScanTarget] {
        [
            ScanTarget(
                path: MCConstants.userCaches,
                recursive: true,
                excludePatterns: ["com.spotify.client", "org.gradle"]
            ),
        ]
    }
}

public struct SystemCacheCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.systemCaches
    public var targets: [ScanTarget] {
        [ScanTarget(path: MCConstants.systemCaches, recursive: true)]
    }
}

public struct UserLogCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.userLogs
    public var targets: [ScanTarget] {
        [
            ScanTarget(
                path: MCConstants.userLogs,
                recursive: true,
                fileExtensions: ["log", "txt", "crash", "diag", "ips"]
            ),
        ]
    }
}

public struct SystemLogCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.systemLogs
    public var targets: [ScanTarget] {
        [
            ScanTarget(
                path: MCConstants.systemLogs,
                recursive: true,
                fileExtensions: ["log", "txt", "crash", "diag"]
            ),
            ScanTarget(
                path: MCConstants.varLog,
                recursive: true,
                fileExtensions: ["log", "gz"]
            ),
        ]
    }
}

public struct LanguageFilesCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.languageFiles
    public var targets: [ScanTarget] {
        [
            ScanTarget(
                path: URL(filePath: "/Applications"),
                recursive: true,
                fileExtensions: ["lproj"],
                excludePatterns: Array(LanguagePreferences.effectivePreserved())
            ),
        ]
    }
}

public struct DocumentVersionsCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.documentVersions
    public var targets: [ScanTarget] {
        [
            ScanTarget(
                path: MCConstants.documentVersions,
                recursive: true,
                minAge: 14400 // older than 4 hours
            ),
        ]
    }
}

public struct BrokenDownloadsCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.brokenDownloads
    public var targets: [ScanTarget] {
        [
            ScanTarget(
                path: MCConstants.downloads,
                recursive: false,
                fileExtensions: ["download", "crdownload", "part", "partial"]
            ),
        ]
    }
}

public struct IOSDeviceBackupsCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.iosDeviceBackups
    public var targets: [ScanTarget] {
        [
            ScanTarget(
                path: MCConstants.mobileBackups,
                recursive: false,
                minAge: 30 * 24 * 3600 // older than 30 days
            ),
        ]
    }
}

public struct OldUpdatesCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.oldUpdates
    public var targets: [ScanTarget] {
        [
            ScanTarget(
                path: MCConstants.userAppSupport,
                recursive: true,
                maxDepth: 3,
                fileExtensions: ["pkg", "mpkg"],
                minAge: 7 * 24 * 3600 // older than 7 days
            ),
        ]
    }
}

public struct UnusedDiskImagesCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.unusedDiskImages
    public var targets: [ScanTarget] {
        [
            ScanTarget(
                path: MCConstants.downloads,
                recursive: false,
                fileExtensions: ["dmg", "iso", "sparseimage"],
                minAge: 7 * 24 * 3600 // older than 7 days
            ),
        ]
    }
}

public struct XcodeJunkCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.xcodeJunk
    public var targets: [ScanTarget] {
        [
            ScanTarget(path: MCConstants.xcodeDerivedData, recursive: false),
            ScanTarget(path: MCConstants.xcodeArchives, recursive: false),
            ScanTarget(path: MCConstants.xcodeDeviceSupport, recursive: false),
            ScanTarget(path: MCConstants.coreSimulator, recursive: false),
            ScanTarget(path: MCConstants.xcodePreviews, recursive: false),
        ]
    }
}

public struct IncompleteDownloadsCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.incompleteDownloads
    public var targets: [ScanTarget] {
        [
            ScanTarget(
                path: MCConstants.downloads,
                recursive: false,
                fileExtensions: ["download", "crdownload", "part", "partial", "tmp"]
            ),
            ScanTarget(
                path: FileManager.default.temporaryDirectory,
                recursive: true,
                maxDepth: 2,
                minAge: 24 * 3600
            ),
        ]
    }
}
