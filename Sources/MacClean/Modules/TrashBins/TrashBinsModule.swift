import Foundation
import MacCleanKit

public struct TrashBinsModule: ScanModule {
    public let id = "trash_bins"
    public var name: String { L10n.tr("废纸篓", "Trash Bins") }
    public let category = ModuleCategory.cleanup

    private let scanner = TargetedScanner()

    public init() {}

    public func scan() async -> [ScanResult] {
        await scanReportingPermissions().results
    }

    /// Same scan as `scan()`, but also reports whether the Trash came back
    /// empty because Full Disk Access is missing (macOS blocks reading
    /// `~/.Trash` without it, and the enumerator silently yields nothing).
    /// The Trash view uses this to show a "Grant Full Disk Access" prompt
    /// instead of a false "Trash is empty."
    public func scanReportingPermissions() async -> (results: [ScanResult], permissionDenied: Bool) {
        let outcome = await scanner.scanReportingPermissions(targets: Self.targets())
        guard !outcome.items.isEmpty else {
            return ([], outcome.permissionDenied)
        }
        let results = [ScanResult(category: .trashBins, items: outcome.items)]
            .filteringUncleanable()
        return (results, outcome.permissionDenied)
    }

    private static func targets() -> [ScanTarget] {
        var targets: [ScanTarget] = [
            // Main user trash
            ScanTarget(path: MCConstants.userTrash, recursive: true),
        ]

        // External drive trash bins
        if let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRemovableKey],
            options: [.skipHiddenVolumes]
        ) {
            for volume in volumes {
                let trashURL = volume.appending(path: ".Trashes")
                if FileManager.default.fileExists(atPath: trashURL.path(percentEncoded: false)) {
                    targets.append(ScanTarget(path: trashURL, recursive: true))
                }
            }
        }
        return targets
    }
}
