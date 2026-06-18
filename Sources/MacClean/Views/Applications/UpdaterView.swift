import SwiftUI
import AppKit
import MacCleanKit

struct UpdaterView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var updates: [AppUpdateChecker.AppUpdate] = []
    @State private var isChecking = false
    @State private var hasChecked = false
    @State private var apps: [AppInfo] = []
    /// Update rows currently mid-action — drives the per-row spinner + disable.
    @State private var updatingIDs: Set<UUID> = []

    private let discovery = AppDiscovery()
    private let checker = AppUpdateChecker()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("应用更新", "Updater"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(L10n.tr("检查可用的应用更新", "Check for available app updates"))
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.6))
                }
                Spacer()
                if !isChecking {
                    Button(hasChecked ? L10n.tr("重新检查", "Recheck") : L10n.tr("检查更新", "Check for Updates")) {
                        checkUpdates()
                    }
                    .buttonStyle(SuperEllipseButtonStyle(
                        gradient: ModuleTheme.applications.buttonGradient,
                        size: CGSize(width: hasChecked ? 100 : 160, height: 34)
                    ))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if isChecking {
                Spacer()
                ScanProgressRing(progress: 0.5, phase: L10n.tr("正在检查更新...", "Checking for updates..."), theme: .applications)
                Spacer()
            } else if hasChecked && updates.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.primary.opacity(0.8))
                    Text(L10n.tr("所有应用均为最新", "All apps are up to date"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                Spacer()
            } else if !updates.isEmpty {
                List {
                    ForEach(updates) { update in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: update.app.path.path(percentEncoded: false)))
                                .resizable()
                                .frame(width: 26, height: 26)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(update.app.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text("\(update.currentVersion) → \(update.availableVersion ?? "?")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if updatingIDs.contains(update.id) {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 60)
                            } else {
                                Button(L10n.tr("更新", "Update")) { startUpdate(update) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .background {
                    if removeBackgroundColors { Color.clear }
                    else { Rectangle().fill(.ultraThinMaterial) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            } else {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 44))
                        .foregroundStyle(.primary.opacity(0.4))
                    Text(L10n.tr("点击上方按钮检查更新", "Click above to check for updates"))
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.55))
                }
                Spacer()
            }
        }
    }

    private func checkUpdates() {
        isChecking = true
        Task {
            apps = await discovery.discoverApps()
            updates = await checker.checkForUpdates(apps: apps)
            isChecking = false
            hasChecked = true
        }
    }

    /// Flip the row to a spinner + disable it the instant Update is tapped,
    /// fire the action, then hold the indicator briefly so the user clearly
    /// sees that the tap registered and something is happening.
    private func startUpdate(_ update: AppUpdateChecker.AppUpdate) {
        guard !updatingIDs.contains(update.id) else { return }
        updatingIDs.insert(update.id)
        Task {
            UpdaterActions.perform(update)
            try? await Task.sleep(for: .milliseconds(1200))
            updatingIDs.remove(update.id)
        }
    }
}
