import Foundation

/// Validates that a deletion operation is safe to execute.
///
/// This type lives in MacCleanKit (no FileManager / NSWorkspace dependencies)
/// so it can be exhaustively unit-tested. The actual deletion happens in
/// `CleaningEngine` in the MacClean target, which calls `validateDeletion`
/// before touching any file.
public struct SafetyGuard: Sendable {
    public enum SafetyError: Error, LocalizedError, Equatable {
        case protectedPath(String)
        case tooManyFiles(Int)
        case symlinkTarget(String)
        case sipProtected(String)
        case outsideUserScope(String)
        case invalidPath(String)

        public var errorDescription: String? {
            switch self {
            case .protectedPath(let path):
                L10n.tr("无法修改受保护的系统路径：\(path)", "Cannot modify protected system path: \(path)")
            case .tooManyFiles(let count):
                L10n.tr("操作超过 \(MCConstants.maxFilesPerOperation) 个文件的安全限制（尝试处理：\(count) 个）", "Operation exceeds safety limit of \(MCConstants.maxFilesPerOperation) files (attempted: \(count))")
            case .symlinkTarget(let path):
                L10n.tr("路径通过符号链接指向了意外位置：\(path)", "Path resolves through symlink to unexpected location: \(path)")
            case .sipProtected(let path):
                L10n.tr("路径受系统完整性保护（SIP）保护：\(path)", "Path is protected by System Integrity Protection: \(path)")
            case .outsideUserScope(let path):
                L10n.tr("路径不在允许的用户范围内：\(path)", "Path is outside the allowed user scope: \(path)")
            case .invalidPath(let path):
                L10n.tr("路径无效或包含非法字符：\(path)", "Path is invalid or contains illegal characters: \(path)")
            }
        }
    }

    public init() {}

    /// Validates an entire deletion batch. Throws on the first failure.
    ///
    /// - Throws: `SafetyError.tooManyFiles` if the batch exceeds the cap.
    /// - Throws: `SafetyError.invalidPath` if any path is empty or contains NULL bytes.
    /// - Throws: any error from `validatePath` for the first unsafe path.
    public func validateDeletion(paths: [URL]) throws {
        if paths.count > MCConstants.maxFilesPerOperation {
            throw SafetyError.tooManyFiles(paths.count)
        }

        for path in paths {
            try validatePath(path)
        }
    }

    /// Validates a single path against the safety policy.
    ///
    /// Safety checks (in order):
    /// 1. Path is non-empty and contains no NULL bytes.
    /// 2. After resolving symlinks, the path does not fall inside any protected
    ///    prefix (`/System`, `/usr`, `/bin`, `/sbin`, etc.).
    /// 3. After resolving symlinks, the path does not fall inside `/System/` (SIP).
    /// 4. If symlink resolution changed the first 3 path components, the symlink
    ///    is treated as suspicious (TOCTOU prevention).
    public func validatePath(_ url: URL) throws {
        let original = url.path(percentEncoded: false)

        if original.isEmpty {
            throw SafetyError.invalidPath("(empty)")
        }
        if original.contains("\0") {
            throw SafetyError.invalidPath(original)
        }

        let resolvedPath = url.resolvingSymlinksInPath().path(percentEncoded: false)

        // Canonicalize macOS firmlinks (/var, /tmp, /etc → strip /private)
        // up-front so every downstream check operates on stable strings.
        // Without this, the SAME file looks different to the protected-
        // paths check vs the redirect check depending on whether
        // FileManager.enumerator handed us /var/log/x or /private/var/log/x
        // on this particular macOS version.
        let originalCanonical = Self.canonicalizeMacOSFirmlinks(original)
        let resolvedCanonical = Self.canonicalizeMacOSFirmlinks(resolvedPath)

        // SIP check first — more specific than the general protected-paths
        // blocklist. `/System` lives in both; we surface the more accurate
        // "macOS will refuse this regardless of permissions" error.
        if resolvedCanonical.hasPrefix("/System/") || resolvedCanonical == "/System" {
            throw SafetyError.sipProtected(resolvedPath)
        }

        for protected in Self.canonicalProtectedPaths {
            if resolvedCanonical.hasPrefix(protected + "/") || resolvedCanonical == protected {
                throw SafetyError.protectedPath(resolvedPath)
            }
        }

        if originalCanonical != resolvedCanonical {
            let originalComponents = originalCanonical.components(separatedBy: "/")
            let resolvedComponents = resolvedCanonical.components(separatedBy: "/")
            if originalComponents.prefix(3) != resolvedComponents.prefix(3) {
                throw SafetyError.symlinkTarget(resolvedPath)
            }
        }
    }

    /// `MCConstants.protectedPaths` with macOS firmlinks canonicalized so
    /// `/private/var/db` matches `/var/db` (and vice versa). Computed once.
    private static let canonicalProtectedPaths: Set<String> =
        Set(MCConstants.protectedPaths.map(SafetyGuard.canonicalizeMacOSFirmlinks))

    /// Strips the `/private/` prefix when the immediate next component
    /// is one of macOS's firmlink mounts (`var`, `tmp`, `etc`). After
    /// this, `/private/var/log/wifi.log` and `/var/log/wifi.log` are the
    /// same string — which is the right answer for redirect detection,
    /// because they ARE the same on-disk location reached via different
    /// canonicalization paths.
    ///
    /// We only canonicalize the three known firmlinks. Arbitrary paths
    /// under `/private/` (e.g. `/private/var/db`, which is a real
    /// protected location) keep their form so the protected-paths check
    /// stays effective.
    static func canonicalizeMacOSFirmlinks(_ path: String) -> String {
        for firmlink in ["var", "tmp", "etc"] {
            let privatePrefix = "/private/\(firmlink)"
            if path == privatePrefix {
                return "/\(firmlink)"
            }
            if path.hasPrefix(privatePrefix + "/") {
                return "/\(firmlink)" + path.dropFirst(privatePrefix.count)
            }
        }
        return path
    }

    /// Returns true if the given bundle identifier names an Apple system app
    /// that should never be uninstalled by the user.
    public func isProtectedApp(_ bundleID: String) -> Bool {
        MCConstants.protectedApps.contains(bundleID)
    }

    /// Returns true if a "this preference is orphaned, delete it" decision is
    /// safe for the given URL. Currently restricted to caches / logs / saved
    /// app state / web data — never preferences, containers, or keychains.
    public func isSafeForOrphanDeletion(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let safePrefixes = [
            MCConstants.userCaches.path(percentEncoded: false),
            MCConstants.userLogs.path(percentEncoded: false),
            MCConstants.userHTTPStorages.path(percentEncoded: false),
            MCConstants.userSavedAppState.path(percentEncoded: false),
            MCConstants.userWebKit.path(percentEncoded: false),
        ]
        return safePrefixes.contains { path.hasPrefix($0) }
    }
}
