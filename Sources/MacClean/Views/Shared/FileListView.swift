import SwiftUI
import AppKit
import MacCleanKit

/// Scan-results list: a sort control over an AppKit-backed table.
///
/// The table is `NSTableView` (see `FileTableView`) because SwiftUI's `List`
/// re-diffs every row on each view update, which froze the UI once scans
/// produced tens of thousands of items. Sorting runs off the main thread into
/// `displayResults`; the render path never sorts.
public struct FileListView: View {
    let results: [ScanResult]
    @Binding var selectedItems: Set<URL>
    @State private var expansion = FileListExpansion()
    @State private var sort: FileListSort = .default
    /// Bundle ids of apps running right now, so item rows can show an "App open"
    /// badge. Snapshotted on appear; the set rarely changes during a review.
    @State private var runningBundleIDs: Set<String> = []
    /// Item URLs whose owning app is running. Precomputed off the render path
    /// (the path→bundle-id work is expensive) so selection toggles stay snappy.
    @State private var appRunningURLs: Set<URL> = []
    /// Results with each category's items already sorted, computed off-main
    /// in the `.task` below. Seeded unsorted so content shows immediately.
    @State private var displayResults: [ScanResult]

    public init(results: [ScanResult], selectedItems: Binding<Set<URL>>) {
        self.results = results
        self._selectedItems = selectedItems
        self._displayResults = State(initialValue: results)
    }

    public var body: some View {
        VStack(spacing: 0) {
            sortBar

            FileTableView(
                rows: FileListRows.flatten(
                    results: displayResults,
                    isExpanded: { expansion.isExpanded($0) },
                    selectedItems: selectedItems,
                    appRunningURLs: appRunningURLs
                ),
                onToggleItem: { toggle($0) },
                onToggleAll: { toggleAll($0) },
                onToggleExpand: { expansion.toggle($0) }
            )
        }
        .onAppear {
            runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        // Recompute "app open" URLs only when the results or running apps change,
        // off the main thread — never on a selection toggle.
        .task(id: "\(sortSignature)#\(runningBundleIDs.count)") {
            let snapshot = results
            let running = runningBundleIDs
            appRunningURLs = await Task.detached(priority: .utility) {
                AppCacheOwnership.runningOwnedURLs(in: snapshot, runningBundleIDs: running)
            }.value
        }
        // Re-sort off the main thread whenever the sort or the result set
        // changes. Keyed on a cheap signature (category + count) so it doesn't
        // re-run on unrelated renders like selection toggles.
        .task(id: sortSignature) {
            let snapshot = results
            let order = sort
            let sorted = await Task.detached(priority: .userInitiated) {
                order.sorted(snapshot)
            }.value
            displayResults = sorted
        }
    }

    /// Cheap key for `.task(id:)`: the sort plus each category's item count.
    /// Computed per render but only O(number of categories).
    private var sortSignature: String {
        sort.rawValue + "#" + results.map { "\($0.category.rawValue):\($0.items.count)" }
            .joined(separator: ",")
    }

    /// Compact sort control above the list. Defaults to largest-first; lets the
    /// user flip to smallest-first or name order.
    private var sortBar: some View {
        HStack(spacing: 6) {
            Spacer()
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Menu {
                Picker(L10n.tr("排序方式", "Sort by"), selection: $sort) {
                    ForEach(FileListSort.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(sort.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Toggle selection of a single file by URL.
    private func toggle(_ url: URL) {
        if selectedItems.contains(url) {
            selectedItems.remove(url)
        } else {
            selectedItems.insert(url)
        }
    }

    /// Select-all / deselect-all for a category: if every item is already
    /// selected, deselect them; otherwise select them all.
    private func toggleAll(_ category: ScanCategory) {
        guard let result = results.first(where: { $0.category == category }) else { return }
        let urls = Set(result.items.map(\.url))
        if urls.isSubset(of: selectedItems) {
            selectedItems.subtract(urls)
        } else {
            selectedItems.formUnion(urls)
        }
    }
}
