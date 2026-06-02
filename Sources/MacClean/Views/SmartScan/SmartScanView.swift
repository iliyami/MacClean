import SwiftUI
import MacCleanKit

struct SmartScanView: View {
    @Environment(AppState.self) private var appState
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

    private static let moduleOrder: [(id: String, name: String, icon: String, group: String)] = [
        ("systemJunk", "System Junk", "trash.circle.fill", "Cleanup"),
        ("mailAttachments", "Mail Attachments", "paperclip.circle.fill", "Cleanup"),
        ("trashBins", "Trash Bins", "trash.fill", "Cleanup"),
        ("malware", "Malware Removal", "shield.lefthalf.filled", "Protection"),
        ("privacy", "Privacy", "hand.raised.fill", "Protection"),
        ("optimization", "Optimization", "gauge.with.dots.needle.67percent", "Speed"),
        ("maintenance", "Maintenance", "wrench.and.screwdriver", "Speed"),
        ("uninstaller", "Uninstaller", "xmark.app.fill", "Apps"),
        ("updater", "Updater", "arrow.triangle.2.circlepath", "Apps"),
        ("largeOldFiles", "Large & Old Files", "doc.richtext.fill", "Files"),
    ]

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
                Text("Smart Scan")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text("Scan your Mac for junk files, malware threats,\nand performance issues")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }

            ScanButton(
                title: "Scan",
                subtitle: "One-click cleanup",
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
                statBadge(label: "Progress", value: "\(Int(progress * 100))%")
                statBadge(label: "Files Found", value: filesFound.formatted())
                statBadge(label: "Size", value: FileSizeFormatter.format(sizeFound))
            }
            .padding(.horizontal, 30)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.12))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
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
                .padding(.bottom, 20)
            }
            .background(.ultraThinMaterial.opacity(0.5))
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
                        .tint(.white)
                } else if completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
            .frame(width: 20)

            // Module icon
            Image(systemName: module.icon)
                .font(.system(size: 14))
                .foregroundStyle(isActive ? .white : .white.opacity(completed ? 0.6 : 0.25))
                .frame(width: 20)

            // Module name
            Text(module.name)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .white.opacity(completed ? 0.7 : 0.3))

            Spacer()

            // Results for completed modules
            if let info = completedInfo, info.fileCount > 0 {
                Text("\(info.fileCount) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Text(FileSizeFormatter.format(info.size))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            } else if let info = completedInfo {
                Text("Clean")
                    .font(.system(size: 11))
                    .foregroundStyle(.green.opacity(0.7))
            }

            // Group tag
            Text(module.group)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? .white.opacity(0.1) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statBadge(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: value)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results

    private func resultsView(totalSize: UInt64) -> some View {
        VStack(spacing: 20) {
            SizeDisplay(size: totalSize, label: "of junk found")
                .foregroundStyle(.white)
                .padding(.top, 24)

            HStack(spacing: 24) {
                if case .results(let cleanup, _, _, _, _) = scanState {
                    resultPill(icon: "trash.circle.fill", label: "Cleanup", value: FileSizeFormatter.format(cleanup))
                }
                if case .results(_, let threats, _, _, _) = scanState {
                    resultPill(icon: "shield.lefthalf.filled", label: "Protection", value: "\(threats) threats")
                }
                if case .results(_, _, let perf, _, _) = scanState {
                    resultPill(icon: "gauge.with.dots.needle.67percent", label: "Speed", value: "\(perf) items")
                }
            }

            FileListView(results: cleanResults, selectedItems: $selectedItems)
                .frame(maxHeight: 280)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

            Button("Clean") { showCleanConfirm = true }
                .buttonStyle(SuperEllipseButtonStyle(
                    gradient: ModuleTheme.smartScan.buttonGradient,
                    size: CGSize(width: 140, height: 46)
                ))
                .disabled(selectedItems.isEmpty)
                .opacity(selectedItems.isEmpty ? 0.5 : 1)
                .alert("Clean \(selectedItems.count) item\(selectedItems.count == 1 ? "" : "s")?", isPresented: $showCleanConfirm) {
                    Button("Cancel", role: .cancel) { }
                    Button("Clean", role: .destructive) { runCleanup() }
                } message: {
                    Text("Selected items will be moved to the Trash so you can recover them if needed.")
                }
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Empty / Done / Cleaning

    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.9))
            Text("Your Mac is clean!")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("No junk, threats, or performance issues found")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
            Button("Done") { resetScan() }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.large)
            Spacer()
        }
    }

    private func cleaningView(progress: Double) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ScanProgressRing(progress: progress, phase: "Cleaning your Mac...", theme: .smartScan)
            // Cancel mid-clean — consistent with the per-module views: just
            // cancel the task and let it land on .done with whatever was
            // already freed (the CleaningEngine checks Task.isCancelled at
            // each chunk boundary). We do NOT reset to .idle here, because
            // the in-flight task would race that back to .done.
            Button("Cancel") { cleanTask?.cancel() }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.large)
            Spacer()
        }
    }

    private func doneView(freedSize: UInt64) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white)
            Text("Moved to the Trash")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            SizeDisplay(size: freedSize, label: "ready to reclaim")
                .foregroundStyle(.white)
            Text("Your selected items are in the Trash — recover anything you need. To erase them for good, open Trash Bins and empty it.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Done") { resetScan() }
                .buttonStyle(.bordered)
                .tint(.white)
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
        .foregroundStyle(.white)
        .frame(width: 110, height: 90)
        .background(.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func startScan() {
        completedModules = []
        currentModuleName = ""

        Task {
            scanState = .scanning(phase: "Analyzing system...", progress: 0, filesFound: 0, sizeFound: 0)
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
