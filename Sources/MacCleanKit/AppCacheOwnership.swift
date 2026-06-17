import Foundation

/// Best-effort mapping from a cache/support file path to the bundle id of the
/// app that owns it, so the UI can show an "App open" badge when that app is
/// currently running (clearing a live app's cache can disrupt it).
///
/// Pure and heuristic: it recognises the common `~/Library` layouts that encode
/// a bundle id in the path, plus a small lookup for browsers that don't. When it
/// can't attribute a path it returns nil and the UI simply shows no badge.
public enum AppCacheOwnership {
    /// The set of item URLs (across all results) whose owning app is currently
    /// running. Computed once when results/running apps change, so the per-render
    /// `FileListRows.flatten` can mark "app open" with a cheap set lookup instead
    /// of re-parsing every path on every selection toggle.
    public static func runningOwnedURLs(
        in results: [ScanResult],
        runningBundleIDs: Set<String>
    ) -> Set<URL> {
        guard !runningBundleIDs.isEmpty else { return [] }
        var urls: Set<URL> = []
        for result in results {
            for item in result.items {
                if let id = owningBundleID(for: item.url), runningBundleIDs.contains(id) {
                    urls.insert(item.url)
                }
            }
        }
        return urls
    }

    public static func owningBundleID(for url: URL) -> String? {
        let components = url.pathComponents

        // Layouts that put the bundle id directly after a known folder:
        //   ~/Library/Caches/<id>/…, Containers/<id>/…, HTTPStorages/<id>/…,
        //   WebKit/<id>/…, Application Scripts/<id>/…
        let anchors = ["Caches", "Containers", "HTTPStorages", "WebKit", "Application Scripts"]
        for anchor in anchors {
            guard let i = components.firstIndex(of: anchor), i + 1 < components.count else { continue }
            let candidate = components[i + 1]
            if looksLikeBundleID(candidate) { return candidate }
        }

        // Apps whose caches don't encode a bundle id in the path.
        let path = url.path
        for entry in browserMap where path.contains(entry.needle) {
            return entry.bundleID
        }
        return nil
    }

    /// Reverse-DNS shape: at least two dot-separated segments, all chars safe.
    private static func looksLikeBundleID(_ string: String) -> Bool {
        guard string.split(separator: ".").count >= 2 else { return false }
        return string.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    private static let browserMap: [(needle: String, bundleID: String)] = [
        ("/Google/Chrome/", "com.google.Chrome"),
        ("/Firefox/", "org.mozilla.firefox"),
        ("/Arc/", "company.thebrowser.Browser"),
        ("/BraveSoftware/Brave-Browser/", "com.brave.Browser"),
        ("/Microsoft Edge/", "com.microsoft.edgemac"),
        ("/Vivaldi/", "com.vivaldi.Vivaldi"),
    ]
}
