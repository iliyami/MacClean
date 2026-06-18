import SwiftUI
import MacCleanKit

struct SmartScanView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var scanState: SmartScanState = .idle
    @State private var completedModules: [CompletedModule] = []
    @State private var currentModuleName: String = ""
    @State private var selectedItems: Set<URL> = []
    @State private var cleanResults: [ScanResult] = []
    @State private var showCleanConfirm = false
    @State private var cleanTask: Task<Void, Never>?

    struct CompletedModule: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let fileCount: Int
        let size: UInt64
    }

    enum SmartScanState {
        case idle
        case scanning(phase: String, progress: Double, filesFound: Int, sizeFound: UInt64)
        case results(cleanup: UInt64, protection: Int, performance: Int, totalSize: UInt64, moduleResults: [ModuleScanResult])
        case empty
        case cleaning(progress: Double)
        case done(freedSize: UInt64)
    }

    private static var moduleOrder: [(id: String, name: String, icon: String, group: String)] {
        [
            ("systemJunk", L10n.tr("系统垃圾", "System Junk"), "trash.circle.fill", L10n.tr("清理", "Cleanup")),
            ("mailAttachments", L10n.tr("邮件附件", "Mail Attachments"), "paperclip.circle.fill", L10n.tr("清理", "Cleanup")),
            ("trashBins", L10n.tr("废纸篓", "Trash Bins"), "trash.fill", L10n.tr("清理", "Cleanup")),
            ("malware", L10n.tr("恶意软件清理", "Malware Removal"), "shield.lefthalf.filled", L10n.tr("防护", "Protection")),
            ("privacy", L10n.tr("隐私清理", "Privacy"), "hand.raised.fill", L10n.tr("防护", "Protection")),
            ("optimization", L10n.tr("优化", "Optimization"), "gauge.with.dots.needle.67percent", L10n.tr("加速", "Speed")),
            ("maintenance", L10n.tr("维护", "Maintenance"), "wrench.and.screwdriver", L10n.tr("加速", "Speed")),
            ("uninstaller", L10n.tr("卸载器", "Uninstaller"), "xmark.app.fill", L10n.tr("应用", "Apps")),
            ("updater", L10n.tr("应用更新", "Updater"), "arrow.triangle.2.circlepath", L10n.tr("应用", "Apps")),
            ("largeOldFiles", L10n.tr("大文件与旧文件", "Large & Old Files"), "doc.richtext.fill", L10n.tr("文件", "Files")),
        ]
    }

    var body: some View {
        Group {
            switch scanState {
            case .idle:
                idleView
            case .scanning(let phase, let progress, let filesFound, let sizeFound):
                scanningView(phase: phase, progress: progress, filesFound: filesFound, sizeFound: sizeFound)
            case .results(_, _, _, let totalSize, _):
                resultsView(totalSize: totalSize)
            case .empty:
                emptyView
            case .cleaning(let progress):
                cleaningView(progress: progress)
            case .done(let freedSize):
                doneView(freedSize: freedSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 8) {
                Text(L10n.tr("智能扫描", "Smart Scan"))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)
                Text(L10n.tr("扫描 Mac 中的垃圾文件、恶意威胁\n和性能问题", "Scan your Mac for junk files, malware threats,\nand performance issues"))
                    .font(.system(size: 14))
                    .foregroundStyle(.primary.opacity(0.65))
                    .multilineTextAlignment(.center)
            }

            ScanButton(
                title: L10n.tr("扫描", "Scan"),
                subtitle: L10n.tr("一键清理", "One-click cleanup"),
                theme: .smartScan,
                action: startScan
            )

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Scanning (redesigned)

    private func scanningView(phase: String, progress: Double, filesFound: Int, sizeFound: UInt64) -> some View {
        VStack(spacing: 0) {
            // Top stats bar
            HStack(spacing: 24) {
                statBadge(label: L10n.tr("进度"), value: "\(Int(progress * 100))%")
                statBadge(label: L10n.tr("已发现文件", "Files Found"), value: filesFound.formatted())
                statBadge(label: L10n.tr("大小", "Size"), value: FileSizeFormatter.format(sizeFound))
            }
            .padding(.horizontal, 30)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary.opacity(0.12))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 30)
            .padding(.bottom, 16)

            // Module checklist
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(Self.moduleOrder.enumerated()), id: \.offset) { index, module in
                        moduleRow(module: module, currentPhase: phase)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .background {
                if removeBackgroundColors { Color.clear }
                else { Rectangle().fill(.ultraThinMaterial.opacity(0.5)) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func moduleRow(module: (id: String, name: String, icon: String, group: String), currentPhase: String) -> some View {
        let isActive = currentPhase == module.name
        let completed = completedModules.contains { $0.name == module.name }
        let completedInfo = completedModules.first { $0.name == module.name }

        return HStack(spacing: 10) {
            // Status icon
            ZStack {
                if isActive {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.primary)
                } else if completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.primary.opacity(0.2))
                }
            }
            .frame(width: 20)

            // Module icon
            Image(systemName: module.icon)
                .font(.system(size: 14))
                .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(completed ? 0.6 : 0.25))
                .frame(width: 20)

            // Module name
            Text(module.name)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(completed ? 0.7 : 0.3))

            Spacer()

            // Results for completed modules
            if let info = completedInfo, info.fileCount > 0 {
                Text(L10n.tr("\(info.fileCount) 项", "\(info.fileCount) items"))
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.5))
                Text(FileSizeFormatter.format(info.size))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.6))
            } else if completedInfo != nil {
                Text(L10n.tr("干净", "Clean"))
                    .font(.system(size: 11))
                    .foregroundStyle(.green.opacity(0.7))
            }

            // Group tag
            Text(module.group)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.primary.opacity(0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.primary.opacity(0.08))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.primary.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statBadge(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: value)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(0.5))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results

    private func resultsView(totalSize: UInt64) -> some View {
        VStack(spacing: 20) {
            SizeDisplay(size: totalSize, label: L10n.tr("发现的垃圾", "of junk found"))
                .foregroundStyle(.primary)
                .padding(.top, 24)

            HStack(spacing: 24) {
                if case .results(let cleanup, _, _, _, _) = scanState {
                    resultPill(icon: "trash.circle.fill", label: L10n.tr("清理", "Cleanup"), value: FileSizeFormatter.format(cleanup))
                }
                if case .results(_, let threats, _, _, _) = scanState {
                    resultPill(icon: "shield.lefthalf.filled", label: L10n.tr("防护", "Protection"), value: L10n.tr("\(threats) 个威胁", "\(threats) threats"))
                }
                if case .results(_, _, let perf, _, _) = scanState {
                    resultPill(icon: "gauge.with.dots.needle.67percent", label: L10n.tr("加速", "Speed"), value: L10n.tr("\(perf) 项", "\(perf) items"))
                }
            }

            // Fill the remaining height so the list is tall enough to review
            // comfortably (issue #85), instead of a short fixed box.
            FileListView(results: cleanResults, selectedItems: $selectedItems)
                .frame(maxHeight: .infinity)
                .background {
                    if removeBackgroundColors { Color.clear }
                    else { Rectangle().fill(.ultraThinMaterial) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

            // Footer: running selection on the left, the clean action on the right.
            HStack {
                Text(L10n.tr("已选择 \(selectedItems.count)/\(totalCleanItems) 项", "\(selectedItems.count)/\(totalCleanItems) selected"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
                Spacer()
                Button { showCleanConfirm = true } label: {
                    Text(L10n.tr("清理 · \(FileSizeFormatter.format(selectedCleanSize))", "Clean · \(FileSizeFormatter.format(selectedCleanSize))"))
                }
                .buttonStyle(SuperEllipseButtonStyle(
                    gradient: ModuleTheme.smartScan.buttonGradient,
                    size: CGSize(width: 200, height: 46)
                ))
                .disabled(selectedItems.isEmpty)
                .opacity(selectedItems.isEmpty ? 0.5 : 1)
                .alert(L10n.tr("清理 \(selectedItems.count) 项？", "Clean \(selectedItems.count) item\(selectedItems.count == 1 ? "" : "s")?"), isPresented: $showCleanConfirm) {
                    Button(L10n.tr("取消", "Cancel"), role: .cancel) { }
                    Button(L10n.tr("清理", "Clean"), role: .destructive) { runCleanup() }
                } message: {
                    Text(L10n.tr("选中的项目会移到废纸篓，如有需要仍可恢复。", "Selected items will be moved to the Trash so you can recover them if needed."))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
    }

    /// Total number of cleanable items found (across all categories).
    private var totalCleanItems: Int {
        cleanResults.reduce(0) { $0 + $1.items.count }
    }

    /// On-disk size of the currently selected items, for the footer button.
    private var selectedCleanSize: UInt64 {
        cleanResults.reduce(into: UInt64(0)) { total, result in
            for item in result.items where selectedItems.contains(item.url) {
                total += item.size
            }
        }
    }

    // MARK: - Empty / Done / Cleaning

    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.primary.opacity(0.9))
            Text(L10n.tr("你的 Mac 很干净！", "Your Mac is clean!"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
            Text(L10n.tr("未发现垃圾、威胁或性能问题", "No junk, threats, or performance issues found"))
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.6))
            Button(L10n.tr("完成", "Done")) { resetScan() }
                .buttonStyle(.bordered)
                .tint(.primary)
                .controlSize(.large)
            Spacer()
        }
    }

    private func cleaningView(progress: Double) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ScanProgressRing(progress: progress, phase: L10n.tr("正在清理你的 Mac...", "Cleaning your Mac..."), theme: .smartScan)
            // Cancel mid-clean — consistent with the per-module views: just
            // cancel the task and let it land on .done with whatever was
            // already freed (the CleaningEngine checks Task.isCancelled at
            // each chunk boundary). We do NOT reset to .idle here, because
            // the in-flight task would race that back to .done.
            Button(L10n.tr("取消", "Cancel")) { cleanTask?.cancel() }
                .buttonStyle(.bordered)
                .tint(.primary)
                .controlSize(.large)
            Spacer()
        }
    }

    private func doneView(freedSize: UInt64) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.primary)
            Text(L10n.tr("已移到废纸篓", "Moved to the Trash"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
            SizeDisplay(size: freedSize, label: L10n.tr("可回收", "ready to reclaim"))
                .foregroundStyle(.primary)
            Text(L10n.tr("你选择的项目已在废纸篓中——需要时可以恢复。若要彻底删除，请打开“废纸篓”模块并清空。", "Your selected items are in the Trash — recover anything you need. To erase them for good, open Trash Bins and empty it."))
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.65))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button(L10n.tr("完成", "Done")) { resetScan() }
                .buttonStyle(.bordered)
                .tint(.primary)
                .controlSize(.large)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private func resetScan() {
        cleanTask?.cancel()
        cleanTask = nil
        selectedItems = []
        cleanResults = []
        completedModules = []
        currentModuleName = ""
        scanState = .idle
    }

    // MARK: - Components

    private func resultPill(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .opacity(0.7)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .frame(width: 110, height: 90)
        .background(.primary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func startScan() {
        completedModules = []
        currentModuleName = ""

        Task {
            scanState = .scanning(phase: L10n.tr("正在分析系统...", "Analyzing system..."), progress: 0, filesFound: 0, sizeFound: 0)
            appState.scanCoordinator.scanAll()

            var previousModule = ""
            var previousFiles = 0
            var previousSize: UInt64 = 0

            while true {
                try? await Task.sleep(for: .milliseconds(80))

                switch appState.scanCoordinator.state {
                case .scanning(let progress, let module, let files, let size):
                    // Detect module transitions
                    if module != previousModule && !previousModule.isEmpty {
                        let filesInModule = files - previousFiles
                        let sizeInModule = size - previousSize

                        let icon = Self.moduleOrder.first { $0.name == previousModule }?.icon ?? "circle"
                        completedModules.append(CompletedModule(
                            name: previousModule,
                            icon: icon,
                            fileCount: filesInModule,
                            size: sizeInModule
                        ))

                        previousFiles = files
                        previousSize = size
                    }
                    previousModule = module
                    currentModuleName = module
                    scanState = .scanning(phase: module, progress: progress, filesFound: files, sizeFound: size)

                case .completed(let results):
                    // Mark last module as completed
                    if !previousModule.isEmpty {
                        let totalFiles = results.reduce(0) { $0 + $1.totalFileCount }
                        let totalSize = results.reduce(0 as UInt64) { $0 + $1.totalSize }
                        let filesInModule = totalFiles - previousFiles
                        let sizeInModule = totalSize - previousSize
                        let icon = Self.moduleOrder.first { $0.name == previousModule }?.icon ?? "circle"
                        completedModules.append(CompletedModule(
                            name: previousModule,
                            icon: icon,
                            fileCount: filesInModule,
                            size: sizeInModule
                        ))
                    }

                    let totalSize = results.reduce(0 as UInt64) { $0 + $1.totalSize }
                    if totalSize == 0 && results.allSatisfy({ $0.totalFileCount == 0 }) {
                        scanState = .empty
                    } else {
                        cleanResults = SmartScanCleanup.allResults(from: results)
                        selectedItems = SmartScanCleanup.defaultSelection(from: results)
                        scanState = .results(
                            cleanup: totalSize,
                            protection: 0,
                            performance: 0,
                            totalSize: totalSize,
                            moduleResults: results
                        )
                    }
                    return

                case .failed:
                    scanState = .idle
                    return

                case .idle:
                    continue
                }
            }
        }
    }

    private func runCleanup() {
        // Snapshot selection up-front so the background task can't observe a
        // later mutation (the state machine moves to .cleaning immediately,
        // but the explicit copy keeps that guarantee local and obvious).
        let results = cleanResults
        let selection = selectedItems
        scanState = .cleaning(progress: 0)
        cleanTask = Task {
            let result = await CleanActions.executeUserClean(
                results: results,
                selectedItems: selection,
                engine: appState.cleaningEngine,
                onProgress: { p in Task { @MainActor in
                    // Ignore late progress that lands after we've left the
                    // cleaning phase (cancel/done), so it can't resurrect
                    // a stale .cleaning state.
                    if case .cleaning = scanState {
                        scanState = .cleaning(progress: p.fraction)
                    }
                } }
            )
            // MVP: surface only freedBytes; result.errors/skippedCount are
            // reserved for a future detail screen.
            scanState = .done(freedSize: result.freedBytes)
        }
    }
}
