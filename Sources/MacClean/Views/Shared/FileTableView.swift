import SwiftUI
import AppKit
import MacCleanKit

/// AppKit-backed scan-results table.
///
/// SwiftUI's `List` re-diffs every row on each view update (it cannot be
/// disabled), which beachballs once a scan produces tens of thousands of
/// items — even opening an unrelated menu froze the UI. `NSTableView` only
/// materialises the ~30 visible rows and recycles their cells, so the row
/// count stops mattering. `reloadData()` preserves scroll position and is
/// cheap (visible cells only), so the update path is a single, simple rule:
/// rows changed → reload.
struct FileTableView: NSViewRepresentable {
    let rows: [FileListRow]
    let onToggleItem: (URL) -> Void
    let onToggleAll: (ScanCategory) -> Void
    let onToggleExpand: (ScanCategory) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.usesAutomaticRowHeights = false
        table.selectionHighlightStyle = .none
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .plain
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let coordinator = context.coordinator
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.action = #selector(Coordinator.tableClicked(_:))

        let menu = NSMenu()
        let reveal = NSMenuItem(
            title: "Reveal in Finder",
            action: #selector(Coordinator.revealInFinder(_:)),
            keyEquivalent: ""
        )
        reveal.target = coordinator
        menu.addItem(reveal)
        menu.delegate = coordinator
        table.menu = menu

        coordinator.tableView = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onToggleItem = onToggleItem
        coordinator.onToggleAll = onToggleAll
        coordinator.onToggleExpand = onToggleExpand
        if coordinator.rows != rows {
            coordinator.rows = rows
            coordinator.tableView?.reloadData()
        }
    }

    // MARK: - Coordinator

    // @MainActor + @preconcurrency: AppKit calls these delegate methods on the
    // main thread, but older SDKs (CI's macos-15 Xcode) don't annotate the
    // protocols as @MainActor, so without this the methods compile as
    // nonisolated and every AppKit call inside errors under Swift 6.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency NSTableViewDataSource,
                             @preconcurrency NSTableViewDelegate, @preconcurrency NSMenuDelegate {
        var rows: [FileListRow] = []
        weak var tableView: NSTableView?
        var onToggleItem: (URL) -> Void = { _ in }
        var onToggleAll: (ScanCategory) -> Void = { _ in }
        var onToggleExpand: (ScanCategory) -> Void = { _ in }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            switch rows[row] {
            case .header: 32
            case .item: 38
            }
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            switch rows[row] {
            case .header(let header):
                let cell = dequeue(tableView, id: "header") { HeaderCellView() }
                cell.configure(header: header) { [weak self] in
                    self?.onToggleExpand(header.category)
                } onToggleAll: { [weak self] in
                    self?.onToggleAll(header.category)
                }
                return cell
            case .item(let item, let isSelected):
                let cell = dequeue(tableView, id: "item") { ItemCellView() }
                cell.configure(item: item, isSelected: isSelected) { [weak self] in
                    self?.onToggleItem(item.url)
                }
                return cell
            }
        }

        private func dequeue<T: NSTableCellView>(
            _ tableView: NSTableView, id: String, make: () -> T
        ) -> T {
            let identifier = NSUserInterfaceItemIdentifier(id)
            if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? T {
                return cell
            }
            let cell = make()
            cell.identifier = identifier
            return cell
        }

        /// Single click anywhere on a row (outside its checkbox/chevron
        /// buttons, which consume their own clicks): items toggle selection,
        /// headers fold/unfold.
        @objc func tableClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < rows.count else { return }
            switch rows[row] {
            case .header(let header): onToggleExpand(header.category)
            case .item(let item, _): onToggleItem(item.url)
            }
        }

        @objc func revealInFinder(_ sender: NSMenuItem) {
            guard let row = tableView?.clickedRow, row >= 0, row < rows.count,
                  case .item(let item, _) = rows[row] else { return }
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            let row = tableView?.clickedRow ?? -1
            let isItem = row >= 0 && row < rows.count
                && { if case .item = rows[row] { return true } else { return false } }()
            menu.items.forEach { $0.isHidden = !isItem }
        }
    }
}

// MARK: - Cells

/// Category header: disclosure chevron, select-all checkbox, icon + name,
/// count + total size.
private final class HeaderCellView: NSTableCellView {
    private let chevron = NSButton()
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let size = NSTextField(labelWithString: "")
    private var onToggleExpand: () -> Void = {}
    private var onToggleAll: () -> Void = {}

    init() {
        super.init(frame: .zero)

        chevron.isBordered = false
        chevron.bezelStyle = .regularSquare
        chevron.imagePosition = .imageOnly
        chevron.target = self
        chevron.action = #selector(chevronClicked)

        checkbox.target = self
        checkbox.action = #selector(checkboxClicked)

        icon.contentTintColor = .secondaryLabelColor

        title.font = .boldSystemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail

        count.font = .systemFont(ofSize: 11)
        count.textColor = .tertiaryLabelColor

        size.font = .systemFont(ofSize: 11, weight: .medium)
        size.textColor = .secondaryLabelColor

        for view in [chevron, checkbox, icon, title, count, size] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            chevron.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 18),
            checkbox.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 4),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            size.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            size.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.trailingAnchor.constraint(equalTo: size.leadingAnchor, constant: -10),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(
        header: FileListHeader,
        onToggleExpand: @escaping () -> Void,
        onToggleAll: @escaping () -> Void
    ) {
        self.onToggleExpand = onToggleExpand
        self.onToggleAll = onToggleAll
        chevron.image = NSImage(
            systemSymbolName: header.isExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: header.isExpanded ? "Collapse" : "Expand"
        )
        checkbox.state = header.allSelected ? .on : .off
        icon.image = NSImage(
            systemSymbolName: header.category.systemImage, accessibilityDescription: nil
        )
        title.stringValue = header.category.displayName
        count.stringValue = "\(header.fileCount) files"
        size.stringValue = FileSizeFormatter.format(header.totalSize)
    }

    @objc private func chevronClicked() { onToggleExpand() }
    @objc private func checkboxClicked() { onToggleAll() }
}

/// File row: checkbox, icon, name over parent path, size.
private final class ItemCellView: NSTableCellView {
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let path = NSTextField(labelWithString: "")
    private let size = NSTextField(labelWithString: "")
    private var onToggle: () -> Void = {}

    init() {
        super.init(frame: .zero)

        checkbox.target = self
        checkbox.action = #selector(checkboxClicked)

        icon.contentTintColor = .secondaryLabelColor

        name.font = .systemFont(ofSize: 12)
        name.lineBreakMode = .byTruncatingMiddle

        path.font = .systemFont(ofSize: 10)
        path.textColor = .tertiaryLabelColor
        path.lineBreakMode = .byTruncatingHead

        size.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        size.textColor = .secondaryLabelColor
        size.alignment = .right

        for view in [checkbox, icon, name, path, size] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            name.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            path.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            path.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
            size.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            size.centerYAnchor.constraint(equalTo: centerYAnchor),
            size.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            name.trailingAnchor.constraint(lessThanOrEqualTo: size.leadingAnchor, constant: -8),
            path.trailingAnchor.constraint(lessThanOrEqualTo: size.leadingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(item: FileItem, isSelected: Bool, onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        checkbox.state = isSelected ? .on : .off
        icon.image = NSImage(
            systemSymbolName: item.isDirectory ? "folder.fill" : Self.symbolName(for: item),
            accessibilityDescription: nil
        )
        name.stringValue = item.name
        path.stringValue = item.url.deletingLastPathComponent().path(percentEncoded: false)
        size.stringValue = item.formattedSize
    }

    @objc private func checkboxClicked() { onToggle() }

    private static func symbolName(for item: FileItem) -> String {
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
