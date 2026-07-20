import SwiftUI
import AppKit
import MacCleanKit

@main
struct MacCleanMenuApp: App {
    init() {
        AppLanguage.registerDefault(.system)
        // Single-instance enforcement. macOS does NOT auto-deduplicate
        // LSUIElement apps by bundle id the way it does for regular apps,
        // and we have two launch paths (SMAppService + NSWorkspace). If a
        // sibling instance is already running, terminate self immediately
        // so the user never sees two icons in the menu bar.
        // Only enforce when we have a real bundle id (i.e. running from
        // the .app). Under `swift run` the bare executable has no bundle
        // id, and matching against other nil-bundle processes would make
        // the dev build exit immediately.
        if let myBundleID = Bundle.main.bundleIdentifier {
            let myPID = ProcessInfo.processInfo.processIdentifier
            let duplicate = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == myBundleID && $0.processIdentifier != myPID
            }
            if duplicate { exit(0) }
        }
    }

    // Polling runs continuously from launch in MenuStatsModel (started by the
    // app delegate), NOT from the popover's onAppear (see MenuStatsModel for
    // why). The App just observes the model and renders it.
    @NSApplicationDelegateAdaptor(MenuAppDelegate.self) private var appDelegate
    @State private var model = MenuStatsModel.shared
    @AppStorage(AppLanguage.defaultsKey, store: SharedAppState.defaults) private var appLanguageRaw = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .fallback
    }

    /// Menu-bar label icon: the Mac Sai vacuum, in color, at 18px.
    /// Rendered as a normal (non-template) image so it shows the brand
    /// colors instead of being flattened to a monochrome mask.
    private static let labelIcon: NSImage = {
        let img = VacuumAsset.image.copy() as! NSImage
        img.isTemplate = false
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(
                stats: model.stats,
                networkSpeed: model.networkSpeed,
                devices: model.devices,
                protection: model.protection,
                tips: model.tips,
                onDismissTip: { model.dismissTip(id: $0) }
            )
            .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
            .id(appLanguage.rawValue)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: Self.labelIcon)
                    .renderingMode(.original)
                if let stats = model.stats {
                    Text(FileSizeFormatter.format(stats.diskFree))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Palette

enum MenuPalette {
    static let bgTop = Color(red: 0.33, green: 0.18, blue: 0.55)
    static let bgBottom = Color(red: 0.13, green: 0.08, blue: 0.28)
    static let card = Color(red: 0.10, green: 0.07, blue: 0.22)
    static let teal = Color(red: 0.40, green: 0.85, blue: 0.82)
    static let yellow = Color(red: 0.98, green: 0.82, blue: 0.30)
    static let green = Color(red: 0.24, green: 0.80, blue: 0.47)
    static let red = Color(red: 0.93, green: 0.33, blue: 0.34)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.58)

    static func barColor(_ v: Double) -> Color {
        if v > 0.85 { return Color(red: 0.98, green: 0.42, blue: 0.45) }   // soft red
        if v > 0.65 { return yellow }
        return teal
    }
}

// MARK: - Popover

struct MenuContentView: View {
    let stats: SystemStatsCollector.SystemStats?
    let networkSpeed: NetworkSpeedMonitor.NetworkSpeed?
    let devices: ConnectedDevices?
    let protection: SharedAppState.ProtectionStatus?
    let tips: [TipsEngine.Tip]
    let onDismissTip: (String) -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [MenuPalette.bgTop, MenuPalette.bgBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                if let stats {
                    statGrid(stats)
                    networkCard(stats)
                    if !tips.isEmpty { recommendationsCard }
                    if let p = protection { protectionCard(p) }
                    if let d = devices, d.hasAny { devicesCard(d) }
                } else {
                    ProgressView().controlSize(.small).tint(.white)
                        .frame(height: 100)
                }
                footer
            }
            .padding(14)
        }
        .frame(width: 340)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: VacuumAsset.image)
                .resizable().interpolation(.high)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(MCConstants.appName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MenuPalette.textPrimary)
                Text(L10n.tr("实时系统状态", "Live system stats", "Состояние системы"))
                    .font(.system(size: 10))
                    .foregroundStyle(MenuPalette.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: Stat grid (rings)

    private func statGrid(_ s: SystemStatsCollector.SystemStats) -> some View {
        let diskUsed = s.diskTotal > 0 ? Double(s.diskTotal - s.diskFree) / Double(s.diskTotal) : 0
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ringCard(icon: "cpu", label: "CPU",
                     value: s.cpuUsage, center: "\(Int((s.cpuUsage*100).rounded()))%",
                     sub: nil)
            ringCard(icon: "memorychip", label: L10n.tr("内存", "Memory", "Память"),
                     value: s.memoryPressure, center: "\(Int((s.memoryPressure*100).rounded()))%",
                     sub: FileSizeFormatter.format(s.memoryUsed))
            ringCard(icon: "internaldrive", label: L10n.tr("磁盘", "Disk", "Диск"),
                     value: diskUsed, center: "\(Int((diskUsed*100).rounded()))%",
                     sub: L10n.tr("\(FileSizeFormatter.format(s.diskFree)) 可用", "\(FileSizeFormatter.format(s.diskFree)) free", "Свободно: \(FileSizeFormatter.format(s.diskFree))"))
            if let level = s.batteryLevel {
                ringCard(icon: s.batteryIsCharging ? "battery.100.bolt" : "battery.75",
                         label: s.batteryIsCharging ? L10n.tr("充电中", "Charging", "Заряжается") : L10n.tr("电池", "Battery", "Аккумулятор"),
                         value: level, center: "\(Int((level*100).rounded()))%",
                         sub: nil, forceColor: level > 0.2 ? MenuPalette.teal : Color(red:0.98,green:0.42,blue:0.45))
            } else {
                uptimeCard(s)
            }
        }
    }

    private func ringCard(icon: String, label: String, value: Double, center: String, sub: String?, forceColor: Color? = nil) -> some View {
        let color = forceColor ?? MenuPalette.barColor(value)
        return VStack(spacing: 12) {
            statHeader(icon: icon, label: label, tint: color)
            RingGauge(value: value, color: color, center: center)
                .frame(width: 58, height: 58)
            // Always render the subtitle line (a space when empty) so
            // every card is the same height and the rings line up.
            Text(sub ?? " ")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MenuPalette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(16)
        .glassCard()
    }

    private func uptimeCard(_ s: SystemStatsCollector.SystemStats) -> some View {
        VStack(spacing: 12) {
            statHeader(icon: "clock", label: L10n.tr("运行时间", "Uptime", "Время работы"), tint: MenuPalette.teal)
            Text(formatUptime(s.uptime))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(height: 58)
            Text(" ").font(.system(size: 10, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(16)
        .glassCard()
    }

    /// Card header: icon + label, centered horizontally above the ring
    /// (no Spacer, so the VStack centers the group).
    private func statHeader(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(MenuPalette.textPrimary)
        }
    }

    // MARK: Network strip

    private func networkCard(_ s: SystemStatsCollector.SystemStats) -> some View {
        HStack(spacing: 0) {
            if let net = networkSpeed {
                netCell(icon: "arrow.down", color: MenuPalette.teal, value: net.formattedIn)
                divider
                netCell(icon: "arrow.up", color: MenuPalette.yellow, value: net.formattedOut)
                divider
            }
            netCell(icon: "clock", color: MenuPalette.textSecondary, value: formatUptime(s.uptime))
            if s.swapUsed > 0 {
                divider
                netCell(icon: "arrow.triangle.swap", color: MenuPalette.textSecondary, value: FileSizeFormatter.format(s.swapUsed))
            }
        }
        .padding(.vertical, 9)
        .glassCard()
    }

    private func netCell(icon: String, color: Color, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            Text(value).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1, height: 18)
    }

    // MARK: Recommendations

    private var recommendationsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader(icon: "sparkles", title: L10n.tr("建议", "Recommendations", "Рекомендации"), tint: MenuPalette.yellow)
            ForEach(tips.prefix(3)) { tip in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: tip.symbol).font(.system(size: 12)).foregroundStyle(MenuPalette.teal).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tip.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                            Text(tip.body).font(.system(size: 10)).foregroundStyle(MenuPalette.textSecondary).lineLimit(2)
                        }
                        Spacer(minLength: 2)
                        Button { onDismissTip(tip.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                .foregroundStyle(MenuPalette.textSecondary).padding(4)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }.buttonStyle(.plain).help(L10n.tr("30 天内不再显示", "Dismiss for 30 days", "Скрыть на 30 дней"))
                    }
                    Button { TipAction.open(moduleID: MenuTipRouting.moduleID(forTipID: tip.id)) } label: {
                        Text(tipCTA(tip)).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(red:0.16,green:0.10,blue:0.30))
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(MenuPalette.yellow, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(11)
        .glassCard()
    }

    private func tipCTA(_ tip: TipsEngine.Tip) -> String {
        switch tip.id {
        case "trash_large": return L10n.tr("清空废纸篓", "Empty Trash", "Очистить Корзину")
        case "caches_large": return L10n.tr("释放空间", "Free Up Space", "Освободить место")
        default: return L10n.tr("打开 \(MCConstants.appName)", "Open \(MCConstants.appName)", "Открыть \(MCConstants.appName)")
        }
    }

    // MARK: Protection

    private func protectionCard(_ p: SharedAppState.ProtectionStatus) -> some View {
        let tint = p.threatsFound > 0 ? Color(red:0.98,green:0.42,blue:0.45) : (p.isStale ? MenuPalette.yellow : MenuPalette.teal)
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.18)).frame(width: 30, height: 30)
                Image(systemName: p.threatsFound > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(p.threatsFound > 0 ? L10n.tr("发现 \(p.threatsFound) 个威胁", "\(p.threatsFound) threat\(p.threatsFound == 1 ? "" : "s") found", "\(p.threatsFound) \(L10n.russianPlural(p.threatsFound, one: "угроза обнаружена", few: "угрозы обнаружены", many: "угроз обнаружено"))") : L10n.tr("已防护", "Protected", "Под защитой"))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text(L10n.tr(
                    "上次扫描：\(relativeTime(p.lastScanDate)) · \(p.localizedScanDepth)",
                    "Scanned \(relativeTime(p.lastScanDate)) · \(p.localizedScanDepth)",
                    "Проверено \(relativeTime(p.lastScanDate)) · \(p.localizedScanDepth)"
                ))
                    .font(.system(size: 10)).foregroundStyle(MenuPalette.textSecondary)
            }
            Spacer()
        }
        .padding(11).glassCard()
    }

    // MARK: Connected devices

    private func devicesCard(_ d: ConnectedDevices) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "externaldrive.connected.to.line.below", title: L10n.tr("已连接", "Connected", "Подключено"), tint: MenuPalette.teal)
            ForEach(d.externalVolumes) { v in
                HStack(spacing: 7) {
                    Image(systemName: "externaldrive.fill").font(.system(size: 10)).foregroundStyle(MenuPalette.teal.opacity(0.8))
                    Text(v.name).font(.system(size: 11)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(L10n.tr("\(FileSizeFormatter.format(v.freeBytes)) 可用", "\(FileSizeFormatter.format(v.freeBytes)) free", "Свободно: \(FileSizeFormatter.format(v.freeBytes))")).font(.system(size: 10, design: .monospaced)).foregroundStyle(MenuPalette.textSecondary)
                }
            }
            if d.externalDisplays > 0 {
                HStack(spacing: 7) {
                    Image(systemName: "display").font(.system(size: 10)).foregroundStyle(MenuPalette.teal.opacity(0.8))
                    Text(L10n.tr("\(d.externalDisplays) 台外接显示器", "\(d.externalDisplays) external display\(d.externalDisplays == 1 ? "" : "s")", "\(d.externalDisplays) \(L10n.russianPlural(d.externalDisplays, one: "внешний дисплей", few: "внешних дисплея", many: "внешних дисплеев"))")).font(.system(size: 11)).foregroundStyle(.white)
                    Spacer()
                }
            }
        }
        .padding(11).glassCard()
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 34, height: 32)
                    .background(MenuPalette.red, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }.buttonStyle(.plain).help(L10n.tr("退出监视器", "Quit Monitor", "Закрыть виджет"))

            Button { TipAction.open() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill").font(.system(size: 11, weight: .bold))
                    Text(L10n.tr("打开 \(MCConstants.appName)", "Open \(MCConstants.appName)", "Открыть \(MCConstants.appName)")).font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(MenuPalette.green, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    // MARK: Helpers

    private func sectionHeader(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            Spacer()
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600, m = (Int(seconds) % 3600) / 60
        if h > 24 { return L10n.tr("\(h/24)天 \(h%24)小时", "\(h/24)d \(h%24)h", "\(h/24) \(L10n.russianPlural(h/24, one: "день", few: "дня", many: "дней")) \(h%24) \(L10n.russianPlural(h%24, one: "час", few: "часа", many: "часов"))") }
        return L10n.tr("\(h)小时 \(m)分", "\(h)h \(m)m", "\(h) \(L10n.russianPlural(h, one: "час", few: "часа", many: "часов")) \(m) \(L10n.russianPlural(m, one: "минута", few: "минуты", many: "минут"))")
    }

    private func relativeTime(_ date: Date) -> String {
        let i = Date().timeIntervalSince(date)
        if i < 60 { return L10n.tr("刚刚", "just now", "только что") }
        if i < 3600 { return L10n.tr("\(Int(i/60)) 分钟前", "\(Int(i/60)) min ago", "\(Int(i/60)) \(L10n.russianPlural(Int(i/60), one: "минуту", few: "минуты", many: "минут")) назад") }
        if i < 86400 { return L10n.tr("\(Int(i/3600)) 小时前", "\(Int(i/3600)) hr ago", "\(Int(i/3600)) \(L10n.russianPlural(Int(i/3600), one: "час", few: "часа", many: "часов")) назад") }
        return L10n.tr("\(Int(i/86400)) 天前", "\(Int(i/86400)) day\(Int(i/86400) == 1 ? "" : "s") ago", "\(Int(i/86400)) \(L10n.russianPlural(Int(i/86400), one: "день", few: "дня", many: "дней")) назад")
    }
}

// MARK: - Ring gauge

struct RingGauge: View {
    let value: Double
    let color: Color
    let center: String

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(center).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
    }
}

// MARK: - Glass card modifier

private extension View {
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        self
            .background(MenuPalette.card.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(.ultraThinMaterial.opacity(0.30),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
    }
}
