import Foundation

public enum MCConstants {
    public static let appName = "Mac Clean"
    public static let bundleIdentifier = "com.macclean.app"
    public static let helperBundleIdentifier = "com.macclean.helper"
    public static let menuBundleIdentifier = "com.macclean.menu"
    /// Per-CHUNK safety net enforced by SafetyGuard.validateDeletion.
    /// CleaningEngine internally chunks large selections into batches
    /// no larger than `cleanChunkSize` (5,000), so this cap is effectively
    /// a defense-in-depth boundary in case a future refactor accidentally
    /// bypasses the chunking. Total selection size is bounded by
    /// `maxTotalItemsPerCleanOperation` instead.
    public static let maxFilesPerOperation = 10_000

    /// CleaningEngine breaks large selections into chunks of this size so
    /// per-chunk SafetyGuard validation never trips on legitimate-but-large
    /// cleanups (Chrome cache alone often has 20k+ entries). 5k leaves
    /// 50% headroom under `maxFilesPerOperation`.
    public static let cleanChunkSize = 5_000

    /// Hard upper bound on a single Clean operation, regardless of
    /// chunking. Catches genuinely pathological scan results (e.g., a
    /// buggy module returning every file on disk) while leaving plenty
    /// of room for real cache cleanups. Set well above the largest
    /// legitimate selection observed in the wild (~200k).
    public static let maxTotalItemsPerCleanOperation = 500_000

    /// Selections above this size show a confirmation modal before Clean
    /// fires. Catches the "I just clicked Clean and now my Mac is going
    /// to do something for 5 minutes — was that intentional?" surprise.
    /// 50k = ~5MB of cache items on average; comfortably covers normal
    /// usage but flags the genuinely-big cleanups.
    public static let cleanConfirmationThreshold = 50_000
    public static let scanThrottleInterval: TimeInterval = 0.05 // 50ms UI update throttle

    // MARK: - Protected Paths (never touch these)

    public static let protectedPaths: Set<String> = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/Library/Apple",
        "/private/var/db",
    ]

    public static let protectedApps: Set<String> = [
        "com.apple.finder",
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.Terminal",
        "com.apple.systempreferences",
        "com.apple.ActivityMonitor",
        "com.apple.Console",
        "com.apple.DiskUtility",
        "com.apple.dt.Xcode",
        "com.apple.AppStore",
        "com.apple.iCal",
        "com.apple.AddressBook",
        "com.apple.Preview",
        "com.apple.TextEdit",
        "com.apple.calculator",
        "com.apple.Dictionary",
        "com.apple.Maps",
        "com.apple.Notes",
        "com.apple.reminders",
        "com.apple.Stickies",
        "com.apple.VoiceMemos",
        "com.apple.stocks",
        "com.apple.weather",
        "com.apple.Passwords",
        "com.apple.FaceTime",
        "com.apple.MobileSMS",
        "com.apple.Photos",
        "com.apple.Music",
    ]

    // MARK: - User Home Library Subdirectories

    public static let home = FileManager.default.homeDirectoryForCurrentUser

    public static let userLibrary = home.appending(path: "Library")
    public static let userCaches = userLibrary.appending(path: "Caches")
    public static let userLogs = userLibrary.appending(path: "Logs")
    public static let userPreferences = userLibrary.appending(path: "Preferences")
    public static let userAppSupport = userLibrary.appending(path: "Application Support")
    public static let userContainers = userLibrary.appending(path: "Containers")
    public static let userGroupContainers = userLibrary.appending(path: "Group Containers")
    public static let userLaunchAgents = userLibrary.appending(path: "LaunchAgents")
    public static let userSavedAppState = userLibrary.appending(path: "Saved Application State")
    public static let userCookies = userLibrary.appending(path: "Cookies")
    public static let userHTTPStorages = userLibrary.appending(path: "HTTPStorages")
    public static let userAppScripts = userLibrary.appending(path: "Application Scripts")
    public static let userWebKit = userLibrary.appending(path: "WebKit")

    // MARK: - System Library Directories

    public static let systemLibrary = URL(filePath: "/Library")
    public static let systemCaches = systemLibrary.appending(path: "Caches")
    public static let systemLogs = systemLibrary.appending(path: "Logs")
    public static let systemLaunchAgents = systemLibrary.appending(path: "LaunchAgents")
    public static let systemLaunchDaemons = systemLibrary.appending(path: "LaunchDaemons")
    public static let varLog = URL(filePath: "/var/log")

    // MARK: - Special Directories

    public static let userTrash = home.appending(path: ".Trash")
    public static let downloads = home.appending(path: "Downloads")
    public static let documentVersions = home.appending(path: ".DocumentRevisions-V100")
    public static let mobileBackups = userAppSupport.appending(path: "MobileSync/Backup")

    // MARK: - Xcode Directories

    public static let xcodeDerivedData = userLibrary.appending(path: "Developer/Xcode/DerivedData")
    public static let xcodeArchives = userLibrary.appending(path: "Developer/Xcode/Archives")
    public static let xcodeDeviceSupport = userLibrary.appending(path: "Developer/Xcode/iOS DeviceSupport")
    public static let coreSimulator = userLibrary.appending(path: "Developer/CoreSimulator")
    public static let xcodePreviews = userLibrary.appending(path: "Developer/Xcode/UserData/Previews")

    // MARK: - Browser Directories

    public static let safariCache = userLibrary.appending(path: "Caches/com.apple.Safari")
    public static let chromeDefault = userAppSupport.appending(path: "Google/Chrome/Default")
    public static let chromeCache = userCaches.appending(path: "Google/Chrome")
    public static let firefoxProfiles = userAppSupport.appending(path: "Firefox/Profiles")
    public static let firefoxCache = userCaches.appending(path: "Firefox/Profiles")

    // MARK: - Mail Directories

    public static let mailData = userLibrary.appending(path: "Mail")
    public static let mailDownloads = userLibrary.appending(path: "Mail Downloads")
    public static let mailContainerDownloads = userContainers
        .appending(path: "com.apple.mail/Data/Library/Mail Downloads")

    // MARK: - Dev Tool Caches

    public static let homebrewCache = userCaches.appending(path: "Homebrew")
    public static let npmCache = userCaches.appending(path: "npm")
    public static let pipCache = userCaches.appending(path: "pip")
    public static let cargoRegistry = home.appending(path: ".cargo/registry")

    // MARK: - Preserved Languages

    public static let preservedLanguages: Set<String> = [
        "en.lproj", "Base.lproj", "en_US.lproj", "en_GB.lproj",
    ]

    // MARK: - Log File Path

    public static let operationLogDir = userLogs.appending(path: "MacClean")
    public static let operationLogFile = operationLogDir.appending(path: "operations.log")

    // MARK: - App version
    //
    // Bumped alongside the VERSION file at the repo root. CI verifies the
    // two stay in sync (scripts/check-version-sync.sh runs in ci.yml) —
    // a mismatch fails the build loudly. Build-time codegen via a SwiftPM
    // plugin was tried (commit history) but doesn't work under multi-arch
    // `swift build --arch arm64 --arch x86_64` because xcbuild doesn't
    // execute plugins.
    public static let appVersion = "1.7.0"
}
