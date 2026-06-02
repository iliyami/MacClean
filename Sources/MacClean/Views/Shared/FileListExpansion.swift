import Foundation
import MacCleanKit

/// Per-category collapse state for FileListView. Categories are expanded by
/// default; only collapsed ones are stored. SwiftUI-free + unit-testable.
struct FileListExpansion {
    private var collapsed: Set<ScanCategory> = []

    func isExpanded(_ c: ScanCategory) -> Bool { !collapsed.contains(c) }

    mutating func toggle(_ c: ScanCategory) {
        if collapsed.contains(c) { collapsed.remove(c) } else { collapsed.insert(c) }
    }

    mutating func collapseAll(_ cats: [ScanCategory]) { collapsed.formUnion(cats) }

    mutating func expandAll() { collapsed.removeAll() }
}
