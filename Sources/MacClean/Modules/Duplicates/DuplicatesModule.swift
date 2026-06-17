import Foundation
import CryptoKit
import MacCleanKit

public struct DuplicatesModule: ScanModule {
    public let id = "duplicates"
    public var name: String { L10n.tr("重复文件", "Duplicates") }
    public let category = ModuleCategory.files
    public let includedInSmartScan = false

    private let scanner = TargetedScanner()

    public init() {}

    /// Scan targets for the duplicate finder: the home folder, minus hidden
    /// (dot-prefixed) subtrees — those hold app/developer state (caches,
    /// extensions, configs) rather than user documents, and surfacing them as
    /// "duplicates" both buries real finds in noise and risks breaking apps
    /// that need their copy at that exact path.
    private var scanTargets: [ScanTarget] {
        [
            ScanTarget(
                path: MCConstants.home,
                recursive: true,
                maxDepth: 5,
                minSize: 1024,
                excludePatterns: ["Library", "node_modules"],
                skipHiddenDirectories: true
            ),
        ]
    }

    public func scan() async -> [ScanResult] {
        let items = await scanner.scan(targets: scanTargets)
        let files = items.filter { !$0.isDirectory }
        let duplicateGroups = await findDuplicates(files)
        let duplicates = DuplicateDetection.extractDeletableDuplicates(duplicateGroups)

        guard !duplicates.isEmpty else { return [] }
        return [ScanResult(category: .duplicates, items: duplicates, autoSelect: false)]
            .filteringUncleanable()
    }

    /// Like `scan()`, but returns the full grouped structure the Duplicates UI
    /// shows: each set's kept original plus its removable copies. Only the
    /// removable copies are filtered for cleanability — the original is never
    /// deleted, so it doesn't matter whether the current process could trash
    /// it. Sets with no cleanable extras left are dropped by `displayGroups`.
    public func scanDisplayGroups() async -> [DuplicateDisplayGroup] {
        let items = await scanner.scan(targets: scanTargets)
        let files = items.filter { !$0.isDirectory }
        let duplicateGroups = await findDuplicates(files)
        let cleanableGroups = duplicateGroups.map { group in
            group.filter { CleanFilter.isCleanableByCurrentProcess($0.url) }
        }
        return DuplicateDetection.displayGroups(cleanableGroups)
    }

    /// Run the full pipeline. Pure decisions come from `DuplicateDetection`
    /// in MacCleanKit; the hashing itself uses CryptoKit + FileHandle and
    /// lives here.
    public func findDuplicates(_ files: [FileItem]) async -> [[FileItem]] {
        // Stage 1: size grouping (pure)
        let candidates = DuplicateDetection.sizeGroups(files)

        // Stage 2: partial hash (parallel)
        let partialResults = await withTaskGroup(of: (key: String, item: FileItem)?.self) {
            group -> [(key: String, item: FileItem)] in
            for sizeGroup in candidates {
                for item in sizeGroup {
                    group.addTask {
                        guard let hash = Self.partialHash(item.url) else { return nil }
                        return (key: "\(item.size)-\(hash)", item: item)
                    }
                }
            }
            var out: [(key: String, item: FileItem)] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }
        let partialCandidates = DuplicateDetection.partialGroups(partialResults)

        // Stage 3: full hash (parallel)
        let fullResults = await withTaskGroup(of: (key: String, item: FileItem)?.self) {
            group -> [(key: String, item: FileItem)] in
            for partialGroup in partialCandidates {
                for item in partialGroup {
                    group.addTask {
                        guard let hash = Self.fullHash(item.url) else { return nil }
                        return (key: hash, item: item)
                    }
                }
            }
            var out: [(key: String, item: FileItem)] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }

        // Stage 4: dedup hard links (pure)
        return DuplicateDetection.fullGroupsAndDedupHardLinks(fullResults)
    }

    static func partialHash(_ url: URL, bytes: Int = 4096) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: bytes)
        guard !data.isEmpty else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func fullHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 65536)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
