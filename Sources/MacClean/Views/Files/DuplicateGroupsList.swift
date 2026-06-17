import SwiftUI
import AppKit
import MacCleanKit

/// Grouped results for the Duplicates module. Each set shows the copy we keep
/// (the "original", marked KEPT and with no checkbox — it can never be selected
/// for deletion) above its removable copies, which are pre-checked. The binding
/// only ever holds the URLs of removable copies, so the original is structurally
/// impossible to delete: it isn't in the list the cleaner operates on.
struct DuplicateGroupsList: View {
    let groups: [DuplicateDisplayGroup]
    @Binding var selectedItems: Set<URL>
    // Owned by the parent (DuplicatesView): this view is rebuilt through an
    // AnyView each time a checkbox toggles, which can reset local @State. Keep
    // the expand/collapse set upstream so groups don't fold on every click.
    @Binding var expanded: Set<UUID>

    private var totalDuplicateCount: Int {
        groups.reduce(0) { $0 + $1.duplicates.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            banner
            Divider().opacity(0.3)
            List {
                ForEach(groups) { group in
                    DuplicateGroupHeaderRow(
                        group: group,
                        isExpanded: expanded.contains(group.id),
                        allExtrasSelected: group.duplicates.allSatisfy { selectedItems.contains($0.url) },
                        onToggleExpand: { toggleExpand(group.id) },
                        onToggleAll: { toggleAll(group) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if expanded.contains(group.id) {
                        DuplicateOriginalRow(item: group.original)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        ForEach(group.duplicates) { copy in
                            DuplicateCopyRow(
                                item: copy,
                                isSelected: selectedItems.contains(copy.url),
                                onToggle: { toggle(copy.url) }
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

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr("每组都会保留一个副本，且永远不会被移除。", "One copy of every set is kept and can never be removed."))
                    .font(.system(size: 12, weight: .medium))
                Text(L10n.tr("标记为“保留”的行受保护，只会删除勾选的副本。", "Rows marked KEPT are protected. Only the checked copies are deleted."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(allExpanded ? L10n.tr("全部折叠", "Collapse all") : L10n.tr("全部展开", "Expand all")) {
                if allExpanded { expanded.removeAll() }
                else { expanded = Set(groups.map(\.id)) }
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var allExpanded: Bool {
        !groups.isEmpty && expanded.count == groups.count
    }

    private func toggleExpand(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if expanded.contains(id) { expanded.remove(id) }
            else { expanded.insert(id) }
        }
    }

    private func toggle(_ url: URL) {
        if selectedItems.contains(url) { selectedItems.remove(url) }
        else { selectedItems.insert(url) }
    }

    /// Select-all / deselect-all for one set's removable copies. Never touches
    /// the original (it isn't in `duplicates`).
    private func toggleAll(_ group: DuplicateDisplayGroup) {
        let urls = Set(group.duplicates.map(\.url))
        if urls.isSubset(of: selectedItems) { selectedItems.subtract(urls) }
        else { selectedItems.formUnion(urls) }
    }
}

private struct DuplicateGroupHeaderRow: View {
    let group: DuplicateDisplayGroup
    let isExpanded: Bool
    let allExtrasSelected: Bool
    let onToggleExpand: () -> Void
    let onToggleAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            // Select-all for this set's removable copies.
            Toggle(isOn: Binding(get: { allExtrasSelected }, set: { _ in onToggleAll() })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            HStack(spacing: 8) {
                Image(systemName: "plus.square.on.square")
                    .foregroundStyle(.secondary)
                Text(group.original.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            Spacer()

            Text(L10n.tr("\(group.copyCount) 个副本", "\(group.copyCount) copies"))
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(L10n.tr("可节省 \(group.formattedWastedSpace)", "saves \(group.formattedWastedSpace)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
        }
    }
}

private struct DuplicateOriginalRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.green)
                .frame(width: 20)

            Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(L10n.tr("保留", "KEPT"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.green.opacity(0.15))
                        .clipShape(Capsule())
                }
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
        .opacity(0.85)
        .contextMenu {
            Button(L10n.tr("在 Finder 中显示", "Reveal in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }
}

private struct DuplicateCopyRow: View {
    let item: FileItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Visual only — the whole row is the hit target (onTapGesture),
            // so hit-testing here is disabled to avoid a double toggle.
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .allowsHitTesting(false)
            .frame(width: 20)

            Image(systemName: item.isDirectory ? "folder.fill" : "doc.on.doc")
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
            Button(L10n.tr("在 Finder 中显示", "Reveal in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }
}
