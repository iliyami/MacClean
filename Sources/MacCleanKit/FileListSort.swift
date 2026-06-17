import Foundation

/// How a scan-results file list is ordered. Pure + deterministic so the
/// ordering is stable across runs (Swift's `sorted` isn't guaranteed stable,
/// so every comparator falls through to a total tiebreak on name then path).
///
/// The default is `.sizeDescending`: surfacing the biggest items first is the
/// whole point — users want to find the few large caches worth deleting
/// without scrolling past hundreds of tiny ones.
public enum FileListSort: String, CaseIterable, Sendable {
    case sizeDescending
    case sizeAscending
    case name

    public static let `default`: FileListSort = .sizeDescending

    /// Short label for the sort control.
    public var label: String {
        switch self {
        case .sizeDescending: L10n.tr("从大到小", "Largest first")
        case .sizeAscending: L10n.tr("从小到大", "Smallest first")
        case .name: L10n.tr("按名称", "Name")
        }
    }

    public func sorted(_ items: [FileItem]) -> [FileItem] {
        switch self {
        case .sizeDescending:
            items.sorted { a, b in
                a.size != b.size ? a.size > b.size : Self.tieBreak(a, b)
            }
        case .sizeAscending:
            items.sorted { a, b in
                a.size != b.size ? a.size < b.size : Self.tieBreak(a, b)
            }
        case .name:
            items.sorted(by: Self.tieBreak)
        }
    }

    /// Sort every category's items, preserving category order and metadata.
    /// Callers run this once when the results or sort change (ideally off the
    /// main thread) rather than re-sorting inside a SwiftUI `body`, which would
    /// repeat the work on every render and block the main thread for large
    /// result sets.
    public func sorted(_ results: [ScanResult]) -> [ScanResult] {
        results.map { result in
            ScanResult(
                category: result.category,
                items: sorted(result.items),
                autoSelect: result.autoSelect
            )
        }
    }

    /// Total, deterministic ordering used to break ties: case-insensitive
    /// name, then full path. Guarantees a stable result regardless of input
    /// order or the sort algorithm's stability.
    private static func tieBreak(_ a: FileItem, _ b: FileItem) -> Bool {
        switch a.name.localizedCaseInsensitiveCompare(b.name) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame:
            a.url.path(percentEncoded: false) < b.url.path(percentEncoded: false)
        }
    }
}
