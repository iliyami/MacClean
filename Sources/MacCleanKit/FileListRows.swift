import Foundation

/// One row of the scan-results table: either a category header or a file.
///
/// The table is AppKit (`NSTableView`) because SwiftUI's `List` diffs every
/// row on each update and beachballs at tens of thousands of rows. The table
/// renders from this flat, value-typed row array; equality on the array is
/// the entire "did anything change" check, so the row carries everything a
/// cell displays (selection state, and whether the owning app is running).
public enum FileListRow: Equatable, Sendable {
    case header(FileListHeader)
    case item(FileItem, isSelected: Bool, appRunning: Bool)
}

/// Tri-state selection for a category's select-all checkbox.
public enum SelectionState: Sendable, Equatable {
    case none, mixed, all
}

/// Display model for a category header row.
public struct FileListHeader: Equatable, Sendable {
    public let category: ScanCategory
    public let totalSize: UInt64
    public let fileCount: Int
    public let selectedSize: UInt64
    public let selectedCount: Int
    public let isExpanded: Bool

    public init(
        category: ScanCategory,
        totalSize: UInt64,
        fileCount: Int,
        selectedSize: UInt64,
        selectedCount: Int,
        isExpanded: Bool
    ) {
        self.category = category
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.selectedSize = selectedSize
        self.selectedCount = selectedCount
        self.isExpanded = isExpanded
    }

    /// Tri-state for the header checkbox: none / mixed / all selected.
    public var selection: SelectionState {
        if selectedCount <= 0 { return .none }
        if selectedCount >= fileCount { return .all }
        return .mixed
    }
}

public enum FileListRows {
    /// Flatten scan results into table rows: each category contributes a
    /// header, then (if expanded) its items in the order given. `runningBundleIDs`
    /// (the currently-running apps' bundle ids) lets each item flag whether the
    /// app that owns it is open, so the UI can warn before clearing a live cache.
    /// `appRunningURLs` is the precomputed set of item URLs whose owning app is
    /// running (see `AppCacheOwnership.runningOwnedURLs`). flatten runs on every
    /// render (e.g. each selection toggle), so it must stay O(items) with only
    /// cheap set lookups — the expensive path→bundle-id work is done once,
    /// outside this hot path.
    public static func flatten(
        results: [ScanResult],
        isExpanded: (ScanCategory) -> Bool,
        selectedItems: Set<URL>,
        appRunningURLs: Set<URL> = []
    ) -> [FileListRow] {
        var rows: [FileListRow] = []
        rows.reserveCapacity(results.reduce(results.count) { $0 + $1.items.count })

        for result in results {
            var selectedCount = 0
            var selectedSize: UInt64 = 0
            for item in result.items where selectedItems.contains(item.url) {
                selectedCount += 1
                selectedSize += item.size
            }

            let expanded = isExpanded(result.category)
            rows.append(.header(FileListHeader(
                category: result.category,
                totalSize: result.totalSize,
                fileCount: result.fileCount,
                selectedSize: selectedSize,
                selectedCount: selectedCount,
                isExpanded: expanded
            )))

            if expanded {
                for item in result.items {
                    rows.append(.item(
                        item,
                        isSelected: selectedItems.contains(item.url),
                        appRunning: appRunningURLs.contains(item.url)
                    ))
                }
            }
        }
        return rows
    }
}
