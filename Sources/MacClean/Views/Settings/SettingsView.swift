import SwiftUI
import ServiceManagement
import MacCleanKit

struct SettingsView: View {
    @AppStorage("showMenuBarWidget") private var showMenuBarWidget = true
    @State private var launcher = MenuBarLauncher.shared
    @State private var refreshTick = 0
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
            Section {
                Toggle(isOn: $showMenuBarWidget) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Mac Clean in the menu bar")
                        Text("Live CPU, memory, disk, battery, and network at the top of your screen. Click to expand the popover.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: showMenuBarWidget) { _, newValue in
                    launcher.setEnabled(newValue)
                    refreshTick &+= 1
                }

                statusRow
                if let err = launcher.lastError {
                    Label(err.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            } header: {
                Text("Menu Bar")
            }
            Section {
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
                    ForEach(filteredLanguages, id: \.name) { lang in
                        // One toggle covers every folder variant of the
                        // language (e.g. "fr.lproj" + legacy "French.lproj").
                        Toggle(lang.name, isOn: Binding(
                            get: { lang.lprojs.allSatisfy { keptLanguages.contains($0) } },
                            set: { on in
                                if on { keptLanguages.formUnion(lang.lprojs) }
                                else { lang.lprojs.forEach { keptLanguages.remove($0) } }
                                LanguagePreferences.userKept = keptLanguages
                            }
                        ))
                    }
                }
            } header: {
                Text("Language Cleanup")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
        .id(refreshTick)
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

    @ViewBuilder
    private var statusRow: some View {
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
        switch launcher.status {
        case .enabled: return "checkmark.circle.fill"
        case .notRegistered: return "minus.circle"
        case .notFound: return "questionmark.circle"
        case .requiresApproval: return "exclamationmark.triangle.fill"
        @unknown default: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch launcher.status {
        case .enabled: return .green
        case .requiresApproval: return .orange
        default: return .secondary
        }
    }

    private var statusText: String {
        switch launcher.status {
        case .enabled: return "running"
        case .notRegistered: return "not registered"
        case .notFound: return "helper not found in bundle"
        case .requiresApproval: return "needs approval in System Settings → Login Items"
        @unknown default: return "unknown"
        }
    }
}
