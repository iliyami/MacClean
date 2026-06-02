import SwiftUI
import AppKit
import MacCleanKit

@main
struct MacCleanMenuApp: App {
    init() {
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

    @State private var statsCollector = SystemStatsCollector()
    @State private var networkMonitor = NetworkSpeedMonitor()
    @State private var devicesCollector = ConnectedDevicesCollector()
    @State private var tipsEngine = TipsEngine()
    @State private var healthMonitor = HealthMonitor()
    @State private var stats: SystemStatsCollector.SystemStats?
    @State private var networkSpeed: NetworkSpeedMonitor.NetworkSpeed?
    @State private var devices: ConnectedDevices?
    @State private var protection: SharedAppState.ProtectionStatus?
    @State private var tips: [TipsEngine.Tip] = []
    @State private var pollingTask: Task<Void, Never>?
    @State private var slowTickCount = 0

    /// Menu-bar label icon: the Mac Clean vacuum, in color, at 18px.
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
                stats: stats,
                networkSpeed: networkSpeed,
                devices: devices,
                protection: protection,
                tips: tips,
                onDismissTip: { tipId in
                    SharedAppState.dismissTip(id: tipId)
                    tips.removeAll { $0.id == tipId }
                }
            )
            .onAppear { startPolling() }
            .onDisappear { stopPolling() }
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: Self.labelIcon)
                    .renderingMode(.original)
                if let stats {
                    Text(FileSizeFormatter.format(stats.diskFree))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                let s = await statsCollector.collect()
                let n = await networkMonitor.measure()
                stats = s
                networkSpeed = n
                protection = SharedAppState.protectionStatus
                slowTickCount += 1
                if slowTickCount % 10 == 1 {
                    devices = await devicesCollector.collect()
                    tips = await tipsEngine.generateTips()
                }
                await healthMonitor.evaluate(stats: s)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
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
                Text("Mac Clean")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MenuPalette.textPrimary)
                Text("Live system stats")
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
            ringCard(icon: "memorychip", label: "Memory",
                     value: s.memoryPressure, center: "\(Int((s.memoryPressure*100).rounded()))%",
                     sub: FileSizeFormatter.format(s.memoryUsed))
            ringCard(icon: "internaldrive", label: "Disk",
                     value: diskUsed, center: "\(Int((diskUsed*100).rounded()))%",
                     sub: "\(FileSizeFormatter.format(s.diskFree)) free")
            if let level = s.batteryLevel {
                ringCard(icon: s.batteryIsCharging ? "battery.100.bolt" : "battery.75",
                         label: s.batteryIsCharging ? "Charging" : "Battery",
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
            statHeader(icon: "clock", label: "Uptime", tint: MenuPalette.teal)
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
            sectionHeader(icon: "sparkles", title: "Recommendations", tint: MenuPalette.yellow)
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
                        }.buttonStyle(.plain).help("Dismiss for 30 days")
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
        case "trash_large": return "Empty Trash"
        case "caches_large": return "Free Up Space"
        default: return "Open Mac Clean"
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
                Text(p.threatsFound > 0 ? "\(p.threatsFound) threat\(p.threatsFound == 1 ? "" : "s") found" : "Protected")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text("Scanned \(relativeTime(p.lastScanDate)) · \(p.scanDepth)")
                    .font(.system(size: 10)).foregroundStyle(MenuPalette.textSecondary)
            }
            Spacer()
        }
        .padding(11).glassCard()
    }

    // MARK: Connected devices

    private func devicesCard(_ d: ConnectedDevices) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "externaldrive.connected.to.line.below", title: "Connected", tint: MenuPalette.teal)
            ForEach(d.externalVolumes) { v in
                HStack(spacing: 7) {
                    Image(systemName: "externaldrive.fill").font(.system(size: 10)).foregroundStyle(MenuPalette.teal.opacity(0.8))
                    Text(v.name).font(.system(size: 11)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(FileSizeFormatter.format(v.freeBytes)) free").font(.system(size: 10, design: .monospaced)).foregroundStyle(MenuPalette.textSecondary)
                }
            }
            if d.externalDisplays > 0 {
                HStack(spacing: 7) {
                    Image(systemName: "display").font(.system(size: 10)).foregroundStyle(MenuPalette.teal.opacity(0.8))
                    Text("\(d.externalDisplays) external display\(d.externalDisplays == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(.white)
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
            }.buttonStyle(.plain).help("Quit Monitor")

            Button { TipAction.open() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill").font(.system(size: 11, weight: .bold))
                    Text("Open Mac Clean").font(.system(size: 12, weight: .bold))
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
        if h > 24 { return "\(h/24)d \(h%24)h" }
        return "\(h)h \(m)m"
    }

    private func relativeTime(_ date: Date) -> String {
        let i = Date().timeIntervalSince(date)
        if i < 60 { return "just now" }
        if i < 3600 { return "\(Int(i/60)) min ago" }
        if i < 86400 { return "\(Int(i/3600)) hr ago" }
        return "\(Int(i/86400)) day\(Int(i/86400) == 1 ? "" : "s") ago"
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
