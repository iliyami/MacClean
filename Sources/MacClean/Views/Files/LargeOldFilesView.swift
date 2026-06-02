import SwiftUI
import MacCleanKit

struct LargeOldFilesView: View {
    @Environment(AppState.self) private var appState
    @State private var results: [ScanResult] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanPhase = ""
    @State private var scanComplete = false
    @State private var completion: CleanSummary?
    @State private var cleaning: CleaningEngine.Progress?
    @State private var cleanTask: Task<Void, Never>?

    var body: some View {
        ModuleContainerView(
            title: "Large & Old Files",
            subtitle: "Find files larger than 50 MB that haven't been accessed recently",
            theme: .files,
            emptyMessage: "No large or old files found",
            results: results,
            selectedItems: $selectedItems,
            isScanning: isScanning,
            scanProgress: scanProgress,
            scanPhase: scanPhase,
            scanComplete: scanComplete,
            completion: completion,
            cleaning: cleaning,
            onScan: scan,
            onClean: clean,
            onCancelClean: { cleanTask?.cancel() },
            onReset: reset
        )
        .onAppear {
            if let e = appState.scanResultsStore.entry(for: .largeOldFiles) {
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
                for: .largeOldFiles
            )
        }
    }

    private func scan() {
        isScanning = true
        scanComplete = false
        scanProgress = 0
        Task {
            let scanStart = Date()

            scanPhase = "Scanning home directory..."
            scanProgress = 0.2
            try? await Task.sleep(for: .milliseconds(500))

            scanPhase = "Checking file sizes..."
            scanProgress = 0.45

            let module = LargeOldFilesModule()
            async let scanTask = module.scan()

            try? await Task.sleep(for: .milliseconds(400))
            scanPhase = "Checking access dates..."
            scanProgress = 0.7

            results = await scanTask

            scanPhase = "Grouping results..."
            scanProgress = 0.9

            let elapsed = Date().timeIntervalSince(scanStart)
            if elapsed < 2.0 {
                try? await Task.sleep(for: .milliseconds(Int((2.0 - elapsed) * 1000)))
            }
            scanProgress = 1.0

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
        results = []; selectedItems = []; completion = nil; cleaning = nil; cleanTask = nil; scanComplete = false
    }
}
