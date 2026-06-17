import Foundation
import MacCleanKit

public protocol ScanModule: Sendable {
    var id: String { get }
    var name: String { get }
    var category: ModuleCategory { get }
    var includedInSmartScan: Bool { get }
    func scan() async -> [ScanResult]
}

public extension ScanModule {
    var includedInSmartScan: Bool { true }
}

public enum ModuleCategory: String, CaseIterable, Sendable {
    case cleanup = "清理"
    case protection = "防护"
    case performance = "性能"
    case applications = "应用"
    case files = "文件"
}

@Observable
public final class ScanCoordinator: @unchecked Sendable {
    public enum ScanState: Sendable {
        case idle
        case scanning(progress: Double, currentModule: String, filesScanned: Int, sizeFound: UInt64)
        case completed(results: [ModuleScanResult])
        case failed(Error)
    }

    public private(set) var state: ScanState = .idle
    public private(set) var filesScanned: Int = 0
    public private(set) var totalSizeFound: UInt64 = 0

    private var scanTask: Task<Void, Never>?
    private var modules: [ScanModule] = []

    public init() {}

    public func registerModule(_ module: ScanModule) {
        modules.append(module)
    }

    public func registerModules(_ newModules: [ScanModule]) {
        modules.append(contentsOf: newModules)
    }

    public func scanAll() {
        scanModules(modules.filter { $0.includedInSmartScan })
    }

    public func scanAllIncludingHeavy() {
        scanModules(modules)
    }

    public func scanCategory(_ category: ModuleCategory) {
        let filtered = modules.filter { $0.category == category }
        scanModules(filtered)
    }

    public func scanSingle(_ moduleID: String) {
        let filtered = modules.filter { $0.id == moduleID }
        scanModules(filtered)
    }

    public func cancel() {
        scanTask?.cancel()
        state = .idle
    }

    private func scanModules(_ modulesToScan: [ScanModule]) {
        scanTask?.cancel()

        filesScanned = 0
        totalSizeFound = 0

        scanTask = Task { @MainActor [weak self] in
            guard let self else { return }

            var results: [ModuleScanResult] = []
            let totalModules = modulesToScan.count

            for (index, module) in modulesToScan.enumerated() {
                if Task.isCancelled { break }

                let progress = Double(index) / Double(totalModules)
                self.state = .scanning(
                    progress: progress,
                    currentModule: module.name,
                    filesScanned: self.filesScanned,
                    sizeFound: self.totalSizeFound
                )

                let start = Date()
                let rawResults = await module.scan()
                // Drop items the current process couldn't trash even if it
                // tried — root-owned children, data-vaulted Apple caches,
                // stale paths. Users never see them, never click them,
                // never see "X errors" on the completion screen for things
                // nothing on this machine could clean anyway. See
                // CleanFilter for the syscall-level reasoning.
                let scanResults: [ScanResult] = rawResults.map { result in
                    ScanResult(
                        category: result.category,
                        items: result.items.filter { CleanFilter.isCleanableByCurrentProcess($0.url) },
                        autoSelect: result.autoSelect
                    )
                }
                let duration = Date().timeIntervalSince(start)

                let moduleResult = ModuleScanResult(
                    moduleID: module.id,
                    moduleName: module.name,
                    categories: scanResults,
                    scanDuration: duration
                )
                results.append(moduleResult)

                self.filesScanned += moduleResult.totalFileCount
                self.totalSizeFound += moduleResult.totalSize
            }

            if !Task.isCancelled {
                self.state = .completed(results: results)
            }
        }
    }
}
