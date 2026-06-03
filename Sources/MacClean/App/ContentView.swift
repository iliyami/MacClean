import SwiftUI
import MacCleanKit

struct ContentView: View {
    @Environment(AppState.self) private var appState

    /// Module views the user has visited at least once. Once a view is here it
    /// stays in the hierarchy (hidden via opacity, NOT destroyed) when the user
    /// switches tabs — so in-flight scans keep running and large result lists
    /// don't re-render on every switch (fixes the switch-back lag and the
    /// mid-scan "cancel"). Views are created lazily on first visit so we don't
    /// front-load every module's `.task` (app discovery, login items, …) at
    /// launch.
    @State private var visited: Set<SidebarItem> = []

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView(selection: $state.selectedSidebarItem)
                // The sidebar is the app's primary navigation and is always
                // shown, so the toolbar's collapse-sidebar button is just
                // dead weight (#21.4). Remove it.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            ZStack {
                if let item = appState.selectedSidebarItem {
                    GradientBackgroundView(theme: item.theme)
                        .ignoresSafeArea()
                }

                // Keep every visited module view alive across tab switches:
                // show the selected one, hide (don't tear down) the rest.
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    // Render if currently selected (so the first frame is never
                    // blank) or previously visited (kept alive in the background).
                    if visited.contains(item) || item == appState.selectedSidebarItem {
                        let isSelected = item == appState.selectedSidebarItem
                        moduleView(for: item)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(isSelected ? 1 : 0)
                            .allowsHitTesting(isSelected)
                            .accessibilityHidden(!isSelected)
                    }
                }

                if appState.selectedSidebarItem == nil {
                    Text("Select a module from the sidebar")
                        .foregroundStyle(.secondary)
                }
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .navigationTitle("Mac Clean")
        // Native macOS pattern: small grey second line under the title.
        // MCConstants.appVersion is checked against VERSION by CI
        // (scripts/check-version-sync.sh) — drifting between the two
        // fails the build.
        .navigationSubtitle("v\(MCConstants.appVersion)")
        // Mark the current selection visited (runs initially too) so its view
        // is created on first visit and then retained.
        .onChange(of: appState.selectedSidebarItem, initial: true) { _, newValue in
            if let newValue { visited.insert(newValue) }
        }
    }

    @ViewBuilder
    private func moduleView(for item: SidebarItem) -> some View {
        switch item {
        case .smartScan:
            SmartScanView()
        case .systemJunk:
            SystemJunkView()
        case .mailAttachments:
            MailAttachmentsView()
        case .trashBins:
            TrashBinsView()
        case .malwareRemoval:
            MalwareView()
        case .privacy:
            PrivacyView()
        case .optimization:
            OptimizationView()
        case .maintenance:
            MaintenanceView()
        case .uninstaller:
            UninstallerView()
        case .updater:
            UpdaterView()
        case .spaceLens:
            SpaceLensView()
        case .largeOldFiles:
            LargeOldFilesView()
        case .duplicates:
            DuplicatesView()
        case .shredder:
            ShredderView()
        }
    }
}
