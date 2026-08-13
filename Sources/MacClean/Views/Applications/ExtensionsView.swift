import AppKit
import SwiftUI
import MacCleanKit

struct ExtensionsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var items: [ManagedExtension] = []
    @State private var isLoading = true
    @State private var isRemoving = false
    @State private var pendingRemove: ManagedExtension?
    @State private var errorMessage: String?
    private let client = ManagedExtensionsClient.live()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("扩展", "Extensions", "Расширения"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(L10n.tr(
                        "查看第三方偏好设置面板、Internet 插件和 Safari 扩展。用户安装的面板和插件可移到废纸篓。",
                        "Review third-party preference panes, Internet Plug-Ins, and Safari extensions. User-installed panes and plug-ins can go to the Trash.",
                        "Просматривайте сторонние панели настроек, интернет-плагины и расширения Safari. Установленные пользователем панели и плагины можно переместить в Корзину."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.6))
                }
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Label(L10n.tr("刷新", "Refresh", "Обновить"), systemImage: "arrow.clockwise")
                }
                .disabled(isLoading || isRemoving)
                .help(L10n.tr("重新读取扩展列表", "Reload the extension list", "Заново прочитать список расширений"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .controlSize(.large)
                            .tint(.primary)
                        Text(L10n.tr("正在查找扩展…", "Looking for extensions…", "Поиск расширений…"))
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.6))
                        Spacer()
                    }
                } else {
                    list
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
        .task { await reload() }
        .respondsToModuleShortcuts(
            onScan: { Task { await reload() } },
            canScan: !isLoading && !isRemoving
        )
        .alert(
            L10n.tr("移到废纸篓？", "Move to Trash?", "Переместить в Корзину?"),
            isPresented: Binding(
                get: { pendingRemove != nil },
                set: { if !$0 { pendingRemove = nil } }
            ),
            presenting: pendingRemove
        ) { item in
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) { pendingRemove = nil }
            Button(L10n.tr("移到废纸篓", "Move to Trash", "Переместить в Корзину"), role: .destructive) {
                let captured = item
                pendingRemove = nil
                Task { await remove(captured) }
            }
        } message: { item in
            Text(L10n.tr(
                "\(item.name) 将被移到废纸篓。如有需要，你可以从废纸篓恢复。",
                "\(item.name) will be moved to the Trash. You can restore it from the Trash if needed.",
                "«\(item.name)» будет перемещено в Корзину. При необходимости его можно восстановить."
            ))
        }
        .alert(
            L10n.tr("扩展", "Extensions", "Расширения"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(L10n.tr("好", "OK"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var list: some View {
        List {
            if items.isEmpty {
                Text(L10n.tr(
                    "未找到第三方扩展、插件或偏好设置面板。",
                    "No third-party extensions, plug-ins, or preference panes found.",
                    "Сторонние расширения, плагины и панели настроек не найдены."
                ))
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.4))
                .listRowSeparator(.hidden)
            } else {
                section(
                    kind: .preferencePane,
                    title: L10n.tr("偏好设置面板", "Preference Panes", "Панели настроек"),
                    icon: "slider.horizontal.3"
                )
                section(
                    kind: .internetPlugin,
                    title: L10n.tr("Internet 插件", "Internet Plug-Ins", "Интернет-плагины"),
                    icon: "puzzlepiece.extension"
                )
                safariSection
            }
        }
        .listStyle(.inset)
    }

    private var safariSection: some View {
        let rows = items.filter { $0.kind == .safariExtension }
        return Section {
            if rows.isEmpty {
                Text(L10n.tr("未列出任何 Safari 扩展", "No Safari extensions listed", "Расширения Safari не показаны"))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.4))
            } else {
                ForEach(rows) { item in
                    row(item)
                }
            }
            Text(L10n.tr(
                "Safari 扩展不能在本应用内开启、关闭或删除，以免破坏宿主应用的签名。请在 Safari 设置中管理它们。",
                "Safari extensions can't be turned on, off, or deleted here — that would break the host app's signature. Manage them in Safari Settings.",
                "Расширения Safari нельзя включать, выключать или удалять здесь — это сломает подпись приложения-хоста. Управляйте ими в настройках Safari."
            ))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        } header: {
            HStack {
                Label(
                    L10n.tr("Safari 扩展", "Safari Extensions", "Расширения Safari"),
                    systemImage: "safari"
                )
                .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(L10n.tr("打开 Safari 设置", "Open Safari Settings", "Открыть настройки Safari")) {
                    client.openSafariSettings()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func section(kind: ManagedExtensionKind, title: String, icon: String) -> some View {
        let rows = items.filter { $0.kind == kind }
        return Section {
            if rows.isEmpty {
                Text(L10n.tr("未找到项目", "Nothing found", "Ничего не найдено"))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.4))
            } else {
                ForEach(rows) { item in
                    row(item)
                }
            }
        } header: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
        }
    }

    private func row(_ item: ManagedExtension) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path.path(percentEncoded: false)))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                    if item.election == .enabled {
                        Text(L10n.tr("已启用", "On", "Вкл."))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    } else if item.election == .disabled {
                        Text(L10n.tr("已停用", "Off", "Выкл."))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle(for: item))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            actions(for: item)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func actions(for item: ManagedExtension) -> some View {
        let action = client.removal(for: item)
        if item.kind == .safariExtension, action == .none {
            Button(L10n.tr("打开设置", "Open Settings", "Открыть настройки")) {
                client.openSafariSettings()
            }
            .buttonStyle(.borderless)
            if let host = item.hostAppPath {
                Button(L10n.tr("显示宿主应用", "Show Host App", "Показать приложение")) {
                    client.revealInFinder(host)
                }
                .buttonStyle(.borderless)
            }
        } else {
            Button(L10n.tr("在 Finder 中显示", "Reveal in Finder", "Показать в Finder")) {
                client.revealInFinder(item.path)
            }
            .buttonStyle(.borderless)
            if action == .trash {
                Button(L10n.tr("移除", "Remove", "Удалить")) {
                    pendingRemove = item
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .disabled(isRemoving)
            }
        }
    }

    private func subtitle(for item: ManagedExtension) -> String {
        let location = item.domain == .user
            ? L10n.tr("用户", "User", "Пользователь")
            : L10n.tr("这台 Mac", "This Mac", "Этот Mac")
        if let host = item.hostAppPath {
            return "\(location) · \(host.deletingPathExtension().lastPathComponent)"
        }
        if !item.bundleIdentifier.isEmpty {
            return "\(location) · \(item.bundleIdentifier)"
        }
        return location
    }

    private func reload() async {
        isLoading = true
        items = await client.load()
        isLoading = false
    }

    private func remove(_ item: ManagedExtension) async {
        guard !isRemoving else { return }
        isRemoving = true
        let urls = client.trashURLs(from: [item])
        guard !urls.isEmpty else {
            errorMessage = L10n.tr(
                "出于安全考虑，已拒绝移除此项目。",
                "This item was refused for safety reasons.",
                "Удаление этого объекта отклонено из соображений безопасности."
            )
            isRemoving = false
            return
        }
        let fileItems = urls.map { url in
            FileItem(
                url: url,
                name: url.lastPathComponent,
                size: 0,
                allocatedSize: 0,
                isDirectory: true,
                isPackage: true
            )
        }
        let result = await CleanActions.executeUserClean(
            items: fileItems,
            selectedItems: Set(urls),
            engine: appState.cleaningEngine
        )
        if !result.errors.isEmpty {
            errorMessage = L10n.tr(
                "无法将 \(item.name) 移到废纸篓。",
                "Couldn't move \(item.name) to the Trash.",
                "Не удалось переместить «\(item.name)» в Корзину."
            )
        }
        await reload()
        isRemoving = false
    }
}
