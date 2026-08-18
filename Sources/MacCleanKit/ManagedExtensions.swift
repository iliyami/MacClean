import Foundation

/// A third-party preference pane, Internet Plug-In, or Safari-family extension
/// (issue #53). Paths are the source of truth; names come from Info.plist.
public struct ManagedExtension: Hashable, Sendable, Identifiable {
    public var id: String { path.path(percentEncoded: false) }

    public let kind: ManagedExtensionKind
    public let name: String
    public let bundleIdentifier: String
    public let path: URL
    public let hostAppPath: URL?
    public let domain: ManagedExtensionDomain
    public let isApple: Bool
    public let election: ManagedExtensionElection
    public let safariPointIdentifier: String?

    public init(
        kind: ManagedExtensionKind,
        name: String,
        bundleIdentifier: String,
        path: URL,
        hostAppPath: URL?,
        domain: ManagedExtensionDomain,
        isApple: Bool,
        election: ManagedExtensionElection,
        safariPointIdentifier: String?
    ) {
        self.kind = kind
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.hostAppPath = hostAppPath
        self.domain = domain
        self.isApple = isApple
        self.election = election
        self.safariPointIdentifier = safariPointIdentifier
    }

    public func withElection(_ election: ManagedExtensionElection) -> ManagedExtension {
        ManagedExtension(
            kind: kind,
            name: name,
            bundleIdentifier: bundleIdentifier,
            path: path,
            hostAppPath: hostAppPath,
            domain: domain,
            isApple: isApple,
            election: election,
            safariPointIdentifier: safariPointIdentifier
        )
    }
}

public enum ManagedExtensionKind: String, Sendable, Hashable, CaseIterable {
    case preferencePane
    case internetPlugin
    case safariExtension
}

public enum ManagedExtensionDomain: String, Sendable, Hashable {
    case user
    case local
}

public enum ManagedExtensionElection: String, Sendable, Hashable {
    case enabled
    case disabled
    case unknown
}

public enum ManagedExtensionRemoval: String, Sendable, Hashable {
    case trash
    case revealInFinder
    case none
}

public struct PluginKitRecord: Hashable, Sendable {
    public let election: ManagedExtensionElection
    public let bundleIdentifier: String
    public let path: String?
    public let sdk: String?

    public init(
        election: ManagedExtensionElection,
        bundleIdentifier: String,
        path: String?,
        sdk: String?
    ) {
        self.election = election
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.sdk = sdk
    }
}

/// Path and vendor rules. No FileManager — callers pass already-resolved paths.
public enum ManagedExtensionPolicy {

    public static let safariExtensionPoints: Set<String> = [
        "com.apple.Safari.extension",
        "com.apple.Safari.content-blocker",
        "com.apple.Safari.web-extension",
    ]

    public static let safariSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Safari-Settings")!

    public static let userRemovalSubdirectories = [
        "Library/PreferencePanes",
        "Library/Internet Plug-Ins",
        "Library/Safari/Extensions",
    ]

    public static let computerRevealPrefixes = [
        "/Library/PreferencePanes",
        "/Library/Internet Plug-Ins",
    ]

    public static func isAppleVendor(bundleID: String, resolvedPath: String) -> Bool {
        if bundleID.lowercased().hasPrefix("com.apple.") { return true }
        if resolvedPath == "/System" || resolvedPath.hasPrefix("/System/") { return true }
        if resolvedPath == "/Library/Apple" || resolvedPath.hasPrefix("/Library/Apple/") { return true }
        return false
    }

    public static func isInsideAppBundleContents(_ path: String) -> Bool {
        path.range(of: ".app/Contents/", options: .caseInsensitive) != nil
    }

    public static func hostAppURL(forAppex url: URL) -> URL? {
        var current = url
        for _ in 0..<12 {
            if current.pathExtension.lowercased() == "app" {
                return URL(filePath: standardizedPath(current))
            }
            let parent = current.deletingLastPathComponent()
            if standardizedPath(parent) == standardizedPath(current) {
                return nil
            }
            current = parent
        }
        return nil
    }

    public static func standardizedPath(_ url: URL) -> String {
        standardizedPath(url.path(percentEncoded: false))
    }

    public static func standardizedPath(_ path: String) -> String {
        if path.count > 1, path.hasSuffix("/") {
            return String(path.dropLast())
        }
        return path
    }

    public static func domain(of path: String, home: String) -> ManagedExtensionDomain? {
        let homePrefix = home.hasSuffix("/") ? String(home.dropLast()) : home
        let homeLibrary = homePrefix + "/Library"
        if path == homeLibrary || path.hasPrefix(homeLibrary + "/") { return .user }
        if path == "/Library" || path.hasPrefix("/Library/") { return .local }
        return nil
    }

    public static func isAllowlistedUserRemovalPath(_ path: String, home: String) -> Bool {
        let homePrefix = home.hasSuffix("/") ? String(home.dropLast()) : home
        for subdir in userRemovalSubdirectories {
            let prefix = homePrefix + "/" + subdir
            if path == prefix || path.hasPrefix(prefix + "/") { return true }
        }
        return false
    }

    public static func isComputerRevealPath(_ path: String) -> Bool {
        computerRevealPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    public static func isProtectedResolvedPath(_ path: String) -> Bool {
        let protected = ["/System", "/usr", "/bin", "/sbin", "/Library/Apple"]
        return protected.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    public static func removal(
        for item: ManagedExtension,
        resolvedPath: String,
        home: String
    ) -> ManagedExtensionRemoval {
        let original = standardizedPath(item.path)
        let resolved = standardizedPath(resolvedPath)
        if item.isApple { return .none }
        if isAppleVendor(bundleID: item.bundleIdentifier, resolvedPath: resolved) {
            return .none
        }
        if isInsideAppBundleContents(original) || isInsideAppBundleContents(resolved) {
            return .none
        }
        if isProtectedResolvedPath(resolved) { return .none }
        // Symlink trap: only the resolved path may be trashed.
        if isAllowlistedUserRemovalPath(resolved, home: home) {
            return .trash
        }
        if isComputerRevealPath(resolved) || isComputerRevealPath(original) {
            return .revealInFinder
        }
        return .none
    }

    public static func trashURLs(
        from items: [ManagedExtension],
        home: String,
        resolvedPath: (URL) -> String
    ) -> [URL] {
        items.compactMap { item in
            let resolved = resolvedPath(item.path)
            guard removal(for: item, resolvedPath: resolved, home: home) == .trash else {
                return nil
            }
            return item.path
        }
    }
}

/// Builds `ManagedExtension` rows from Info.plist dictionaries. No I/O.
public enum ManagedExtensionCatalog {

    public static func item(
        kind: ManagedExtensionKind,
        url: URL,
        plist: [String: Any]?,
        resolvedPath: String,
        home: String
    ) -> ManagedExtension? {
        let bundleID = (plist?["CFBundleIdentifier"] as? String) ?? ""
        if ManagedExtensionPolicy.isAppleVendor(bundleID: bundleID, resolvedPath: resolvedPath) {
            return nil
        }

        let point = safariPointIdentifier(from: plist)
        if kind == .safariExtension, url.pathExtension.lowercased() == "appex" {
            guard let point, ManagedExtensionPolicy.safariExtensionPoints.contains(point) else {
                return nil
            }
        }

        let name = displayName(plist: plist, url: url)
        let host = kind == .safariExtension && url.pathExtension.lowercased() == "appex"
            ? ManagedExtensionPolicy.hostAppURL(forAppex: url)
            : nil
        let domain = ManagedExtensionPolicy.domain(of: resolvedPath, home: home)
            ?? ManagedExtensionPolicy.domain(of: url.path(percentEncoded: false), home: home)
            ?? .local

        return ManagedExtension(
            kind: kind,
            name: name,
            bundleIdentifier: bundleID,
            path: url,
            hostAppPath: host,
            domain: domain,
            isApple: false,
            election: .unknown,
            safariPointIdentifier: point
        )
    }

    public static func mergeElections(
        _ items: [ManagedExtension],
        pluginkit: [PluginKitRecord]
    ) -> [ManagedExtension] {
        items.map { item in
            let path = item.path.path(percentEncoded: false)
            if let match = pluginkit.first(where: { record in
                if !item.bundleIdentifier.isEmpty, record.bundleIdentifier == item.bundleIdentifier {
                    return true
                }
                if let recordPath = record.path, recordPath == path { return true }
                return false
            }) {
                return item.withElection(match.election)
            }
            return item
        }
    }

    public static func displayName(plist: [String: Any]?, url: URL) -> String {
        if let value = plist?["CFBundleDisplayName"] as? String, !value.isEmpty { return value }
        if let value = plist?["CFBundleName"] as? String, !value.isEmpty { return value }
        if let value = plist?["NSPrefPaneIconLabel"] as? String, !value.isEmpty { return value }
        return url.deletingPathExtension().lastPathComponent
    }

    public static func safariPointIdentifier(from plist: [String: Any]?) -> String? {
        guard let extensionInfo = plist?["NSExtension"] as? [String: Any],
              let point = extensionInfo["NSExtensionPointIdentifier"] as? String,
              !point.isEmpty else { return nil }
        return point
    }
}

/// Parses `pluginkit -m -v` stdout. No Process — fixtures in tests.
public enum PluginKitParser {

    public static func records(from output: String) -> [PluginKitRecord] {
        var records: [PluginKitRecord] = []
        var pendingElection: ManagedExtensionElection?
        var pendingID = ""
        var pendingPath: String?
        var pendingSDK: String?

        func flush() {
            guard let election = pendingElection, !pendingID.isEmpty else {
                pendingElection = nil
                pendingID = ""
                pendingPath = nil
                pendingSDK = nil
                return
            }
            records.append(PluginKitRecord(
                election: election,
                bundleIdentifier: pendingID,
                path: pendingPath,
                sdk: pendingSDK
            ))
            pendingElection = nil
            pendingID = ""
            pendingPath = nil
            pendingSDK = nil
        }

        for rawLine in output.split(whereSeparator: \.isNewline).map(String.init) {
            if let header = electionHeader(rawLine) {
                flush()
                pendingElection = header.election
                pendingID = header.bundleID
                continue
            }
            guard pendingElection != nil else { continue }
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if let path = value(after: "Path =", in: trimmed) {
                pendingPath = path
            } else if let sdk = value(after: "SDK =", in: trimmed) {
                pendingSDK = sdk
            }
        }
        flush()
        return records
    }

    private static func electionHeader(_ line: String) -> (election: ManagedExtensionElection, bundleID: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, "+-?".contains(first) else { return nil }
        let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        let identifier = rest.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? rest
        let bundleID = String(identifier.prefix { $0 != "(" })
        guard !bundleID.isEmpty else { return nil }
        let election: ManagedExtensionElection
        switch first {
        case "+": election = .enabled
        case "-": election = .disabled
        default: election = .unknown
        }
        return (election, bundleID)
    }

    private static func value(after prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
