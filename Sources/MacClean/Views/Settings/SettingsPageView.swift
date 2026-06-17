import SwiftUI
import AppKit
import ServiceManagement
import MacCleanKit

/// In-app Settings page rendered in the detail pane. Opened from the
/// pinned sidebar footer, the Cmd-comma "Settings…" menu item, or
/// macclean://module/settings. Replaced the separate Settings window
/// (spec: docs/superpowers/specs/2026-06-05-settings-page-design.md).
struct SettingsPageView: View {
    enum UpdateUIState: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed(message: String)
    }

    @AppStorage("showMenuBarWidget") private var showMenuBarWidget = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @AppStorage(AppearanceManager.defaultsKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @State private var launcher = MenuBarLauncher.shared
    @State private var loginLauncher = LaunchAtLoginManager.shared
    @State private var updateState: UpdateUIState = .idle
    @State private var keptLanguages: Set<String> = []
    @State private var selectable: [(name: String, lprojs: [String])] = []
    @State private var languageSearch: String = ""

    /// Selectable languages filtered by the search field (case-insensitive).
    private var filteredLanguages: [(name: String, lprojs: [String])] {
        guard !languageSearch.isEmpty else { return selectable }
        return selectable.filter { $0.name.localizedCaseInsensitiveContains(languageSearch) }
    }

    var body: some View {
        Form {
            headerSection
            generalSection
            appearanceSection
            languageSection
            aboutSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .onAppear {
            keptLanguages = LanguagePreferences.userKept
            selectable = LanguagePreferences.selectableLanguages()
            Task.detached(priority: .userInitiated) {
                let found = LanguageScanner().discoverLproj(in: LanguageScanner.defaultRoots)
                await MainActor.run {
                    LanguagePreferences.discoveredLproj = found
                    selectable = LanguagePreferences.selectableLanguages()
                }
            }
        }
    }

    // MARK: - Header (version + update check)

    private var headerSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MCConstants.appName)
                        .font(.title2.weight(.semibold))
                    Text("Version \(MCConstants.appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                updateControl
            }
            if case .available(let version, let url) = updateState {
                updateAvailableRow(version: version, url: url)
            }
        }
    }

    @ViewBuilder
    private var updateControl: some View {
        switch updateState {
        case .idle:
            Button("Check for Updates") { startUpdateCheck() }
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Up to date")
            }
        case .available:
            EmptyView()   // detail rendered by updateAvailableRow
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Button("Retry") { startUpdateCheck() }
            }
        }
    }

    @ViewBuilder
    private func updateAvailableRow(version: String, url: URL) -> some View {
        if UpdateChecker.isHomebrewInstall() {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version \(version) is available. Update with Homebrew:")
                    Text(Self.brewUpgradeCommand)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.brewUpgradeCommand, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        } else {
            HStack {
                Text("Version \(version) is available.")
                Spacer()
                Button("View Release") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    static let brewUpgradeCommand = "brew upgrade --cask mac-sai"

    @MainActor
    private func startUpdateCheck() {
        updateState = .checking
        Task {
            let result = await UpdateChecker.check()
            switch result {
            case .upToDate:
                updateState = .upToDate
            case .updateAvailable(let version, let url):
                updateState = .available(version: version, url: url)
            case .failed(let message):
                updateState = .failed(message: message)
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section("General") {
            // Toggle flips instantly; the SMAppService round-trip runs in the
            // background with a spinner (no main-thread block, no lag).
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                    Text("Open \(MCConstants.appName) automatically when you sign in to macOS. You can also manage this in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if loginLauncher.isBusy {
                    ProgressView().controlSize(.small)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(loginLauncher.isBusy)
            }
            .animation(.easeInOut(duration: 0.18), value: loginLauncher.isBusy)
            .onChange(of: launchAtLogin) { _, newValue in
                Task { await loginLauncher.setEnabled(newValue) }
            }
            if loginLauncher.status == .requiresApproval {
                Label("Needs approval in System Settings → General → Login Items",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            if let err = loginLauncher.lastError {
                Label(err.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show \(MCConstants.appName) in the menu bar")
                    Text("Live CPU, memory, disk, battery, and network at the top of your screen. Click to expand the popover.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if launcher.isBusy {
                    ProgressView().controlSize(.small)
                }
                Toggle("Show \(MCConstants.appName) in the menu bar", isOn: $showMenuBarWidget)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(launcher.isBusy)
            }
            .animation(.easeInOut(duration: 0.18), value: launcher.isBusy)
            .onChange(of: showMenuBarWidget) { _, newValue in
                Task { await launcher.setEnabled(newValue) }
            }
            widgetStatusRow
            if let err = launcher.lastError {
                Label(err.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearanceRaw) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: appearanceRaw) { _, newValue in
                AppearanceManager.apply(AppearanceMode(rawValue: newValue) ?? .system)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove background colors")
                    Text("Replace module gradient backgrounds with a neutral dark color for better readability.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Remove background colors", isOn: $removeBackgroundColors)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Language Cleanup (carried over from the old Settings window)

    private var languageSection: some View {
        Section("Language Cleanup") {
            Text("English is always kept. Checked languages are preserved; unchecked language files can be removed by System Junk.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if selectable.isEmpty {
                Text("Detecting installed languages…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Search languages", text: $languageSearch)
                    .textFieldStyle(.roundedBorder)

                if filteredLanguages.isEmpty {
                    Text("No languages match “\(languageSearch)”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Fixed-height scroll box: ~100 languages would otherwise
                // stretch the page and push the About section out of reach.
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredLanguages, id: \.name) { lang in
                            // One toggle covers every folder variant of the
                            // language (e.g. "fr.lproj" + legacy "French.lproj").
                            HStack {
                                Text(lang.name)
                                Spacer()
                                Toggle(lang.name, isOn: Binding(
                                    get: { lang.lprojs.allSatisfy { keptLanguages.contains($0) } },
                                    set: { on in
                                        if on { keptLanguages.formUnion(lang.lprojs) }
                                        else { lang.lprojs.forEach { keptLanguages.remove($0) } }
                                        LanguagePreferences.userKept = keptLanguages
                                    }
                                ))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                            }
                            .padding(.vertical, 5)
                            .padding(.trailing, 6)
                            Divider().opacity(0.5)
                        }
                    }
                }
                .frame(height: 250)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            aboutRow(icon: "chevron.left.forwardslash.chevron.right", tint: .orange,
                     title: "Source code", caption: "Browse the codebase on GitHub",
                     url: MCConstants.repoURL)
            aboutRow(icon: "exclamationmark.bubble", tint: .blue,
                     title: "Report an issue", caption: "Bug reports and feature requests",
                     url: MCConstants.issuesURL)
            aboutRow(icon: "tag", tint: .green,
                     title: "Release notes", caption: "Changelog and previous versions",
                     url: MCConstants.releasesURL)
        }
    }

    private func aboutRow(icon: String, tint: Color, title: String, caption: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.18)).frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }

    // MARK: - Widget status (carried over from the old Settings window)

    @ViewBuilder
    private var widgetStatusRow: some View {
        HStack {
            Image(systemName: statusGlyph)
                .foregroundStyle(statusColor)
            Text("Widget status:")
                .foregroundStyle(.secondary)
            Text(statusText)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
        .font(.caption)
    }

    private var statusGlyph: String {
        switch launcher.statusSnapshot {
        case .enabled: return "checkmark.circle.fill"
        case .notRegistered: return "minus.circle"
        case .notFound: return "questionmark.circle"
        case .requiresApproval: return "exclamationmark.triangle.fill"
        @unknown default: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch launcher.statusSnapshot {
        case .enabled: return .green
        case .requiresApproval: return .orange
        default: return .secondary
        }
    }

    private var statusText: String {
        switch launcher.statusSnapshot {
        case .enabled: return "running"
        case .notRegistered: return "not registered"
        case .notFound: return "helper not found in bundle"
        case .requiresApproval: return "needs approval in System Settings → Login Items"
        @unknown default: return "unknown"
        }
    }
}
