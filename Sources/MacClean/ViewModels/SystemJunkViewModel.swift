import SwiftUI
import MacCleanKit

@MainActor @Observable
final class SystemJunkViewModel {
    enum State {
        case idle
        case scanning(progress: Double)
        case results
        case empty
        case cleaning(progress: CleaningEngine.Progress?)
        case done(summary: CleanSummary)
    }

    var state: State = .idle
    var results: [ScanResult] = [] {
        didSet { rebuildSizeIndex() }
    }
    var selectedItems: Set<URL> = [] {
        didSet { recomputeSelectedSize() }
    }
    var filesFound: Int = 0
    var scanPhase: String = L10n.tr("正在扫描...", "Scanning...", "Сканирование...")
    /// Held so the View's Cancel button can stop an in-flight cleanup.
    private var cleanTask: Task<Void, Never>?

    private let module = SystemJunkModule()

    /// Cached total bytes of the current selection. The results view reads this
    /// on every body pass, and SwiftUI re-evaluates that body during the layout
    /// pass on every sidebar switch, so it MUST be O(1) to read. It used to be
    /// an O(n) computed property that flat-mapped every item into a fresh array
    /// each call; once a scan listed 100k+ items that froze the main thread for
    /// seconds on each switch (confirmed by a sample: ~46% of main-thread time
    /// was in this getter under NSHostingView.layout). Recomputed only when
    /// `results` or `selectedItems` actually change.
    private(set) var totalSelectedSize: UInt64 = 0

    /// url -> size index, rebuilt when `results` change, so recomputing the
    /// selected total is O(selected) rather than O(all items).
    private var sizeByURL: [URL: UInt64] = [:]

    private func rebuildSizeIndex() {
        var map = [URL: UInt64](minimumCapacity: results.reduce(0) { $0 + $1.items.count })
        for result in results {
            for item in result.items { map[item.url] = item.size }
        }
        sizeByURL = map
        recomputeSelectedSize()
    }

    private func recomputeSelectedSize() {
        var total: UInt64 = 0
        for url in selectedItems { total += sizeByURL[url] ?? 0 }
        totalSelectedSize = total
    }

    var selectedCount: Int {
        selectedItems.count
    }

    var totalFileCount: Int {
        results.reduce(0) { $0 + $1.fileCount }
    }

    func startScan() {
        state = .scanning(progress: 0)
        filesFound = 0
        results = []
        selectedItems = []
        scanPhase = L10n.tr("正在扫描缓存...", "Scanning caches...", "Сканирование кэшей...")

        Task {
            let scanStart = Date()

            state = .scanning(progress: 0.1)
            scanPhase = L10n.tr("正在扫描用户缓存...", "Scanning user caches...", "Сканирование пользовательских кэшей...")
            try? await Task.sleep(for: .milliseconds(300))

            scanPhase = L10n.tr("正在扫描系统日志...", "Scanning system logs...", "Сканирование системных журналов...")
            state = .scanning(progress: 0.25)

            async let scanTask = module.scan()

            try? await Task.sleep(for: .milliseconds(400))
            scanPhase = L10n.tr("正在检查语言文件...", "Checking language files...", "Проверка файлов локализации...")
            state = .scanning(progress: 0.4)

            try? await Task.sleep(for: .milliseconds(300))
            scanPhase = L10n.tr("正在检查偏好设置...", "Inspecting preferences...", "Проверка настроек...")
            state = .scanning(progress: 0.55)

            try? await Task.sleep(for: .milliseconds(300))
            scanPhase = L10n.tr("正在检查登录项...", "Checking login items...", "Проверка объектов входа...")
            state = .scanning(progress: 0.7)

            let scanResults = await scanTask

            scanPhase = L10n.tr("正在分析结果...", "Analyzing results...", "Анализ результатов...")
            state = .scanning(progress: 0.9)

            results = scanResults
            filesFound = scanResults.reduce(0) { $0 + $1.fileCount }

            // Build the auto-selection locally and assign once, so the
            // selectedItems observer (and its size recompute) fires a single
            // time instead of once per inserted URL.
            var selection = selectedItems
            for result in scanResults where result.autoSelect {
                for item in result.items { selection.insert(item.url) }
            }
            selectedItems = selection

            let elapsed = Date().timeIntervalSince(scanStart)
            if elapsed < 2.0 {
                try? await Task.sleep(for: .milliseconds(Int((2.0 - elapsed) * 1000)))
            }

            state = .scanning(progress: 1.0)
            try? await Task.sleep(for: .milliseconds(300))
            state = scanResults.isEmpty ? .empty : .results
        }
    }

    func startCleaning(engine: CleaningEngine) {
        state = .cleaning(progress: nil)
        let preCleanSelectedCount = selectedItems.count

        cleanTask = Task { [weak self] in
            // Onprogress is invoked from the engine actor; hop to main
            // before touching @Observable view state.
            let result = await CleanActions.executeUserClean(
                results: self?.results ?? [],
                selectedItems: self?.selectedItems ?? [],
                engine: engine,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        if case .cleaning = self.state {
                            self.state = .cleaning(progress: progress)
                        }
                    }
                }
            )
            guard let self else { return }
            self.state = .done(summary: CleanSummary(
                selectedCount: preCleanSelectedCount,
                removedCount: result.removedCount,
                freedBytes: result.freedBytes,
                errorMessages: result.errors.map(\.error)
            ))
        }
    }

    /// User clicked Cancel during a long cleanup. The engine honors
    /// Task.isCancelled at chunk boundaries, so the operation will halt
    /// and produce a partial CleanResult; the .done state shows the
    /// partial summary so the user sees what was cleaned before the
    /// cancellation.
    func cancelCleaning() {
        cleanTask?.cancel()
    }

    func reset() {
        state = .idle
        results = []
        selectedItems = []
        filesFound = 0
        cleanTask = nil
    }

    // MARK: - Navigation persistence

    /// Rehydrate from a previously-cached scan (preserved across navigation).
    func restore(results: [ScanResult], selection: Set<URL>, scanComplete: Bool) {
        self.results = results
        self.selectedItems = selection
        self.filesFound = results.reduce(0) { $0 + $1.fileCount }
        state = scanComplete ? (results.isEmpty ? .empty : .results) : .idle
    }

    /// True once a scan has produced a results/empty screen worth preserving.
    var isScanComplete: Bool {
        switch state {
        case .results, .empty: return true
        default: return false
        }
    }
}
