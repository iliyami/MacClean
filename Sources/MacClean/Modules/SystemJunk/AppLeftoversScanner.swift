import Foundation
import MacCleanKit

/// Finds leftover support files belonging to apps that are no longer installed.
///
/// Only scans the directories `SafetyGuard.isSafeForOrphanDeletion` allows
/// (caches, logs, HTTP storages, saved app state, WebKit) — never preferences,
/// containers, or keychains. The orphan decision is pure (`OrphanedAppFiles`);
/// this type only gathers the inputs: the set of installed bundle ids and the
/// top-level entries in each safe directory.
public enum AppLeftoversScanner {

    /// Standard locations apps are installed. Reading each bundle's
    /// CFBundleIdentifier gives the "installed" set the detector checks against.
    private static let appSearchRoots: [URL] = [
        URL(filePath: "/Applications"),
        URL(filePath: "/Applications/Utilities"),
        URL(filePath: "/System/Applications"),
        URL(filePath: "/System/Applications/Utilities"),
        MCConstants.home.appending(path: "Applications"),
    ]

    /// The safe-to-clean Library roots, each scanned at its top level for
    /// bundle-id-named entries. Mirrors `SafetyGuard.isSafeForOrphanDeletion`.
    private static var safeRoots: [URL] {
        [
            MCConstants.userCaches,
            MCConstants.userLogs,
            MCConstants.userHTTPStorages,
            MCConstants.userSavedAppState,
            MCConstants.userWebKit,
        ]
    }

    public static func scan(
        roots: [URL]? = nil,
        installedBundleIDs: Set<String>? = nil
    ) -> [FileItem] {
        let installed = installedBundleIDs ?? Self.installedBundleIDs()
        // No installed apps found at all → almost certainly an enumeration
        // failure, not an empty Mac. Refuse to flag everything as orphaned.
        guard !installed.isEmpty else { return [] }

        let fm = FileManager.default
        var items: [FileItem] = []
        var seenURLs: Set<URL> = []

        for root in roots ?? safeRoots {
            guard let entries = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                // The entry name is the candidate bundle id (e.g.
                // Caches/com.acme.App, Saved Application State/com.acme.App.savedState).
                let candidate = entry.lastPathComponent
                guard OrphanedAppFiles.isOrphan(bundleID: candidate, installedBundleIDs: installed)
                else { continue }
                guard seenURLs.insert(entry.standardizedFileURL).inserted else { continue }

                let size = directorySize(at: entry)
                guard size > 0 else { continue }
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? true
                items.append(FileItem(
                    url: entry,
                    name: candidate,
                    size: size,
                    allocatedSize: size,
                    isDirectory: isDir
                ))
            }
        }

        return items.sorted { $0.size > $1.size }
    }

    /// Lowercased CFBundleIdentifiers of every app found under the standard
    /// install roots.
    static func installedBundleIDs() -> Set<String> {
        let fm = FileManager.default
        var ids: Set<String> = []
        for root in appSearchRoots {
            guard let apps = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for app in apps where app.pathExtension == "app" {
                let infoURL = app.appending(path: "Contents/Info.plist")
                guard let data = try? Data(contentsOf: infoURL),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let id = plist["CFBundleIdentifier"] as? String
                else { continue }
                ids.insert(id.lowercased())
            }
        }
        return ids
    }

    /// Recursive byte size of a file or directory. Bounded by the entry's own
    /// subtree; used only to show the user how much each leftover reclaims.
    private static func directorySize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        var values = try? url.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        if values?.isDirectory != true {
            return UInt64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        var total: UInt64 = 0
        if let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
            options: []
        ) {
            for case let fileURL as URL in enumerator {
                values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                total += UInt64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
