import Foundation
import MacCleanKit

/// Whether the Duplicates action deletes copies or consolidates them into clones.
enum DuplicatesActionMode: Equatable {
    case remove
    case consolidate
}

/// Pure mapping from display groups + the user's selection to the consolidation
/// work list: per group, the kept original is the master and the selected
/// duplicates are the copies to replace with clones. Groups with no selected
/// copy are dropped. Testable without SwiftUI.
enum DuplicatesConsolidation {
    static func groups(from displayGroups: [DuplicateDisplayGroup],
                       selection: Set<URL>) -> [GroupConsolidation] {
        displayGroups.compactMap { group in
            let copies = group.duplicates
                .map(\.url)
                .filter { selection.contains($0) }
            guard !copies.isEmpty else { return nil }
            return GroupConsolidation(master: group.original.url, copies: copies)
        }
    }

    /// Approximate reclaimable bytes for the confirmation preview, summed from
    /// the sizes already gathered during the scan. Deliberately in-memory: the
    /// accurate, disk-touching `FileConsolidator.estimateReclaimable` must never
    /// run in a view body, or it re-stats every selected file on each checkbox
    /// toggle and freezes the UI (#128). The real reclaimed total is reported
    /// from the actual run on the done screen.
    static func estimatedReclaim(from displayGroups: [DuplicateDisplayGroup],
                                 selection: Set<URL>) -> UInt64 {
        displayGroups.reduce(0) { total, group in
            total + group.duplicates
                .filter { selection.contains($0.url) }
                .reduce(0) { $0 + $1.allocatedSize }
        }
    }
}
