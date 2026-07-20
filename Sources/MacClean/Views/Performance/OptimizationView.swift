import SwiftUI
import MacCleanKit

struct OptimizationView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var loginItems: [AutoStartItem] = []
    @State private var launchAgents: [AutoStartItem] = []
    @State private var launchDaemons: [AutoStartItem] = []
    @State private var selectedTab = 0
    @State private var isLoading = true
    @State private var showAlert = false
    @State private var alertMessage = ""

    private let manager = AutoStartManager()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("优化", "Optimization", "Оптимизация"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(L10n.tr("管理启动项和后台进程", "Manage startup items and background processes", "Управление автозапуском и фоновыми процессами"))
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.6))
                }
                Spacer()
                // The view is kept alive across navigation, so `.task` only runs
                // once and the list would otherwise go stale (issue #93: rescans
                // showed old data until the app was relaunched). This button
                // re-reads login items and launch agents from disk on demand.
                Button {
                    refresh()
                } label: {
                    Label(L10n.tr("刷新", "Refresh", "Обновить"), systemImage: "arrow.clockwise")
                }
                .help(L10n.tr("重新扫描启动项", "Rescan startup items", "Повторно проверить объекты автозапуска"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Picker(L10n.tr("分区", "Section", "Раздел"), selection: $selectedTab) {
                Text(L10n.tr("登录项", "Login Items", "Объекты входа")).tag(0)
                Text(L10n.tr("启动代理", "Launch Agents", "Агенты запуска")).tag(1)
                Text(L10n.tr("启动守护进程", "Launch Daemons", "Демоны запуска")).tag(2)
                Text(L10n.tr("文件打开方式", "File Associations", "Связи файлов")).tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            Group {
                if selectedTab == 3 {
                    FileHandlerView()
                } else if isLoading {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .controlSize(.large)
                            .tint(.primary)
                        Text(L10n.tr("正在加载项目...", "Loading items...", "Загрузка объектов..."))
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.6))
                        Spacer()
                    }
                } else {
                    Group {
                        switch selectedTab {
                        case 0:  itemList(items: loginItems)
                        case 1:  itemList(items: launchAgents)
                        case 2:  itemList(items: launchDaemons)
                        default: itemList(items: loginItems)
                        }
                    }
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
        .alert(alertMessage, isPresented: $showAlert) {
            Button("OK") { showAlert = false }
        }
        .task { refresh() }
    }

    // MARK: - Item List

    @ViewBuilder
    private func itemList(items: [AutoStartItem]) -> some View {
        if items.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text(L10n.tr("没有找到项目", "No items found", "Объекты не найдены"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(items, id: \.id) { item in
                    ItemRow(item: item, onToggle: { newVal in
                        do {
                            try manager.toggleItem(item, enabled: newVal)
                            refresh()
                        } catch {
                            alertMessage = error.localizedDescription
                            showAlert = true
                        }
                    }, onOpenConfig: {
                        manager.openConfigInFinder(item)
                    })
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Refresh

    private func refresh() {
        loginItems = manager.getLoginItems()
        launchAgents = manager.getLaunchAgents()
        launchDaemons = manager.getLaunchDaemons()
        isLoading = false
    }
}

// MARK: - Item Row

private struct ItemRow: View {
    let item: AutoStartItem
    let onToggle: (Bool) -> Void
    let onOpenConfig: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // App Icon
            if let bid = item.bundleIdentifier,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 28, height: 28)
            } else if let path = item.programPath,
                      FileManager.default.fileExists(atPath: path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
            }

            // Name and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // Source type badge
                    Text(item.sourceType.localizedName)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(sourceTypeColor.opacity(0.2))
                        .foregroundStyle(sourceTypeColor)
                        .clipShape(Capsule())

                    if item.isSystem {
                        Text(L10n.tr("系统", "System", "Системный"))
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 0)

            // Toggle (or lock for read-only system items)
            if item.sourceType != .loginItem && item.isSystem {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Toggle("", isOn: Binding(
                    get: { item.isEnabled },
                    set: { onToggle($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // Folder button (right of toggle)
            if item.hasConfigFile {
                Button(action: onOpenConfig) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .help(L10n.tr("在 Finder 中查看配置文件", "Show config in Finder", "Показать файл конфигурации в Finder"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private var sourceTypeColor: Color {
        switch item.sourceType {
        case .loginItem:    return .blue
        case .launchAgent:  return .orange
        case .launchDaemon: return .purple
        }
    }
}
