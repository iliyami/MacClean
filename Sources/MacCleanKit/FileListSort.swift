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
        case .sizeDescending: "Largest first"
        case .sizeAscending: "Smallest first"
        case .name: "Name"
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
