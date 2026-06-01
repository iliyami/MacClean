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
}
