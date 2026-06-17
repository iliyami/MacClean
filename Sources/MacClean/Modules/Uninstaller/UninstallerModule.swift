import Foundation
import AppKit
import MacCleanKit

public struct UninstallerModule: ScanModule {
    public let id = "uninstaller"
    public var name: String { L10n.tr("卸载器", "Uninstaller") }
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
        let fm = FileManager.default

        let appDirs = [
            URL(filePath: "/Applications"),
            MCConstants.home.appending(path: "Applications"),
        ]

        for dir in appDirs {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: resourceKeys
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                if let info = appInfo(from: url) {
                    apps.append(info)
                }
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    public init(maxLevel: MatchLevel = .companyName) {
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
