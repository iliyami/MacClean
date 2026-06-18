import SwiftUI
import MacCleanKit

struct DuplicatesView: View {
    @Environment(AppState.self) private var appState
    @State private var results: [ScanResult] = []
    /// The grouped view model the UI renders. `results` is derived from this
    /// (its removable copies) and is what the cleaner acts on; `displayGroups`
    /// carries the kept-original info that `results` alone can't express.
    @State private var displayGroups: [DuplicateDisplayGroup] = []
    /// Which duplicate sets are expanded in the grouped results. Owned here so
    /// it survives the AnyView rebuild that happens on each checkbox toggle.
    @State private var expandedGroups: Set<UUID> = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanPhase = ""
    @State private var scanComplete = false
    @State private var completion: CleanSummary?
    @State private var cleaning: CleaningEngine.Progress?
    @State private var cleanTask: Task<Void, Never>?
    @State private var elapsedSeconds: Int = 0

    var body: some View {
        Group {
            if isScanning {
                scanningView
            } else if scanComplete && results.isEmpty {
                ModuleContainerView(
                    title: L10n.tr("重复文件", "Duplicates"),
                    subtitle: "",
                    theme: .files,
                    emptyMessage: L10n.tr("未找到重复文件", "No duplicates found"),
                    results: results,
                    selectedItems: $selectedItems,
                    isScanning: false,
                    scanComplete: true,
                    completion: nil,
                    cleaning: cleaning,
                    onScan: scan, onClean: clean,
                    onCancelClean: { cleanTask?.cancel() },
                    onReset: reset
                )
            } else if !results.isEmpty {
                ModuleContainerView(
                    title: L10n.tr("重复文件", "Duplicates"),
                    subtitle: "",
                    theme: .files,
                    results: results,
                    selectedItems: $selectedItems,
                    isScanning: false,
                    completion: completion,
                    cleaning: cleaning,
                    onScan: scan, onClean: clean,
                    onCancelClean: { cleanTask?.cancel() },
                    onReset: reset,
                    resultsContent: {
                        AnyView(
                            DuplicateGroupsList(
                                groups: displayGroups,
                                selectedItems: $selectedItems,
                                expanded: $expandedGroups
                            )
                        )
                    }
                )
            } else if completion != nil {
                ModuleContainerView(
                    title: L10n.tr("重复文件", "Duplicates"),
                    subtitle: "",
                    theme: .files,
                    results: [],
                    selectedItems: $selectedItems,
                    isScanning: false,
                    completion: completion,
                    cleaning: cleaning,
                    onScan: scan, onClean: clean,
                    onCancelClean: { cleanTask?.cancel() },
                    onReset: reset
                )
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 10) {
                Text(L10n.tr("重复文件", "Duplicates"))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)
                Text(L10n.tr("使用渐进式 SHA-256 哈希检测\n查找重复文件", "Find duplicate files using progressive\nSHA-256 hash detection"))
                    .font(.system(size: 14))
                    .foregroundStyle(.primary.opacity(0.65))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 13))
                Text(L10n.tr("大型个人目录可能需要几分钟扫描", "This scan may take several minutes on large home folders"))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.primary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            ScanButton(title: L10n.tr("扫描", "Scan"), subtitle: L10n.tr("重复文件", "Duplicates"), theme: .files, action: scan)

            Spacer()
        }
    }

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(.primary)
                .scaleEffect(1.4)

            VStack(spacing: 6) {
                Text(scanPhase)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.interpolate)
                    .animation(.easeInOut(duration: 0.2), value: scanPhase)

                Text(L10n.tr("已用时：\(formatElapsed(elapsedSeconds))", "Elapsed: \(formatElapsed(elapsedSeconds))"))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.6))
            }

            Text(L10n.tr("重复文件检测会使用 SHA-256 哈希每个候选文件。\n大型个人目录可能需要 5–15 分钟。", "Duplicate detection hashes every candidate file with SHA-256.\nLarge home folders can take 5–15 minutes."))
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func scan() {
        isScanning = true
        scanComplete = false
        scanProgress = 0
        elapsedSeconds = 0
        scanPhase = L10n.tr("正在扫描个人目录...", "Scanning home folder...")

        // Elapsed timer
        let timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
            }
        }

        Task {
            scanPhase = L10n.tr("正在扫描个人目录...", "Scanning home folder...")
            try? await Task.sleep(for: .milliseconds(400))

            scanPhase = L10n.tr("正在按大小分组文件...", "Grouping files by size...")
            try? await Task.sleep(for: .milliseconds(400))

            scanPhase = L10n.tr("正在并行哈希候选文件...", "Hashing candidate files in parallel...")

            let module = DuplicatesModule()
            let groups = await module.scanDisplayGroups()

            scanPhase = L10n.tr("正在完成...", "Finalizing...")
            try? await Task.sleep(for: .milliseconds(300))

            timerTask.cancel()
            displayGroups = groups
            expandedGroups = []
            // The cleaner only ever sees the removable copies — never an
            // original — so a kept copy can't be deleted even by selecting all.
            let removable = groups.flatMap(\.duplicates)
            results = removable.isEmpty
                ? []
                : [ScanResult(category: .duplicates, items: removable, autoSelect: false)]
            // Pre-check every removable copy; the user unchecks anything to spare.
            selectedItems = Set(removable.map(\.url))
            isScanning = false
            scanComplete = true
        }
    }

    private func clean() {
        let preCleanSelectedCount = selectedItems.count
        cleaning = CleaningEngine.Progress(
            totalItems: preCleanSelectedCount,
            processedItems: 0, removedSoFar: 0, freedBytesSoFar: 0
        )
        cleanTask = Task {
            let result = await CleanActions.executeUserClean(
                results: results,
                selectedItems: selectedItems,
                engine: appState.cleaningEngine,
                onProgress: { progress in
                    Task { @MainActor in cleaning = progress }
                }
            )
            cleaning = nil
            completion = CleanSummary(
                selectedCount: preCleanSelectedCount,
                removedCount: result.removedCount,
                freedBytes: result.freedBytes,
                errorMessages: result.errors.map(\.error)
            )
        }
    }

    private func reset() {
        results = []; displayGroups = []; expandedGroups = []; selectedItems = []
        completion = nil; cleaning = nil; cleanTask = nil
        scanComplete = false; elapsedSeconds = 0
    }
}
