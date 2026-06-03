import SwiftUI

public enum SidebarItem: String, CaseIterable, Identifiable {
    // Main
    case smartScan = "Smart Scan"

    // Cleanup
    case systemJunk = "System Junk"
    case mailAttachments = "Mail Attachments"
    case trashBins = "Trash Bins"

    // Protection
    case malwareRemoval = "Malware Removal"
    case privacy = "Privacy"

    // Performance
    case optimization = "Optimization"
    case maintenance = "Maintenance"

    // Applications
    case uninstaller = "Uninstaller"
    case updater = "Updater"

    // Files
    case spaceLens = "Space Lens"
    case largeOldFiles = "Large & Old Files"
    case duplicates = "Duplicates"
    case shredder = "Shredder"

    public var id: String { rawValue }

    /// Stable slug used in `macclean://module/<id>` deep links.
    public var deepLinkID: String {
        switch self {
        case .smartScan: "smart-scan"
        case .systemJunk: "system-junk"
        case .mailAttachments: "mail-attachments"
        case .trashBins: "trash-bins"
        case .malwareRemoval: "malware"
        case .privacy: "privacy"
        case .optimization: "optimization"
        case .maintenance: "maintenance"
        case .uninstaller: "uninstaller"
        case .updater: "updater"
        case .spaceLens: "space-lens"
        case .largeOldFiles: "large-old-files"
        case .duplicates: "duplicates"
        case .shredder: "shredder"
        }
    }

    public init?(deepLinkID: String) {
        guard let match = Self.allCases.first(where: { $0.deepLinkID == deepLinkID }) else { return nil }
        self = match
    }

    public var icon: String {
        switch self {
        case .smartScan: "sparkle.magnifyingglass"
        case .systemJunk: "trash.circle"
        case .mailAttachments: "paperclip.circle"
        case .trashBins: "trash"
        case .malwareRemoval: "shield.lefthalf.filled"
        case .privacy: "hand.raised.fill"
        case .optimization: "gauge.with.dots.needle.67percent"
        case .maintenance: "wrench.and.screwdriver"
        case .uninstaller: "xmark.app"
        case .updater: "arrow.triangle.2.circlepath"
        case .spaceLens: "chart.pie"
        case .largeOldFiles: "doc.richtext"
        case .duplicates: "plus.square.on.square"
        case .shredder: "scissors"
        }
    }

    public var theme: ModuleTheme {
        switch self {
        case .smartScan: .smartScan
        case .systemJunk, .mailAttachments, .trashBins: .cleanup
        case .malwareRemoval, .privacy: .protection
        case .optimization, .maintenance: .performance
        case .uninstaller, .updater: .applications
        case .spaceLens, .largeOldFiles, .duplicates, .shredder: .files
        }
    }

    public var section: SidebarSection {
        switch self {
        case .smartScan: .main
        case .systemJunk, .mailAttachments, .trashBins: .cleanup
        case .malwareRemoval, .privacy: .protection
        case .optimization, .maintenance: .performance
        case .uninstaller, .updater: .applications
        case .spaceLens, .largeOldFiles, .duplicates, .shredder: .files
        }
    }
}

public enum SidebarSection: String, CaseIterable, Identifiable {
    case main = ""
    case cleanup = "Cleanup"
    case protection = "Protection"
    case performance = "Performance"
    case applications = "Applications"
    case files = "Files"

    public var id: String { rawValue }

    public var items: [SidebarItem] {
        SidebarItem.allCases.filter { $0.section == self }
    }
}

public struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @AppStorage("showMenuBarWidget") private var showMenuBarWidget = true
    @State private var launcher = MenuBarLauncher.shared
    /// Sections the user has collapsed. Native `.sidebar` Sections only reveal
    /// a collapse chevron on hover and don't fold on a title click, so we render
    /// our own header rows with an always-visible chevron that fold on tap.
    @State private var collapsedSections: Set<SidebarSection> = []

    public init(selection: Binding<SidebarItem?>) {
        self._selection = selection
    }

    public var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(SidebarSection.allCases) { section in
                    if section == .main {
                        ForEach(section.items) { item in
                            sidebarRow(item)
                        }
                    } else {
                        sectionHeader(section)
                        if !collapsedSections.contains(section) {
                            ForEach(section.items) { item in
                                sidebarRow(item)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider().opacity(0.4)

            menuBarFooter
        }
        .frame(minWidth: 180, idealWidth: 200)
    }

    /// A collapsible section header: always-visible leading chevron + title;
    /// the whole row folds/unfolds the section on tap. Not selectable (it isn't
    /// a module), so clicking it never changes the detail pane.
    private func sectionHeader(_ section: SidebarSection) -> some View {
        let isCollapsed = collapsedSections.contains(section)
        return HStack(spacing: 6) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(section.rawValue.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                if isCollapsed { collapsedSections.remove(section) }
                else { collapsedSections.insert(section) }
            }
        }
        .selectionDisabled()
        .listRowSeparator(.hidden)
    }

    /// Always-visible footer at the bottom of the sidebar with the
    /// menu bar widget toggle. ⌘, Settings has the same control plus
    /// a status diagnostic row; this one is the discoverable entry
    /// point for users who haven't learned the keyboard shortcut.
    private var menuBarFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: showMenuBarWidget
                  ? "menubar.dock.rectangle.badge.record"
                  : "menubar.dock.rectangle")
                .foregroundStyle(showMenuBarWidget ? .green : .secondary)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 0) {
                Text("Menu Bar Widget")
                    .font(.system(size: 11, weight: .medium))
                Text(showMenuBarWidget ? "Running" : "Off")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $showMenuBarWidget)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onChange(of: showMenuBarWidget) { _, newValue in
            launcher.setEnabled(newValue)
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label {
            Text(item.rawValue)
                .fontWeight(item == .smartScan ? .semibold : .regular)
        } icon: {
            Image(systemName: item.icon)
                .foregroundStyle(item.theme.accentColor)
        }
        .tag(item)
    }
}
