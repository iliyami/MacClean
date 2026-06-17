import Foundation
import MacCleanKit

public struct LargeOldFilesModule: ScanModule {
    public let id = "large_old_files"
    public var name: String { L10n.tr("大文件与旧文件", "Large & Old Files") }
    public let category = ModuleCategory.files

    // Excluded from Smart Scan's "junk found" total: large media (music,
    // videos, project files) is not junk, and folding it into the headline
    // number is misleading. It stays discoverable in its own dedicated
    // section, which runs its own scan. Mirrors the other `.files` modules
    // (Duplicates, SpaceLens, Shredder), which are opt-in for the same reason.
    public let includedInSmartScan = false

    private let scanner = TargetedScanner()
    private let minSize: UInt64
    private let minAge: TimeInterval?

    public init(minSize: UInt64 = 50 * 1024 * 1024, minAge: TimeInterval? = nil) {
        self.minSize = minSize
        self.minAge = minAge
    }

    public func scan() async -> [ScanResult] {
        let targets = [
            ScanTarget(
                path: MCConstants.home,
                recursive: true,
                maxDepth: 5,
                minAge: minAge,
                minSize: minSize,
                excludePatterns: ["Library", ".Trash", ".git", "node_modules"]
            ),
            ScanTarget(
                path: MCConstants.downloads,
                recursive: true,
                minAge: minAge,
                minSize: minSize
            ),
        ]

        let items = await scanner.scan(targets: targets)
        let split = Self.splitLargeAndOld(items: items, minSize: minSize)

        var results: [ScanResult] = []
        if !split.large.isEmpty {
            results.append(ScanResult(category: .largeFiles, items: split.large, autoSelect: false))
        }
        if !split.old.isEmpty {
            results.append(ScanResult(category: .oldFiles, items: split.old, autoSelect: false))
        }
        return results.filteringUncleanable()
    }

    /// Pure splitter for testability: classifies file items into "large" and "old"
    /// buckets based on size and modification age. Both buckets are sorted
    /// (large: descending size; old: ascending mod date).
    public static func splitLargeAndOld(
        items: [FileItem],
        minSize: UInt64,
        oldThreshold: TimeInterval = 180 * 24 * 3600,
        now: Date = Date()
    ) -> (large: [FileItem], old: [FileItem]) {
        var large: [FileItem] = []
        var old: [FileItem] = []
        let cutoff = now.addingTimeInterval(-oldThreshold)

        for item in items where !item.isDirectory {
            if item.size >= minSize { large.append(item) }
            if let modDate = item.modificationDate, modDate < cutoff { old.append(item) }
        }
        large.sort { $0.size > $1.size }
        old.sort { ($0.modificationDate ?? .distantFuture) < ($1.modificationDate ?? .distantFuture) }

        return (large, old)
    }
}

// `FileGroup` moved to MacCleanKit — see Sources/MacCleanKit/FileGroup.swift.
