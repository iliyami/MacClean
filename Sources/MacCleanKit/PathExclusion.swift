import Foundation

/// Path-prefix exclusion matching for user-chosen folders (issue #141).
///
/// Pure: no FileManager. Roots are absolute path strings. Matching uses a
/// `/` boundary (so `…/Caches` does not match `…/CachesEvil`) and the same
/// firmlink canonicalize as `SafetyGuard` so `/var` and `/private/var` agree.
public enum PathExclusion {

    public enum RejectReason: Equatable, Sendable {
        case notAbsolute
        case entireHome
        case entireVolumesRoot
        case outsideAllowedRoots
        case atCapacity
        case alreadyCovered
    }

    public enum CandidateDecision: Equatable, Sendable {
        case allow
        case reject(RejectReason)
    }

    /// True if `path` is `root` or a descendant.
    public static func isInside(_ path: String, root: String) -> Bool {
        let p = SafetyGuard.canonicalizeMacOSFirmlinks(path)
        let r = SafetyGuard.canonicalizeMacOSFirmlinks(root)
        if p == r { return true }
        let prefix = r.hasSuffix("/") ? r : r + "/"
        return p.hasPrefix(prefix)
    }

    public static func isExcluded(path: String, by roots: [String]) -> Bool {
        guard !roots.isEmpty else { return false }
        return roots.contains { isInside(path, root: $0) }
    }

    public static func isExcluded(_ url: URL, by roots: [String]) -> Bool {
        isExcluded(path: url.path(percentEncoded: false), by: roots)
    }

    /// Whether a folder path may be added to the exclusion list.
    public static func candidateDecision(
        for path: String,
        home: String,
        maxCount: Int = FolderExclusionPreferences.defaultMaxCount,
        existing: [String] = []
    ) -> CandidateDecision {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), !trimmed.isEmpty else {
            return .reject(.notAbsolute)
        }
        let canonical = SafetyGuard.canonicalizeMacOSFirmlinks(trimmed)
        let homeCanon = SafetyGuard.canonicalizeMacOSFirmlinks(home)

        if canonical == homeCanon {
            return .reject(.entireHome)
        }
        if canonical == "/Volumes" {
            return .reject(.entireVolumesRoot)
        }

        let underHome = isInside(canonical, root: homeCanon)
        let underVolumes = isInside(canonical, root: "/Volumes")
        guard underHome || underVolumes else {
            return .reject(.outsideAllowedRoots)
        }

        if existing.contains(where: { isInside(canonical, root: $0) }) {
            return .reject(.alreadyCovered)
        }
        if existing.count >= maxCount {
            return .reject(.atCapacity)
        }
        return .allow
    }

    /// Deduped, sorted, with descendants removed when an ancestor is present.
    public static func normalized(_ paths: [String]) -> [String] {
        let unique = Array(Set(paths.map {
            SafetyGuard.canonicalizeMacOSFirmlinks(
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.filter { !$0.isEmpty })).sorted()

        return unique.filter { path in
            !unique.contains { other in
                other != path && isInside(path, root: other)
            }
        }
    }
}
