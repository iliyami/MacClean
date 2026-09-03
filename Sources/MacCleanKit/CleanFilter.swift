import Foundation
import Darwin

/// Drops scan items that our process couldn't trash even if it tried —
/// before they reach the UI. Two categories of un-cleanable items show
/// up routinely on real Macs and used to surface as "X errors" on the
/// completion screen, even though there's nothing the user can do about
/// them:
///
///   * **Root-owned children** under writable parents. `/Library/Caches/`
///     is writable, but `/Library/Caches/com.apple.InferenceProviderService/`
///     is mode 700 root:wheel — `unlink` from inside it returns EACCES.
///     Likewise `/private/var/log/com.apple.xpc.launchd/` (root-owned),
///     `/Library/Logs/PaloAltoNetworks/...` (third-party root daemons).
///
///   * **Data-vault dirs** in the user's own home. `~/Library/Caches/`
///     is owned by the user, but `~/Library/Caches/com.apple.containermanagerd/`,
///     `…com.apple.ap.adprivacyd/`, `…com.apple.Safari.SafeBrowsing/` carry
///     the `UF_DATAVAULT` flag — macOS rejects writes to these subtrees
///     regardless of FDA, regardless of ownership, regardless of root.
///     Only Apple-signed daemons can touch them.
///
/// Both surface as `access(W_OK)` denials at the syscall level (EACCES
/// for POSIX-permission denial, EPERM for data-vault denial), so a single
/// probe covers both.
public enum CleanFilter {
    public static func isCleanableByCurrentProcess(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)

        // `trashItem`/`unlink` is a directory-modification op — it
        // requires write permission on the PARENT directory. Files in
        // root-owned dirs fail here even if the file is "user-readable".
        let parent = (path as NSString).deletingLastPathComponent
        guard access(parent, W_OK) == 0 else { return false }

        // If the item doesn't exist any more (stale scan results from a
        // previous run, cache churn between scan and clean), drop it
        // here instead of surfacing it as a UI row that produces a
        // benign skip at clean time.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            return false
        }

        // Directory deletion has to descend into the tree. This is the
        // check that catches `~/Library/Caches/com.apple.*` — the
        // parent is writable, but the dir itself carries UF_DATAVAULT
        // and macOS rejects writes inside it.
        if isDir.boolValue {
            guard access(path, W_OK) == 0 else { return false }
        }

        return true
    }

    /// True when the item is both writable by this process and outside
    /// every user-excluded folder (issue #141).
    public static func isActionable(
        _ url: URL,
        excludedFolders: [String] = FolderExclusionPreferences.paths
    ) -> Bool {
        isCleanableByCurrentProcess(url) && !PathExclusion.isExcluded(url, by: excludedFolders)
    }
}

public extension Array where Element == ScanResult {
    /// Drops items the current process couldn't trash, per
    /// `CleanFilter.isCleanableByCurrentProcess`, and items under user-
    /// excluded folders (issue #141). Producing modules call this on their
    /// results before returning — that way every caller (ScanCoordinator,
    /// each per-module ViewModel/View that invokes `module.scan()` directly)
    /// sees a filtered set without needing to know about the filter. The
    /// contract is: a `ScanModule.scan()` only returns items the user can
    /// act on.
    func filteringUncleanable(
        excludedFolders: [String] = FolderExclusionPreferences.paths
    ) -> [ScanResult] {
        map { result in
            ScanResult(
                category: result.category,
                items: result.items.filter {
                    CleanFilter.isActionable($0.url, excludedFolders: excludedFolders)
                },
                autoSelect: result.autoSelect
            )
        }
    }

    /// On-disk size of the user's current selection, counting each URL
    /// exactly once. The same file can appear in more than one category
    /// (a file that's both "large" and "old") — and Clean trashes each
    /// path only once — so summing per-item would over-report the estimate
    /// versus what actually gets freed. Dedupe by URL to keep the
    /// "X will be freed" preview honest.
    func selectedSize(_ selected: Set<URL>) -> UInt64 {
        var counted = Set<URL>()
        var total: UInt64 = 0
        for result in self {
            for item in result.items
            where selected.contains(item.url) && counted.insert(item.url).inserted {
                total += item.size
            }
        }
        return total
    }
}
