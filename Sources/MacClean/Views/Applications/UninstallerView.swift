import SwiftUI
import AppKit
import MacCleanKit

struct UninstallerView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var apps: [AppInfo] = []
    @State private var selectedApp: AppInfo?
    @State private var associatedFiles: [FileItem] = []
    @State private var selectedFiles: Set<URL> = []
    @State private var isLoading = true
    @State private var isLoadingFiles = false
    @State private var isUninstalling = false
    @State private var appPendingUninstall: AppInfo?
    @State private var filter: AppFilter = .all
    @State private var searchText = ""

    enum AppFilter: String, CaseIterable {
        case all = "All"
        case unused = "Unused"
        case thirdParty = "Third Party"
    }

    private let discovery = AppDiscovery()
    private let pathFinder = AppPathFinder()
    private let safetyGuard = SafetyGuard()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uninstaller")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Completely remove apps and their leftover files")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.6))
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.primary)
                    Text("Discovering installed apps...")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.6))
                }
                Spacer()
            } else {
                HStack(spacing: 10) {
                    TextField("Search apps...", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("Filter", selection: $filter) {
                        ForEach(AppFilter.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                HSplitView {
                    appList
                        .frame(minWidth: 240)

                    if let app = selectedApp {
                        appDetailView(app)
                            .frame(minWidth: 280)
                    } else {
                        VStack {
                            Spacer()
                            Text("Select an app to see its files")
                                .foregroundStyle(.primary.opacity(0.4))
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .background {
                    if removeBackgroundColors { Color.clear }
                    else { Rectangle().fill(.ultraThinMaterial) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .task { await loadApps() }
        // Attached to the top-level body (not the conditionally-rendered
        // detail pane) so the confirmation can't be torn down mid-present
        // when selectedApp changes. `appPendingUninstall` is the anchor.
        .alert("Move \(appPendingUninstall?.name ?? "this app") to the Trash?",
               isPresented: Binding(get: { appPendingUninstall != nil },
                                    set: { if !$0 { appPendingUninstall = nil } }),
               presenting: appPendingUninstall) { app in
            Button("Cancel", role: .cancel) { appPendingUninstall = nil }
            Button("Move to Trash", role: .destructive) {
                let target = app; appPendingUninstall = nil; uninstall(target)
            }
        } message: { app in
            Text("\(app.name) and its associated files will be moved to the Trash. You can restore them from the Trash if needed.")
        }
    }

    private var filteredApps: [AppInfo] {
        var filtered = apps
        switch filter {
        case .all: break
        case .unused: filtered = filtered.filter(\.isUnused)
        case .thirdParty: filtered = filtered.filter { !$0.isAppleApp }
        }
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
            }
        }
        return filtered
    }

    private var appList: some View {
        List {
            ForEach(filteredApps) { app in
                Button {
                    selectedApp = app
                    loadAssociatedFiles(for: app)
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path(percentEncoded: false)))
                            .resizable()
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(app.formattedSize)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if app.isUnused {
                            Text("Unused")
                                .font(.system(size: 10))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                .background(selectedApp?.id == app.id ? Color.accentColor.opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .listStyle(.sidebar)
    }

    private func appDetailView(_ app: AppInfo) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path(percentEncoded: false)))
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.headline)
                    Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                    if let version = app.version {
                        Text("v\(version)").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()

                if safetyGuard.isProtectedApp(app.bundleIdentifier) {
                    Text("Protected system app — can't be removed")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.6))
                } else if isUninstalling {
                    // In-progress feedback: the button is gone (can't be
                    // re-tapped) and a spinner shows the work is happening.
                    ProgressView()
                        .controlSize(.small)
                    Text("Uninstalling…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Button("Uninstall") { appPendingUninstall = app }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)

                    Button("Reset") { resetSelection() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding()

            if isLoadingFiles {
                Spacer()
                ProgressView("Finding associated files...")
                    .tint(.secondary)
                    .font(.system(size: 12))
                Spacer()
            } else if !associatedFiles.isEmpty {
                let totalSize = associatedFiles.reduce(0 as UInt64) { $0 + $1.size }
                Text("\(associatedFiles.count) associated files (\(FileSizeFormatter.format(totalSize)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                List(associatedFiles) { file in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { selectedFiles.contains(file.url) },
                            set: { on in
                                if on { selectedFiles.insert(file.url) }
                                else { selectedFiles.remove(file.url) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        Image(systemName: file.isDirectory ? "folder" : "doc")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.name).font(.system(size: 12))
                            Text(file.url.deletingLastPathComponent().path(percentEncoded: false))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()
                        Text(file.formattedSize)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
            } else {
                Spacer()
                Text("No associated files found")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                Spacer()
            }
        }
    }

    private func resetSelection() {
        selectedApp = nil
        associatedFiles = []
        selectedFiles = []
        isLoadingFiles = false
    }

    private func loadApps() async {
        apps = await discovery.discoverApps()
        isLoading = false
    }

    private func loadAssociatedFiles(for app: AppInfo) {
        isLoadingFiles = true
        associatedFiles = []
        Task {
            let files = pathFinder.findAssociatedFiles(for: app)
            associatedFiles = files
            selectedFiles = Set(files.map(\.url))
            isLoadingFiles = false
        }
    }

    private func uninstall(_ app: AppInfo) {
        guard !isUninstalling else { return }   // ignore double-taps
        isUninstalling = true
        Task {
            try? FileManager.default.trashItem(at: app.path, resultingItemURL: nil)
            _ = await CleanActions.executeUserClean(
                items: associatedFiles,
                selectedItems: selectedFiles,
                engine: appState.cleaningEngine
            )
            await loadApps()
            isUninstalling = false
            selectedApp = nil
            associatedFiles = []
        }
    }
}
