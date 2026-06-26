import Foundation
import AppKit

public enum LaunchServicesError: LocalizedError, Sendable {
    case backupFailed(Error)
    case restoreFailed(Error)
    case deleteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .backupFailed(let e): return "Backup failed: \(e.localizedDescription)"
        case .restoreFailed(let e): return "Restore failed: \(e.localizedDescription)"
        case .deleteFailed(let msg): return "Delete failed: \(msg)"
        }
    }
}

public final class LaunchServicesService: @unchecked Sendable {
    public static let shared = LaunchServicesService()

    private let plistPath: String
    private let backupDir: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        plistPath = "\(home)/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
        backupDir = URL(fileURLWithPath: home)
            .appending(path: "Library/Application Support/MacClean/LaunchServicesBackups")
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
    }

    /// Testing override: inject a custom plist path so tests don't touch the real file.
    internal init(plistPath: String) {
        self.plistPath = plistPath
        backupDir = URL(fileURLWithPath: plistPath).deletingLastPathComponent()
            .appending(path: ".launchservices-backups")
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
    }

    // MARK: - Read

    public func loadHandlers() -> [HandlerEntry] {
        guard FileManager.default.fileExists(atPath: plistPath),
              let plistData = NSDictionary(contentsOfFile: plistPath),
              let handlers = plistData["LSHandlers"] as? [[String: Any]] else {
            return []
        }
        return handlers.compactMap { dict -> HandlerEntry? in
            var entry = HandlerEntry(id: UUID())
            entry.contentType = dict["LSHandlerContentType"] as? String
            entry.contentTag = dict["LSHandlerContentTag"] as? String
            entry.contentTagClass = dict["LSHandlerContentTagClass"] as? String
            entry.roleAll = dict["LSHandlerRoleAll"] as? String
            entry.urlScheme = dict["LSHandlerURLScheme"] as? String
            if let ts = dict["LSHandlerModificationDate"] as? Double {
                entry.modificationDate = Date(timeIntervalSince1970: ts)
            }
            if entry.roleAll == nil && entry.urlScheme == nil { return nil }
            return entry
        }
    }

    // MARK: - Safe Delete (in-place with backup)

    /// Delete a single entry from LSHandlers.  Before mutating it backs up the
    /// current plist so every change is reversible.
    public func deleteHandler(_ entry: HandlerEntry) throws {
        // 1. Backup first — always.
        try backup()

        // 2. Read as mutable dictionary so unknown keys are preserved.
        guard let plistData = NSMutableDictionary(contentsOfFile: plistPath) else {
            throw LaunchServicesError.deleteFailed("Cannot read plist")
        }

        if let handlers = plistData["LSHandlers"] as? NSMutableArray {
            let indices = (0 ..< handlers.count)
                .filter { i in
                    guard let dict = handlers[i] as? [String: Any] else { return false }
                    return entryMatches(entry, dict)
                }
                .reversed()
            for idx in indices {
                handlers.removeObject(at: idx)
            }
        }

        guard plistData.write(toFile: plistPath, atomically: true) else {
            throw LaunchServicesError.deleteFailed("Cannot write plist")
        }
    }

    // MARK: - Backup / Restore

    /// Snapshot the current plist to the backup directory.
    public func backup() throws {
        let src = URL(fileURLWithPath: plistPath)
        guard FileManager.default.fileExists(atPath: plistPath) else { return }
        let fm = ISO8601DateFormatter()
        fm.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = fm.string(from: Date())
            // Replace colons with underscores so the name is filesystem-safe
            // and trivially reversible for display.
            .replacingOccurrences(of: ":", with: "_")
        var dst = backupDir.appending(path: "launchservices-\(ts).plist")
        // If two backups happen in the same fractional second, append a uniquifier.
        if FileManager.default.fileExists(atPath: dst.path) {
            dst = backupDir.appending(path: "launchservices-\(ts)-\(UUID().uuidString.prefix(8)).plist")
        }
        do {
            try FileManager.default.copyItem(at: src, to: dst)
        } catch {
            throw LaunchServicesError.backupFailed(error)
        }
    }

    /// List available backups newest-first (sorted by filename timestamp).
    public func listBackups() -> [URL] {
        guard let contents = try? FileManager.default
            .contentsOfDirectory(at: backupDir,
                                includingPropertiesForKeys: nil)
        else { return [] }
        return contents
            .filter { $0.pathExtension == "plist" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Restore a specific backup to the live plist path, replacing the current.
    public func restoreBackup(from url: URL) throws {
        let dst = URL(fileURLWithPath: plistPath)
        do {
            // Remove current, then copy backup in its place.
            if FileManager.default.fileExists(atPath: plistPath) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: url, to: dst)
        } catch {
            throw LaunchServicesError.restoreFailed(error)
        }
    }

    // MARK: - Helpers

    /// Check whether a plist dictionary matches a HandlerEntry.
    private func entryMatches(_ entry: HandlerEntry, _ dict: [String: Any]) -> Bool {
        // Match on URL scheme when present.
        if let scheme = entry.urlScheme {
            return dict["LSHandlerURLScheme"] as? String == scheme
        }
        // Match on content-type + roleAll when present.
        if let ct = entry.contentType {
            return dict["LSHandlerContentType"] as? String == ct
                && dict["LSHandlerRoleAll"] as? String == entry.roleAll
        }
        // Fallback: match on content-tag + tag-class + roleAll.
        if let tag = entry.contentTag {
            return dict["LSHandlerContentTag"] as? String == tag
                && dict["LSHandlerContentTagClass"] as? String == entry.contentTagClass
                && dict["LSHandlerRoleAll"] as? String == entry.roleAll
        }
        return false
    }

    // MARK: - App Info

    public func getAppInfo(for bundleId: String?) -> (name: String, icon: NSImage)? {
        guard let bid = bundleId, !bid.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        return (name, icon)
    }

    public func getURLSchemeAppInfo(for scheme: String?) -> (name: String, icon: NSImage)? {
        guard let s = scheme, !s.isEmpty,
              let url = URL(string: "\(s)://test"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: appURL.path)
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 32, height: 32)
        return (name, icon)
    }
}
