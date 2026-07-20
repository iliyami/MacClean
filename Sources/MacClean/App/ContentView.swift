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
    @State private var updateCoordinator = UpdateCoordinator()
    @Environment(\.scenePhase) private var scenePhase

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
                    Text(L10n.tr("请从侧边栏选择一个模块", "Select a module from the sidebar", "Выберите модуль на боковой панели"))
                        .foregroundStyle(.secondary)
                }

                // Centered title, drawn as plain content in the title bar
                // region. Not a ToolbarItem: macOS 26 wraps toolbar items in
                // a Liquid Glass capsule we don't want, and the unified
                // toolbar pins its own title to the leading edge (system
                // title hidden via TitleBarConfigurator; the window keeps
                // its real title for Mission Control/VoiceOver).
                VStack {
                    Text(MCConstants.appName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.92))
                        .padding(.top, 16)
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .background(TitleBarConfigurator())
        // Empty: the system-drawn title pins to the leading edge and on
        // macOS 26 ignores titleVisibility re-asserts while SwiftUI owns a
        // non-empty title. The visible (centered) title is drawn by the
        // detail-pane overlay; the real NSWindow.title is set by
        // TitleBarConfigurator so Mission Control/VoiceOver keep the name.
        .navigationTitle("")
        // Mark the current selection visited (runs initially too) so its view
        // is created on first visit and then retained.
        .onChange(of: appState.selectedSidebarItem, initial: true) { _, newValue in
            if let newValue { visited.insert(newValue) }
        }
        // Automatic update check: ~3s after launch (never blocks startup) and
        // again whenever the app becomes active. UpdateCoordinator throttles to
        // once per day and one popup per session.
        .task {
            try? await Task.sleep(for: .seconds(3))
            await updateCoordinator.runCheckIfDue()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await updateCoordinator.runCheckIfDue() }
            }
        }
        .alert(
            L10n.tr("发现新版本", "Update available", "Доступно обновление"),
            isPresented: Binding(
                get: { updateCoordinator.pendingUpdate != nil },
                set: { if !$0 { updateCoordinator.dismiss() } }
            ),
            presenting: updateCoordinator.pendingUpdate
        ) { pending in
            switch pending.action {
            case .brewCommand:
                Button(L10n.tr("复制升级命令", "Copy Upgrade Command", "Скопировать команду обновления")) {
                    updateCoordinator.performPrimaryAction()
                }
            case .openRelease:
                Button(L10n.tr("下载", "Download", "Загрузить")) {
                    updateCoordinator.performPrimaryAction()
                }
            }
            Button(L10n.tr("跳过此版本", "Skip This Version", "Пропустить эту версию")) {
                updateCoordinator.skip(pending.version)
            }
            Button(L10n.tr("稍后", "Later", "Позже"), role: .cancel) {
                updateCoordinator.dismiss()
            }
        } message: { pending in
            switch pending.action {
            case .brewCommand(let cmd):
                Text(L10n.tr(
                    "Mac Sai \(pending.version) 已发布。使用 Homebrew 升级：\n\(cmd)",
                    "Mac Sai \(pending.version) is available. Upgrade with Homebrew:\n\(cmd)",
                    "Доступна версия Mac Sai \(pending.version). Обновите через Homebrew:\n\(cmd)"))
            case .openRelease:
                Text(L10n.tr(
                    "Mac Sai \(pending.version) 已发布。",
                    "Mac Sai \(pending.version) is available.",
                    "Доступна версия Mac Sai \(pending.version)."))
            }
        }
    }

    /// Hides the system-drawn window title once the view lands in a window.
    /// The title string itself stays set (Mission Control, App Exposé, and
    /// VoiceOver still read it); only the toolbar's leading-edge rendering
    /// is suppressed, replaced by the centered principal toolbar item above.
    private struct TitleBarConfigurator: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { ConfiguringView() }

        // Re-assert on every SwiftUI update. SwiftUI's navigationTitle is
        // empty (it kept drawing a leading-edge title on macOS 26), so the
        // real window title lives here: Mission Control, App Exposé, the
        // Window menu, and VoiceOver read NSWindow.title; titleVisibility
        // keeps it out of the toolbar where the overlay draws instead.
        static func apply(to window: NSWindow?) {
            guard let window else { return }
            window.title = MCConstants.appName
            window.titleVisibility = .hidden
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            DispatchQueue.main.async { [weak nsView] in
                Self.apply(to: nsView?.window)
            }
        }

        private final class ConfiguringView: NSView {
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                DispatchQueue.main.async { [weak self] in
                    TitleBarConfigurator.apply(to: self?.window)
                }
            }
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
        case .settings:
            SettingsPageView()
        }
    }
}
