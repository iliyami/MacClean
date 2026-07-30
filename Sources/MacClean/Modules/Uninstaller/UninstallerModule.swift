import Foundation
import AppKit
import MacCleanKit

public struct UninstallerModule: ScanModule {
    public let id = "uninstaller"
    public var name: String { L10n.tr("卸载器", "Uninstaller", "Удаление приложений") }
    public let category = ModuleCategory.applications

    public init() {}

    public func scan() async -> [ScanResult] {
        // The uninstaller doesn't produce traditional scan results.
        // It provides an app list with associated files.
        []
    }
}

// MARK: - App Discovery

public actor AppDiscovery {
    private let resourceKeys: [URLResourceKey] = [
        .fileSizeKey, .totalFileAllocatedSizeKey, .isApplicationKey,
        .contentModificationDateKey,
    ]

    public init() {}

    public func discoverApps() -> [AppInfo] {
        var apps: [AppInfo] = []
        var seen = Set<String>()

        let appDirs = [
            URL(filePath: "/Applications"),
            MCConstants.home.appending(path: "Applications"),
        ]

        for dir in appDirs {
            for appURL in Self.appBundles(in: dir) {
                let path = appURL.path(percentEncoded: false)
                guard seen.insert(path).inserted else { continue }
                if let info = appInfo(from: appURL) {
                    apps.append(info)
                }
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// All `.app` bundles under `dir`, including those nested in subfolders
    /// (e.g. `/Applications/Adobe/Photoshop.app`, `/Applications/Utilities/`),
    /// which the old top-level-only scan missed (issue #120).
    ///
    /// `.skipsPackageDescendants` stops the walk at each bundle so we never list
    /// helper apps buried inside another app (`…/Contents/Library/…/Helper.app`),
    /// and `maxDepth` bounds the recursion so a huge non-app folder can't stall
    /// discovery. Real installs nest an app one or two folders deep at most.
    static func appBundles(in dir: URL, maxDepth: Int = 4,
                           fileManager: FileManager = .default) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if enumerator.level >= maxDepth { enumerator.skipDescendants() }
            if url.pathExtension == "app" {
                found.append(url)
                enumerator.skipDescendants()   // never recurse into a bundle
            }
        }
        return found
    }

    private func appInfo(from url: URL) -> AppInfo? {
        let infoPlistURL = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
        let name = plist["CFBundleName"] as? String
            ?? plist["CFBundleDisplayName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        let version = plist["CFBundleShortVersionString"] as? String

        let isApple = bundleID.hasPrefix("com.apple.")
        let size = directorySize(url)

        return AppInfo(
            bundleIdentifier: bundleID,
            name: name,
            path: url,
            version: version,
            size: size,
            lastOpened: lastOpenedDate(url),
            isAppleApp: isApple
        )
    }

    private func lastOpenedDate(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentAccessDateKey])
        return values?.contentAccessDate
    }

    private func directorySize(_ url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += UInt64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

// MARK: - App Path Finder (system-side wrapper around MacCleanKit.AppMatching)

public struct AppPathFinder: Sendable {
    public typealias MatchLevel = AppMatching.MatchLevel

    public let maxLevel: MatchLevel

    // Default stops at .versionStripped: the .companyName level matches the bare
    // vendor token and would flag sibling apps from the same vendor (issue #98).
    public init(maxLevel: MatchLevel = .versionStripped) {
        self.maxLevel = maxLevel
    }

    public func findAssociatedFiles(for app: AppInfo) -> [FileItem] {
        let patterns = AppMatching.generatePatterns(for: app, maxLevel: maxLevel)
        var found: [FileItem] = []
        let fm = FileManager.default

        for subdir in AppMatching.librarySubdirectories {
            let dirURL = MCConstants.userLibrary.appending(path: subdir)
            guard let contents = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey]
            ) else { continue }

            for itemURL in contents {
                if AppMatching.filenameMatches(itemURL.lastPathComponent, patterns: patterns) {
                    if let fileItem = makeFileItem(from: itemURL) {
                        found.append(fileItem)
                    }
                }
            }
        }

        // Also check system Library for launch daemons
        let systemDirs = [MCConstants.systemLaunchDaemons, MCConstants.systemLaunchAgents]
        for dirURL in systemDirs {
            guard let contents = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            else { continue }

            for itemURL in contents where itemURL.pathExtension == "plist" {
                if AppMatching.filenameMatches(itemURL.lastPathComponent, patterns: patterns) {
                    if let fileItem = makeFileItem(from: itemURL) {
                        found.append(fileItem)
                    }
                }
            }
        }

        return found
    }

    private func makeFileItem(from url: URL) -> FileItem? {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey,
            .contentModificationDateKey, .nameKey,
        ])
        let isDir = values?.isDirectory ?? false
        var size = UInt64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)

        if isDir {
            size = directorySize(url)
        }

        return FileItem(
            url: url,
            name: values?.name ?? url.lastPathComponent,
            size: size,
            allocatedSize: size,
            isDirectory: isDir,
            modificationDate: values?.contentModificationDate
        )
    }

    private func directorySize(_ url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: []
        ) else { return 0 }
        var total: UInt64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let v = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += UInt64(v?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
