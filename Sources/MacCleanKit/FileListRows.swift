import Foundation

/// One row of the scan-results table: either a category header or a file.
///
/// The table is AppKit (`NSTableView`) because SwiftUI's `List` diffs every
/// row on each update and beachballs at tens of thousands of rows. The table
/// renders from this flat, value-typed row array; equality on the array is
/// the entire "did anything change" check, so the row carries everything a
/// cell displays (including selection state).
public enum FileListRow: Equatable, Sendable {
    case header(FileListHeader)
    case item(FileItem, isSelected: Bool)
}

/// Display model for a category header row.
public struct FileListHeader: Equatable, Sendable {
    public let category: ScanCategory
    public let totalSize: UInt64
    public let fileCount: Int
    public let isExpanded: Bool
    public let allSelected: Bool

    public init(
        category: ScanCategory,
        totalSize: UInt64,
        fileCount: Int,
        isExpanded: Bool,
        allSelected: Bool
    ) {
        self.category = category
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.isExpanded = isExpanded
        self.allSelected = allSelected
    }
}

public enum FileListRows {
    /// Flatten scan results into table rows: each category contributes a
    /// header, then (if expanded) its items in the order given.
    public static func flatten(
        results: [ScanResult],
        isExpanded: (ScanCategory) -> Bool,
        selectedItems: Set<URL>
    ) -> [FileListRow] {
        var rows: [FileListRow] = []
        rows.reserveCapacity(results.reduce(results.count) { $0 + $1.items.count })

        for result in results {
            let expanded = isExpanded(result.category)
            rows.append(.header(FileListHeader(
                category: result.category,
                totalSize: result.totalSize,
                fileCount: result.fileCount,
                isExpanded: expanded,
                allSelected: !result.items.isEmpty
                    && result.items.allSatisfy { selectedItems.contains($0.url) }
            )))
            if expanded {
                for item in result.items {
                    rows.append(.item(item, isSelected: selectedItems.contains(item.url)))
                }
            }
        }
        return rows
    }
}
