import AppKit
import SwiftUI
import MacCleanKit

struct AppPermissionsView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var snapshot = AppPermissionsSnapshot(grants: [], listing: .loaded)
    @State private var isLoading = true
    private let client = AppPermissionsClient.live()

    private var apps: [AppPermissionApp] {
        AppPermissionOverview.apps(from: snapshot.grants)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("权限总览", "Permissions", "Обзор разрешений"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(L10n.tr(
                        "按应用查看持有哪些隐私权限。这是只读列表——按钮会打开系统设置。本应用无法关闭权限。",
                        "See which privacy grants each app holds. This list is read-only — buttons open System Settings. Mac Sai cannot turn a permission off.",
                        "Смотрите, какие разрешения есть у каждого приложения. Список только для чтения — кнопки открывают Системные настройки. Это приложение не может выключить разрешение."
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

            if snapshot.listing == .loaded {
                if apps.isEmpty {
                    Text(L10n.tr(
                        "未列出任何应用。",
                        "No apps listed.",
                        "Приложения не показаны."
                    ))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.4))
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(apps) { app in
                        appSection(app)
                    }
                }
            }

            settingsJumpSection
        }
        .listStyle(.inset)
    }

    private func appSection(_ app: AppPermissionApp) -> some View {
        Section {
            ForEach(app.grants) { grant in
                grantRow(grant)
            }
        } header: {
            HStack(spacing: 8) {
                Image(nsImage: icon(for: app))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(displayName(for: app))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(grantCountLabel(app.grants.count))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func grantRow(_ grant: AppPermissionGrant) -> some View {
        HStack(spacing: 10) {
            Image(systemName: permissionIcon(grant.permission))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(permissionTitle(grant.permission))
                        .font(.system(size: 13, weight: .medium))
                    if grant.isLimited {
                        Text(L10n.tr("受限", "Limited", "Ограничено"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if let target = grant.indirectObjectIdentifier, !target.isEmpty {
                    Text(L10n.tr("控制 \(target)", "Controls \(target)", "Управляет \(target)"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button(L10n.tr("在系统设置中打开", "Open in System Settings", "Открыть в Системных настройках")) {
                client.openSettings(for: grant.permission)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private var settingsJumpSection: some View {
        Section {
            ForEach(PrivacyPermission.allCases) { permission in
                Button {
                    client.openSettings(for: permission)
                } label: {
                    HStack {
                        Label(permissionTitle(permission), systemImage: permissionIcon(permission))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(L10n.tr("在系统设置中打开", "Open in System Settings", "Открыть в Системных настройках"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(L10n.tr("在系统设置中打开类别", "Open a category in System Settings", "Открыть категорию в Системных настройках"))
                .font(.system(size: 13, weight: .semibold))
        } footer: {
            Text(L10n.tr(
                "更改权限只能在系统设置中完成。",
                "Changing a grant can only be done in System Settings.",
                "Изменить разрешение можно только в Системных настройках."
            ))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private var listingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                snapshot.listing == .needsFullDiskAccess
                    ? L10n.tr("需要完全磁盘访问权限才能列出应用", "Full Disk Access needed to list apps", "Чтобы показать приложения, нужен полный доступ к диску")
                    : L10n.tr("无法读取权限数据库", "Couldn't read the permission database", "Не удалось прочитать базу разрешений")
            )
            .font(.system(size: 13, weight: .semibold))
            Text(
                snapshot.listing == .needsFullDiskAccess
                    ? L10n.tr(
                        "macOS 正在阻止按应用汇总。请为 \(MCConstants.appName) 授予完全磁盘访问权限，然后刷新。下方按钮仍会打开系统设置。",
                        "macOS is blocking the by-app overview. Grant \(MCConstants.appName) Full Disk Access, then refresh. The buttons below still open System Settings.",
                        "macOS блокирует сводку по приложениям. Предоставьте \(MCConstants.appName) полный доступ к диску и обновите. Кнопки ниже по-прежнему открывают Системные настройки."
                    )
                    : L10n.tr(
                        "无法列出哪些应用持有哪些权限。仍可通过下方按钮打开系统设置。",
                        "This app can't list which apps hold which grants. You can still open System Settings with the buttons below.",
                        "Не получается показать, какие приложения какими разрешениями владеют. По-прежнему можно открыть Системные настройки кнопками ниже."
                    )
            )
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.7))
            if snapshot.listing == .needsFullDiskAccess {
                Button(L10n.tr("在系统设置中打开", "Open in System Settings", "Открыть в Системных настройках")) {
                    client.openFullDiskAccessSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }

    private func reload() async {
        isLoading = true
        snapshot = await client.load()
        isLoading = false
    }

    private func grantCountLabel(_ count: Int) -> String {
        L10n.tr(
            "\(count) 项权限",
            count == 1 ? "1 grant" : "\(count) grants",
            "\(count) \(L10n.russianPlural(count, one: "разрешение", few: "разрешения", many: "разрешений"))"
        )
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

    private func displayName(for app: AppPermissionApp) -> String {
        if app.clientIsPath {
            return URL(filePath: app.client).deletingPathExtension().lastPathComponent
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.client) {
            return FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        }
        return app.client
    }

    private func icon(for app: AppPermissionApp) -> NSImage {
        if app.clientIsPath {
            return NSWorkspace.shared.icon(forFile: app.client)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.client) {
            return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        }
        return NSWorkspace.shared.icon(forFileType: "app")
    }
}
