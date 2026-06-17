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
    var results: [ScanResult] = []
    var selectedItems: Set<URL> = []
    var filesFound: Int = 0
    var scanPhase: String = L10n.tr("正在扫描...", "Scanning...")
    /// Held so the View's Cancel button can stop an in-flight cleanup.
    private var cleanTask: Task<Void, Never>?

    private let module = SystemJunkModule()

    var totalSelectedSize: UInt64 {
        let allItems = results.flatMap(\.items)
        return allItems
            .filter { selectedItems.contains($0.url) }
            .reduce(0) { $0 + $1.size }
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
        scanPhase = L10n.tr("正在扫描缓存...", "Scanning caches...")

        Task {
            let scanStart = Date()

            state = .scanning(progress: 0.1)
            scanPhase = L10n.tr("正在扫描用户缓存...", "Scanning user caches...")
            try? await Task.sleep(for: .milliseconds(300))

            scanPhase = L10n.tr("正在扫描系统日志...", "Scanning system logs...")
            state = .scanning(progress: 0.25)

            async let scanTask = module.scan()

            try? await Task.sleep(for: .milliseconds(400))
            scanPhase = L10n.tr("正在检查语言文件...", "Checking language files...")
            state = .scanning(progress: 0.4)

            try? await Task.sleep(for: .milliseconds(300))
            scanPhase = L10n.tr("正在检查偏好设置...", "Inspecting preferences...")
            state = .scanning(progress: 0.55)

            try? await Task.sleep(for: .milliseconds(300))
            scanPhase = L10n.tr("正在检查登录项...", "Checking login items...")
            state = .scanning(progress: 0.7)

            let scanResults = await scanTask

            scanPhase = L10n.tr("正在分析结果...", "Analyzing results...")
            state = .scanning(progress: 0.9)

            results = scanResults
            filesFound = scanResults.reduce(0) { $0 + $1.fileCount }

            for result in scanResults where result.autoSelect {
                for item in result.items {
                    selectedItems.insert(item.url)
                }
            }

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
