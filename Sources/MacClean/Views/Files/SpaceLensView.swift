import SwiftUI
import MacCleanKit

struct SpaceLensView: View {
    @State private var rootNode: FileNode?
    @State private var treemapRects: [TreemapRect] = []
    @State private var isScanning = false
    @State private var scanTask: Task<Void, Never>?
    @State private var nav = SpaceLensNavigation(root: MCConstants.home)
    @State private var selectedVolume: URL = URL(filePath: "/")

    private let scanner = FileTreeScanner()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("空间透视", "Space Lens"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(L10n.tr("可视化磁盘空间使用情况", "Visualize disk space usage"))
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.6))
                }
                Spacer()
                if !isScanning {
                    Button(L10n.tr("扫描", "Scan")) { startScan() }
                        .buttonStyle(SuperEllipseButtonStyle(
                            gradient: ModuleTheme.files.buttonGradient,
                            size: CGSize(width: 90, height: 34)
                        ))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if nav.breadcrumbs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        Button { nav.up(); startScan() } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.plain).foregroundStyle(.primary.opacity(0.8))
                            .disabled(!nav.canGoUp)
                            .help(L10n.tr("上一级", "Up one level"))
                        Button { nav.home(); startScan() } label: { Image(systemName: "house") }
                            .buttonStyle(.plain).foregroundStyle(.primary.opacity(0.8))
                            .disabled(!nav.canGoUp)
                            .help(L10n.tr("返回起点", "Back to start"))

                        ForEach(nav.breadcrumbs, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                nav.navigate(to: url)
                                startScan()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary.opacity(0.7))
                            .font(.system(size: 12))

                            if url != nav.breadcrumbs.last {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.primary.opacity(0.4))
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }
            }

            if isScanning {
                Spacer()
                ScanProgressRing(progress: 0.5, phase: L10n.tr("正在扫描磁盘...", "Scanning disk..."), theme: .files)
                Button(L10n.tr("取消", "Cancel")) {
                    scanTask?.cancel()
                    isScanning = false
                }
                .buttonStyle(.bordered)
                .tint(.primary)
                .controlSize(.large)
                Spacer()
            } else if !treemapRects.isEmpty {
                GeometryReader { geo in
                    ZStack {
                        ForEach(treemapRects) { item in
                            treemapCell(item, containerSize: geo.size)
                        }
                    }
                    .padding(20)
                }
            } else {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 44))
                        .foregroundStyle(.primary.opacity(0.4))
                    Text(L10n.tr("点击“扫描”以可视化磁盘使用情况", "Click Scan to visualize disk usage"))
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.55))
                }
                Spacer()
            }
        }
    }

    private func treemapCell(_ item: TreemapRect, containerSize: CGSize) -> some View {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint]
        let colorIndex = abs(item.node.name.hashValue) % colors.count

        return RoundedRectangle(cornerRadius: 4)
            .fill(colors[colorIndex].opacity(0.7))
            .frame(width: max(item.rect.width - 2, 0), height: max(item.rect.height - 2, 0))
            .overlay {
                if item.rect.width > 60 && item.rect.height > 30 {
                    VStack(spacing: 2) {
                        Text(item.node.name)
                            .font(.system(size: max(9, min(13, item.rect.width / 10))))
                            .lineLimit(1)
                        Text(item.node.formattedSize)
                            .font(.system(size: max(8, min(10, item.rect.width / 12))))
                            .opacity(0.7)
                    }
                    .foregroundStyle(.primary)
                    .padding(4)
                }
            }
            .position(x: item.rect.midX, y: item.rect.midY)
            .onTapGesture {
                if item.node.isDirectory {
                    nav.drillInto(item.node.url)
                    startScan()
                }
            }
    }

    private func startScan() {
        // Cancel any in-flight scan first. Breadcrumb taps can fire while a
        // scan is running; without this the old task would keep running and
        // race the new one to overwrite rootNode/treemapRects/isScanning.
        scanTask?.cancel()
        isScanning = true
        scanTask = Task {
            let node = await scanner.scanWithSizeAggregation(root: nav.current)
            guard !Task.isCancelled else { return }
            rootNode = node

            let treemapNodes = node.children
                .sorted { $0.totalSize > $1.totalSize }
                .prefix(50)
                .map { child in
                    TreemapNode(
                        name: child.name,
                        size: child.totalSize,
                        url: child.url,
                        isDirectory: child.isDirectory,
                        children: []
                    )
                }

            let bounds = CGRect(x: 0, y: 0, width: 700, height: 400)
            treemapRects = SquarifiedTreemap.layout(nodes: Array(treemapNodes), in: bounds)
            isScanning = false
        }
    }
}
