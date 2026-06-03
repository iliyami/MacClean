import Foundation

/// Discovers which `.lproj` language folders actually exist in installed apps,
/// so Settings can offer the user's real languages instead of a hardcoded list.
/// Filesystem-walking but testable against a temp root.
public struct LanguageScanner: Sendable {
    public init() {}

    /// Default roots scanned for installed apps (where language cleanup also looks).
    public static var defaultRoots: [URL] {
        [URL(filePath: "/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")]
    }

    /// Collect the distinct `.lproj` folder names (e.g. "fr.lproj") found in the
    /// `Contents/Resources` of `.app` bundles directly under the given roots.
    public func discoverLproj(in roots: [URL]) -> Set<String> {
        let fm = FileManager.default
        var found: Set<String> = []
        for root in roots {
            guard let apps = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for app in apps where app.pathExtension == "app" {
                let resources = app.appending(path: "Contents/Resources")
                guard let entries = try? fm.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil) else { continue }
                for e in entries where e.pathExtension == "lproj" {
                    found.insert(e.lastPathComponent)
                }
            }
        }
        return found
    }
}
