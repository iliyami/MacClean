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
    /// In-flight duplicates scan. Held so Cancel can stop hashing mid-run (#3).
    @State private var scanTask: Task<Void, Never>?
    @State private var scanTimerTask: Task<Void, Never>?
    @State private var elapsedSeconds: Int = 0
    /// Remove (delete) vs Consolidate (replace copies with APFS clones) (#65).
    @State private var actionMode: DuplicatesActionMode = .remove
    @State private var consolidateConfirm = false
    @State private var consolidateTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isScanning {
                scanningView
            } else if scanComplete && results.isEmpty {
                ModuleContainerView(
                    title: L10n.tr("重复文件", "Duplicates", "Дубликаты"),
                    subtitle: "",
                    theme: .files,
                    emptyMessage: L10n.tr("未找到重复文件", "No duplicates found", "Дубликаты не найдены"),
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
                    title: L10n.tr("重复文件", "Duplicates", "Дубликаты"),
                    subtitle: "",
                    theme: .files,
                    results: results,
                    selectedItems: $selectedItems,
                    isScanning: false,
                    completion: completion,
                    cleaning: cleaning,
                    onScan: scan,
                    onClean: { actionMode == .consolidate ? (consolidateConfirm = true) : clean() },
                    onCancelClean: { cleanTask?.cancel() },
                    onReset: reset,
                    resultsContent: {
                        AnyView(
                            VStack(spacing: 12) {
                                Picker("", selection: $actionMode) {
                                    Text(L10n.tr("删除重复项", "Remove duplicates", "Удалить дубликаты"))
                                        .tag(DuplicatesActionMode.remove)
                                    Text(L10n.tr("合并", "Consolidate", "Объединить"))
                                        .tag(DuplicatesActionMode.consolidate)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .padding(.horizontal, 20)

                                DuplicateGroupsList(
                                    groups: displayGroups,
                                    selectedItems: $selectedItems,
                                    expanded: $expandedGroups
                                )
                            }
                        )
                    }
                )
            } else if completion != nil {
                ModuleContainerView(
                    title: L10n.tr("重复文件", "Duplicates", "Дубликаты"),
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
        // Idle / scanning paths don't use ModuleContainerView; relay ⌘R here.
        // When ModuleContainerView is shown it also listens to the same nonces —
        // outer must NOT accept ⌘K (canClean: false), or clean() runs twice and
        // the second pass can overwrite the completion summary with "0 freed".
        .respondsToModuleShortcuts(
            onScan: scan,
            canScan: !isScanning && cleaning == nil && completion == nil && results.isEmpty && !scanComplete,
            canClean: false
        )
        .confirmationDialog(
            L10n.tr("合并所选副本？", "Consolidate selected copies?", "Объединить выбранные копии?"),
            isPresented: $consolidateConfirm, titleVisibility: .visible
        ) {
            Button(L10n.tr("合并", "Consolidate", "Объединить")) { consolidate() }
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) {}
        } message: {
            let est = FileConsolidator.estimateReclaimable(
                groups: DuplicatesConsolidation.groups(from: displayGroups, selection: selectedItems))
            Text(L10n.tr(
                "保留所有副本，预计释放 \(FileSizeFormatter.format(est))",
                "Keeps every copy, frees about \(FileSizeFormatter.format(est))",
                "Сохраняет все копии, освободит примерно \(FileSizeFormatter.format(est))"))
        }
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 10) {
                Text(L10n.tr("重复文件", "Duplicates", "Дубликаты"))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)
                Text(L10n.tr("使用渐进式 SHA-256 哈希检测\n查找重复文件", "Find duplicate files using progressive\nSHA-256 hash detection", "Поиск дубликатов с помощью поэтапного\nхеширования SHA-256"))
                    .font(.system(size: 14))
                    .foregroundStyle(.primary.opacity(0.65))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 13))
                Text(L10n.tr("大型个人目录可能需要几分钟扫描", "This scan may take several minutes on large home folders", "Сканирование большой домашней папки может занять несколько минут"))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.primary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            ScanButton(title: L10n.tr("扫描", "Scan", "Сканировать"), subtitle: L10n.tr("重复文件", "Duplicates", "Дубликаты"), theme: .files, action: scan)

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

                Text(L10n.tr("已用时：\(formatElapsed(elapsedSeconds))", "Elapsed: \(formatElapsed(elapsedSeconds))", "Прошло: \(formatElapsed(elapsedSeconds))"))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.6))
            }

            Text(L10n.tr("重复文件检测会使用 SHA-256 哈希每个候选文件。\n大型个人目录可能需要 5–15 分钟。", "Duplicate detection hashes every candidate file with SHA-256.\nLarge home folders can take 5–15 minutes.", "При поиске дубликатов для каждого файла вычисляется хеш SHA-256.\nОбработка больших домашних папок может занять 5–15 минут."))
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(L10n.tr("取消", "Cancel", "Отмена")) { cancelScan() }
                .buttonStyle(.bordered)
                .tint(.primary)
                .controlSize(.large)

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
        scanPhase = L10n.tr("正在扫描个人目录...", "Scanning home folder...", "Сканирование домашней папки...")

        scanTask?.cancel()
        scanTimerTask?.cancel()

        // Elapsed timer
        scanTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                elapsedSeconds += 1
            }
        }

        scanTask = Task {
            scanPhase = L10n.tr("正在扫描个人目录...", "Scanning home folder...", "Сканирование домашней папки...")
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }

            scanPhase = L10n.tr("正在按大小分组文件...", "Grouping files by size...", "Группировка файлов по размеру...")
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }

            scanPhase = L10n.tr("正在并行哈希候选文件...", "Hashing candidate files in parallel...", "Параллельное хеширование файлов-кандидатов...")

            let module = DuplicatesModule()
            let groups = await module.scanDisplayGroups()
            if Task.isCancelled { return }

            scanPhase = L10n.tr("正在完成...", "Finalizing...", "Завершение...")
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }

            scanTimerTask?.cancel()
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
            scanTask = nil
            scanTimerTask = nil
        }
    }

    /// Stop an in-flight duplicates scan and return to the idle screen (#3).
    private func cancelScan() {
        scanTask?.cancel()
        scanTimerTask?.cancel()
        scanTask = nil
        scanTimerTask = nil
        isScanning = false
        scanComplete = false
        scanProgress = 0
        elapsedSeconds = 0
        scanPhase = ""
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

    /// Replace the selected copies with APFS clones of each group's kept master,
    /// keeping every path in place (#65). Reuses the shared done-screen via
    /// `completion`; the filesystem work runs off the main actor.
    private func consolidate() {
        let groups = DuplicatesConsolidation.groups(from: displayGroups, selection: selectedItems)
        let planned = groups.reduce(0) { $0 + $1.copies.count }
        cleaning = CleaningEngine.Progress(
            totalItems: planned,
            processedItems: 0, removedSoFar: 0, freedBytesSoFar: 0
        )
        consolidateTask?.cancel()
        consolidateTask = Task {
            let summary = await Task.detached { FileConsolidator.consolidate(groups: groups) }.value
            cleaning = nil
            completion = CleanSummary(
                selectedCount: summary.consolidatedCount + summary.skipped.count + summary.failed.count,
                removedCount: summary.consolidatedCount,
                freedBytes: summary.reclaimedBytes,
                errorMessages: summary.failed.map(\.message)
                    + summary.skipped.map { "\($0.url.lastPathComponent): \(skipLabel($0.reason))" }
            )
        }
    }

    private func skipLabel(_ reason: SkipReason) -> String {
        switch reason {
        case .contentChanged: L10n.tr("内容已更改", "content changed", "содержимое изменилось")
        case .notSameVolume: L10n.tr("跨卷", "different volume", "другой том")
        case .cloningUnsupported: L10n.tr("非 APFS 卷", "not an APFS volume", "не том APFS")
        case .notRegularFile: L10n.tr("非普通文件", "not a regular file", "не обычный файл")
        case .notWritable: L10n.tr("不可写", "not writable", "недоступно для записи")
        case .protectedPath: L10n.tr("受保护路径", "protected path", "защищённый путь")
        }
    }

    private func reset() {
        scanTask?.cancel()
        scanTimerTask?.cancel()
        scanTask = nil
        scanTimerTask = nil
        consolidateTask?.cancel()
        consolidateTask = nil
        actionMode = .remove
        results = []; displayGroups = []; expandedGroups = []; selectedItems = []
        completion = nil; cleaning = nil; cleanTask = nil
        scanComplete = false; elapsedSeconds = 0; isScanning = false
    }
}
