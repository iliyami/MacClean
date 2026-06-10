import SwiftUI
import AppKit
import MacCleanKit

public struct FileListView: View {
    let results: [ScanResult]
    @Binding var selectedItems: Set<URL>
    @State private var expansion = FileListExpansion()
    @State private var sort: FileListSort = .default

    public init(results: [ScanResult], selectedItems: Binding<Set<URL>>) {
        self.results = results
        self._selectedItems = selectedItems
    }

    public var body: some View {
        VStack(spacing: 0) {
            sortBar

            // Flat rows (NOT `Section`): a `.sidebar` List makes Sections natively
            // collapsible and steals header taps for its own collapse state, which
            // fought our custom chevron and made folding unreliable. Rendering the
            // header as a normal row means our chevron is the single, deterministic
            // fold control and `expansion` is the single source of truth.
            List {
                ForEach(results, id: \.category) { result in
                    CategoryHeaderView(
                        category: result.category,
                        totalSize: result.totalSize,
                        fileCount: result.fileCount,
                        allSelected: !result.items.isEmpty && result.items.allSatisfy { selectedItems.contains($0.url) },
                        isExpanded: expansion.isExpanded(result.category),
                        onToggleExpand: {
                            withAnimation { expansion.toggle(result.category) }
                        },
                        onToggleAll: { toggleAll(result) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if expansion.isExpanded(result.category) {
                        // Sort within each category so the biggest items in
                        // that group surface first. Totals/counts in the header
                        // are aggregates and unaffected by row order.
                        ForEach(sort.sorted(result.items)) { item in
                            FileRowView(
                                item: item,
                                isSelected: selectedItems.contains(item.url),
                                onToggle: { toggle(item.url) }
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
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
                Picker("Sort by", selection: $sort) {
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
    private func toggleAll(_ result: ScanResult) {
        let urls = Set(result.items.map(\.url))
        if urls.isSubset(of: selectedItems) {
            selectedItems.subtract(urls)
        } else {
            selectedItems.formUnion(urls)
        }
    }
}

struct CategoryHeaderView: View {
    let category: ScanCategory
    let totalSize: UInt64
    let fileCount: Int
    let allSelected: Bool
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggleAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Leading disclosure chevron — always visible, folds the category.
            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            // Select-all checkbox (visual indicator + control).
            Toggle(isOn: Binding(get: { allSelected }, set: { _ in onToggleAll() })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            // Icon + name. Tapping the name also folds the category.
            HStack(spacing: 8) {
                Image(systemName: category.systemImage)
                    .foregroundStyle(.secondary)
                Text(category.displayName)
                    .font(.headline)
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            Spacer()

            Text("\(fileCount) files")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(FileSizeFormatter.format(totalSize))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
        }
    }
}

struct FileRowView: View {
    let item: FileItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Purely visual — the whole row is the hit target (see onTapGesture
            // below). Hit-testing is disabled so a click on the checkbox isn't
            // counted twice (checkbox action + row tap).
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .allowsHitTesting(false)

            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            Text(item.formattedSize)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }

    private var fileIcon: String {
        switch item.fileExtension {
        case "log", "txt": "doc.text"
        case "plist", "json", "xml": "doc.badge.gearshape"
        case "cache", "db", "sqlite": "cylinder"
        case "dmg": "opticaldisc"
        case "zip", "gz", "tar": "doc.zipper"
        case "lproj": "globe"
        default: "doc"
        }
    }
}
