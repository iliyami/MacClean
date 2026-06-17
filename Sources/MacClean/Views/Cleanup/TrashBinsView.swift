import SwiftUI
import MacCleanKit

struct TrashBinsView: View {
    @Environment(AppState.self) private var appState
    @State private var results: [ScanResult] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanComplete = false
    @State private var permissionDenied = false
    @State private var completion: CleanSummary?
    @State private var cleaning: CleaningEngine.Progress?
    @State private var cleanTask: Task<Void, Never>?

    private let module = TrashBinsModule()

    var body: some View {
        ModuleContainerView(
            title: L10n.tr("废纸篓", "Trash Bins"),
            subtitle: L10n.tr("清空所有废纸篓位置，包括外接驱动器", "Empty all trash locations including external drives"),
            theme: .cleanup,
            emptyMessage: L10n.tr("废纸篓为空", "Trash is empty"),
            results: results,
            selectedItems: $selectedItems,
            isScanning: isScanning,
            scanProgress: scanProgress,
            scanPhase: scanPhase,
            scanComplete: scanComplete,
            completion: completion,
            cleaning: cleaning,
            permissionDenied: permissionDenied,
            onScan: scan,
            onClean: clean,
            onCancelClean: { cleanTask?.cancel() },
            onReset: reset,
            onGrantAccess: { PermissionManager.shared.openFullDiskAccessSettings() },
            confirmEmptyTrash: true
        )
        .onAppear {
            if let e = appState.scanResultsStore.entry(for: .trashBins) {
                results = e.results
                selectedItems = e.selection
                scanComplete = e.scanComplete
            }
        }
        .onDisappear {
            appState.scanResultsStore.save(
                results: results,
                selection: selectedItems,
                scanComplete: scanComplete,
                for: .trashBins
            )
        }
    }

    @State private var scanProgress: Double = 0
    @State private var scanPhase = ""

    private func scan() {
        isScanning = true
        scanComplete = false
        permissionDenied = false
        scanProgress = 0
        Task {
            let scanStart = Date()

            scanPhase = L10n.tr("正在扫描用户废纸篓...", "Scanning user Trash...")
            scanProgress = 0.3
            try? await Task.sleep(for: .milliseconds(400))

            scanPhase = L10n.tr("正在检查外接驱动器...", "Checking external drives...")
            scanProgress = 0.6

            async let scanTask = module.scanReportingPermissions()
            let outcome = await scanTask
            results = outcome.results
            permissionDenied = outcome.permissionDenied

            scanPhase = L10n.tr("正在计算大小...", "Calculating sizes...")
            scanProgress = 0.9

            let elapsed = Date().timeIntervalSince(scanStart)
            if elapsed < 1.5 {
                try? await Task.sleep(for: .milliseconds(Int((1.5 - elapsed) * 1000)))
            }
            scanProgress = 1.0

            for r in results where r.autoSelect {
                selectedItems.formUnion(r.items.map(\.url))
            }
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
        results = []; selectedItems = []; completion = nil; cleaning = nil; cleanTask = nil; scanComplete = false; permissionDenied = false
    }
}
