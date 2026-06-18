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
            title: L10n.tr("在 Finder 中显示", "Reveal in Finder"),
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
        // Top/bottom breathing room so the first/last rows aren't flush against
        // the rounded container edges.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
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
            case .header: 50
            case .item: 42
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
            case .item(let item, let isSelected, let appRunning):
                let cell = dequeue(tableView, id: "item") { ItemCellView() }
                cell.configure(
                    item: item,
                    isSelected: isSelected,
                    appRunning: appRunning,
                    onToggle: { [weak self] in self?.onToggleItem(item.url) },
                    onReveal: { NSWorkspace.shared.activateFileViewerSelecting([item.url]) },
                    onInfo: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(item.url.path(percentEncoded: false), forType: .string)
                    }
                )
                return cell
            }
        }

        /// Each category (header + its items) is drawn as one rounded "card"
        /// with a gap between groups: the row's position within its group decides
        /// which corners round. Groups always start with a header row and run
        /// until the next header (or the end).
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let id = NSUserInterfaceItemIdentifier("grouprow")
            let rowView = (tableView.makeView(withIdentifier: id, owner: nil) as? GroupRowView)
                ?? { let view = GroupRowView(); view.identifier = id; return view }()
            rowView.groupPosition = groupPosition(for: row)
            return rowView
        }

        private func groupPosition(for row: Int) -> GroupRowView.GroupPosition {
            let isFirst: Bool = { if case .header = rows[row] { return true } else { return false } }()
            let isLast: Bool = row == rows.count - 1
                || { if case .header = rows[row + 1] { return true } else { return false } }()
            switch (isFirst, isLast) {
            case (true, true): return .single
            case (true, false): return .top
            case (false, true): return .bottom
            case (false, false): return .middle
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

        /// Single click anywhere on a row (outside its checkbox/chevron/action
        /// buttons, which consume their own clicks): items toggle selection,
        /// headers fold/unfold.
        @objc func tableClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < rows.count else { return }
            switch rows[row] {
            case .header(let header): onToggleExpand(header.category)
            case .item(let item, _, _): onToggleItem(item.url)
            }
        }

        @objc func revealInFinder(_ sender: NSMenuItem) {
            guard let row = tableView?.clickedRow, row >= 0, row < rows.count,
                  case .item(let item, _, _) = rows[row] else { return }
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

/// Category header: disclosure chevron, tri-state select-all checkbox, icon,
/// name over a one-line description, "selected/total selected" count, and a
/// "selectedSize / totalSize" readout (selected portion in the accent colour).
private final class HeaderCellView: NSTableCellView {
    private let chevron = NSButton()
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
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

        checkbox.allowsMixedState = true
        checkbox.target = self
        checkbox.action = #selector(checkboxClicked)

        icon.contentTintColor = .secondaryLabelColor

        title.font = .boldSystemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1

        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .tertiaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.maximumNumberOfLines = 1

        for label in [title, subtitle] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        count.font = .systemFont(ofSize: 11)
        count.textColor = .tertiaryLabelColor

        size.font = .systemFont(ofSize: 11, weight: .medium)

        for view in [chevron, checkbox, icon, title, subtitle, count, size] {
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
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            size.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            size.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.trailingAnchor.constraint(equalTo: size.leadingAnchor, constant: -12),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -8),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -8),
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
            accessibilityDescription: header.isExpanded ? L10n.tr("折叠", "Collapse") : L10n.tr("展开", "Expand")
        )
        switch header.selection {
        case .all: checkbox.state = .on
        case .mixed: checkbox.state = .mixed
        case .none: checkbox.state = .off
        }
        icon.image = NSImage(
            systemSymbolName: header.category.systemImage, accessibilityDescription: nil
        )
        title.stringValue = header.category.displayName
        subtitle.stringValue = header.category.subtitle
        count.stringValue = L10n.tr("已选择 \(header.selectedCount)/\(header.fileCount)", "\(header.selectedCount)/\(header.fileCount) selected")
        size.attributedStringValue = Self.sizeText(
            selected: header.selectedSize, total: header.totalSize
        )
    }

    /// "selectedSize / totalSize" — the selected portion emphasised with the
    /// primary label colour + weight (readable on the coloured module
    /// backgrounds, unlike an accent tint), the total dimmed.
    private static func sizeText(selected: UInt64, total: UInt64) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: FileSizeFormatter.format(selected),
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            ]
        )
        result.append(NSAttributedString(
            string: " / \(FileSizeFormatter.format(total))",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            ]
        ))
        return result
    }

    @objc private func chevronClicked() { onToggleExpand() }
    @objc private func checkboxClicked() { onToggleAll() }
}

/// File row: checkbox, icon, name over parent path, optional "App open" badge,
/// size, and inline info (copy path) + reveal-in-Finder buttons.
private final class ItemCellView: NSTableCellView {
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let path = NSTextField(labelWithString: "")
    private let badge = BadgeView(text: L10n.tr("应用已打开", "App open"))
    private let size = NSTextField(labelWithString: "")
    private let infoButton = NSButton()
    private let revealButton = NSButton()
    private var onToggle: () -> Void = {}
    private var onReveal: () -> Void = {}
    private var onInfo: () -> Void = {}

    init() {
        super.init(frame: .zero)

        checkbox.target = self
        checkbox.action = #selector(checkboxClicked)

        icon.contentTintColor = .secondaryLabelColor

        name.font = .systemFont(ofSize: 12)
        name.lineBreakMode = .byTruncatingMiddle
        name.maximumNumberOfLines = 1

        path.font = .systemFont(ofSize: 10)
        path.textColor = .tertiaryLabelColor
        path.lineBreakMode = .byTruncatingHead
        path.maximumNumberOfLines = 1

        // Long, space-less names (e.g. cache hashes) must truncate, not push the
        // checkbox/icon out of alignment. Let the labels yield horizontally.
        for label in [name, path] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        size.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        size.textColor = .secondaryLabelColor
        size.alignment = .right

        configureIconButton(infoButton, symbol: "info.circle", tooltip: L10n.tr("复制路径", "Copy path"), action: #selector(infoClicked))
        configureIconButton(revealButton, symbol: "folder", tooltip: L10n.tr("在 Finder 中显示", "Reveal in Finder"), action: #selector(revealClicked))

        for view in [checkbox, icon, name, path, badge, size, infoButton, revealButton] {
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
            name.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            path.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            path.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),

            revealButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            revealButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            revealButton.widthAnchor.constraint(equalToConstant: 22),
            infoButton.trailingAnchor.constraint(equalTo: revealButton.leadingAnchor, constant: -2),
            infoButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            infoButton.widthAnchor.constraint(equalToConstant: 22),
            size.trailingAnchor.constraint(equalTo: infoButton.leadingAnchor, constant: -10),
            size.centerYAnchor.constraint(equalTo: centerYAnchor),
            size.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            badge.trailingAnchor.constraint(equalTo: size.leadingAnchor, constant: -10),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),

            name.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),
            path.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func configureIconButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = self
        button.action = action
    }

    func configure(
        item: FileItem,
        isSelected: Bool,
        appRunning: Bool,
        onToggle: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onInfo: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.onReveal = onReveal
        self.onInfo = onInfo
        checkbox.state = isSelected ? .on : .off
        icon.image = NSImage(
            systemSymbolName: item.isDirectory ? "folder.fill" : Self.symbolName(for: item),
            accessibilityDescription: nil
        )
        name.stringValue = item.name
        path.stringValue = item.url.deletingLastPathComponent().path(percentEncoded: false)
        size.stringValue = item.formattedSize
        badge.isHidden = !appRunning
    }

    @objc private func checkboxClicked() { onToggle() }
    @objc private func revealClicked() { onReveal() }
    @objc private func infoClicked() { onInfo() }

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

/// Row background that renders each category group as its own rounded "card":
/// the header rounds the top, the last item rounds the bottom, middle rows are
/// square, and a single (collapsed) group rounds all four corners. A small gap
/// at each group boundary separates adjacent cards.
private final class GroupRowView: NSTableRowView {
    enum GroupPosition { case top, middle, bottom, single }
    var groupPosition: GroupPosition = .middle { didSet { needsLayout = true } }

    private let card = CALayer()
    private let hInset: CGFloat = 6
    private let gap: CGFloat = 6
    private let radius: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        card.cornerRadius = radius
        layer?.addSublayer(card)
        updateCardColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        updateCardColor()
        // Don't animate the card frame on reload/scroll.
        card.actions = ["position": NSNull(), "bounds": NSNull(), "frame": NSNull()]

        let topGap: CGFloat = (groupPosition == .top || groupPosition == .single) ? gap : 0
        let bottomGap: CGFloat = (groupPosition == .bottom || groupPosition == .single) ? gap : 0
        // Layer-backed flipped view: geometry is flipped, so y == 0 is the top.
        card.frame = CGRect(
            x: hInset,
            y: topGap,
            width: max(0, bounds.width - hInset * 2),
            height: max(0, bounds.height - topGap - bottomGap)
        )
        switch groupPosition {
        case .top:
            card.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        case .bottom:
            card.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .single:
            card.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                  .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .middle:
            card.maskedCorners = []
        }
    }

    /// CALayer `cgColor` is static, so re-resolve `labelColor` for the current
    /// appearance: a subtle dark card on Light, a subtle light card on Dark.
    private func updateCardColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            card.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateCardColor()
    }

    // The card is the only background; suppress the table's default selection draw.
    override func drawSelection(in dirtyRect: NSRect) {}
}

/// Small rounded pill, e.g. "App open", warning the user the owning app is live.
private final class BadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor

        label.stringValue = text
        label.font = .systemFont(ofSize: 9, weight: .semibold)
        label.textColor = .systemYellow
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}
