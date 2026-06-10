import Foundation

/// Pure decision logic for the "leftovers from deleted apps" scan: given a
/// Library entry whose name looks like an app's bundle id, decide whether the
/// owning app is gone and the entry is therefore an orphan.
///
/// Design notes (learned from how this goes wrong in the field — e.g.
/// Pearcleaner's false-positive reports): macOS guarantees no association
/// between an app and its scattered files, so the only signal we trust for an
/// AUTOMATIC, deletion-oriented scan is the bundle id. Name-based matching is
/// what flags files of installed apps, so we don't do it here. We also defend
/// against the specific traps: helper/agent ids of installed apps, shared
/// frameworks, and system ids.
public enum OrphanedAppFiles {

    /// Suffixes apps append to spawn helpers/agents/etc. We strip these to the
    /// base id so a leftover named `com.x.app.helper` is recognised as
    /// belonging to installed `com.x.app`.
    static let helperSuffixes = [
        ".helper", ".agent", ".daemon", ".launcher", ".updater", ".framework",
        ".xpc", ".findersync", ".quicklook", ".shareextension", ".widget",
        ".loginitem", ".service",
    ]

    /// Bundle-id prefixes that are NEVER owned by a single user app and must
    /// never be flagged: Apple/system, plus a small curated set of shared
    /// frameworks and updaters that many apps drop under their own id.
    static let neverFlagPrefixes = [
        "com.apple.",          // system
        "org.chromium.",       // Chromium / CEF embedded in many apps
        "com.google.keystone", // Google's shared updater
        "org.qt-project.",     // Qt framework
        "io.qt.",              // Qt framework
        "com.github.electron", // Electron shared runtime
        "com.electron.",       // Electron shared runtime
    ]

    /// Decide whether a directory named `bundleID` is an orphan, given the set
    /// of currently-installed app bundle ids.
    public static func isOrphan(bundleID: String, installedBundleIDs: Set<String>) -> Bool {
        let id = bundleID.lowercased()

        // Only ever auto-flag clean reverse-DNS bundle ids.
        guard isBundleIDLike(id) else { return false }

        // System and shared-framework ids are off-limits.
        if neverFlagPrefixes.contains(where: { id == $0 || id.hasPrefix($0) }) {
            return false
        }

        let installed = Set(installedBundleIDs.map { $0.lowercased() })
        let base = strippingHelperSuffixes(id)

        // In use if any installed app shares dotted-prefix lineage with either
        // the id itself or its helper-stripped base. This catches the dominant
        // false positive: `com.x.app.helper` while `com.x.app` is installed,
        // and the reverse (entry is a parent of an installed app's id).
        for installedID in installed {
            if sharesLineage(installedID, id) || sharesLineage(installedID, base) {
                return false
            }
        }
        return true
    }

    /// True if `a` and `b` are equal or one is a dotted-prefix ancestor of the
    /// other (`com.x` ~ `com.x.app`). Crucially NOT a mere shared company
    /// prefix: `com.adobe.photoshop` and `com.adobe.illustrator` do not share
    /// lineage, so an Illustrator leftover is still an orphan while Photoshop
    /// is installed.
    static func sharesLineage(_ a: String, _ b: String) -> Bool {
        a == b || a.hasPrefix(b + ".") || b.hasPrefix(a + ".")
    }

    /// A reverse-DNS-looking id: >= 3 non-empty dot components (tld.company.app),
    /// made only of id-safe characters. Requiring three components keeps plain
    /// filenames like `cache.db` and bare names out of the auto-flag set.
    static func isBundleIDLike(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    static func strippingHelperSuffixes(_ id: String) -> String {
        var result = id
        var changed = true
        while changed {
            changed = false
            for suffix in helperSuffixes where result.hasSuffix(suffix) && result.count > suffix.count {
                result = String(result.dropLast(suffix.count))
                changed = true
            }
        }
        return result
    }
}
