import AppKit
import SwiftUI
import MacCleanKit

struct AppPermissionsView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var snapshot = AppPermissionsSnapshot(grants: [], listing: .loaded)
    @State private var isLoading = true
    private let client = AppPermissionsClient.live()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("应用权限", "App Permissions", "Разрешения приложений"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(L10n.tr(
                        "查看哪些应用获得了隐私权限。撤销在“系统设置”中完成。",
                        "See which apps hold privacy permissions. Revoke them in System Settings.",
                        "Смотрите, каким приложениям выданы разрешения. Отзывать их нужно в Системных настройках."
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
                .disabled(isLoading)
                .help(L10n.tr("重新读取权限列表", "Reload the permission list", "Заново прочитать список разрешений"))
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
                        Text(L10n.tr("正在读取权限…", "Reading permissions…", "Чтение разрешений…"))
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
        .respondsToModuleShortcuts(onScan: { Task { await reload() } }, canScan: !isLoading)
    }

    private var list: some View {
        List {
            if snapshot.listing != .loaded {
                listingBanner
            }
            ForEach(PrivacyPermission.allCases) { permission in
                let grants = snapshot.grants.filter { $0.permission == permission }
                Section {
                    if grants.isEmpty {
                        Text(L10n.tr("未列出任何应用", "No apps listed", "Приложения не показаны"))
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.4))
                    } else {
                        ForEach(grants) { grant in
                            grantRow(grant)
                        }
                    }
                } header: {
                    HStack {
                        Label(permissionTitle(permission), systemImage: permissionIcon(permission))
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button(L10n.tr("打开设置", "Open Settings", "Открыть настройки")) {
                            client.openSettings(for: permission)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var listingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                snapshot.listing == .needsFullDiskAccess
                    ? L10n.tr("需要完全磁盘访问权限", "Full Disk Access needed", "Требуется полный доступ к диску")
                    : L10n.tr("无法读取权限数据库", "Couldn't read the permission database", "Не удалось прочитать базу разрешений")
            )
            .font(.system(size: 13, weight: .semibold))
            Text(
                snapshot.listing == .needsFullDiskAccess
                    ? L10n.tr(
                        "macOS 正在阻止读取列表。请为 \(MCConstants.appName) 授予完全磁盘访问权限，然后刷新。类别按钮仍可打开系统设置。",
                        "macOS is blocking the list. Grant \(MCConstants.appName) Full Disk Access, then refresh. Category buttons still open System Settings.",
                        "macOS блокирует список. Предоставьте \(MCConstants.appName) полный доступ к диску и обновите. Кнопки категорий по-прежнему открывают Системные настройки."
                    )
                    : L10n.tr(
                        "macOS 不允许列出 приложения。仍可通过各类别打开系统设置并在那里撤销权限。",
                        "macOS won't let this app list grants. You can still open System Settings for each category and revoke there.",
                        "macOS не даёт показать список. По-прежнему можно открыть Системные настройки по категориям и отозвать разрешения там."
                    )
            )
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.7))
            if snapshot.listing == .needsFullDiskAccess {
                Button(L10n.tr("打开设置", "Open Settings", "Открыть настройки")) {
                    client.openFullDiskAccessSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }

    private func grantRow(_ grant: AppPermissionGrant) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon(for: grant))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(displayName(for: grant))
                        .font(.system(size: 13, weight: .medium))
                    if grant.isLimited {
                        Text(L10n.tr("受限", "Limited", "Ограничено"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle(for: grant))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(L10n.tr("打开设置", "Open Settings", "Открыть настройки")) {
                client.openSettings(for: grant.permission)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func reload() async {
        isLoading = true
        snapshot = await client.load()
        isLoading = false
    }

    private func permissionTitle(_ permission: PrivacyPermission) -> String {
        switch permission {
        case .camera: L10n.tr("相机", "Camera", "Камера")
        case .microphone: L10n.tr("麦克风", "Microphone", "Микрофон")
        case .fullDiskAccess: L10n.tr("完全磁盘访问权限", "Full Disk Access", "Полный доступ к диску")
        case .screenRecording: L10n.tr("屏幕录制", "Screen Recording", "Запись экрана")
        case .automation: L10n.tr("自动化", "Automation", "Автоматизация")
        }
    }

    private func permissionIcon(_ permission: PrivacyPermission) -> String {
        switch permission {
        case .camera: "web.camera"
        case .microphone: "mic"
        case .fullDiskAccess: "externaldrive"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .automation: "gearshape.2"
        }
    }

    private func displayName(for grant: AppPermissionGrant) -> String {
        if grant.clientIsPath {
            return URL(filePath: grant.client).deletingPathExtension().lastPathComponent
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: grant.client) {
            return FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        }
        return grant.client
    }

    private func subtitle(for grant: AppPermissionGrant) -> String {
        if let target = grant.indirectObjectIdentifier, !target.isEmpty {
            return "\(grant.client) → \(target)"
        }
        if grant.clientIsPath {
            return grant.client
        }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: grant.client) == nil {
            return L10n.tr("未找到应用", "App not found", "Приложение не найдено")
        }
        return grant.client
    }

    private func icon(for grant: AppPermissionGrant) -> NSImage {
        if grant.clientIsPath {
            return NSWorkspace.shared.icon(forFile: grant.client)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: grant.client) {
            return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        }
        return NSWorkspace.shared.icon(forFileType: "app")
    }
}
