import SwiftUI
import MacCleanKit

struct DuplicatesView: View {
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
    @State private var elapsedSeconds: Int = 0

    var body: some View {
        Group {
            if isScanning {
                scanningView
            } else if scanComplete && results.isEmpty {
                ModuleContainerView(
                    title: "Duplicates",
                    subtitle: "",
                    theme: .files,
                    emptyMessage: "No duplicates found",
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
                    title: "Duplicates",
                    subtitle: "",
                    theme: .files,
                    results: results,
                    selectedItems: $selectedItems,
                    isScanning: false,
                    completion: completion,
                    cleaning: cleaning,
                    onScan: scan, onClean: clean,
                    onCancelClean: { cleanTask?.cancel() },
                    onReset: reset
                )
            } else if completion != nil {
                ModuleContainerView(
                    title: "Duplicates",
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
        .onAppear {
            if let e = appState.scanResultsStore.entry(for: .duplicates) {
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
                for: .duplicates
            )
        }
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 10) {
                Text("Duplicates")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text("Find duplicate files using progressive\nSHA-256 hash detection")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 13))
                Text("This scan may take several minutes on large home folders")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            ScanButton(title: "Scan", subtitle: "Duplicates", theme: .files, action: scan)

            Spacer()
        }
    }

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .scaleEffect(1.4)

            VStack(spacing: 6) {
                Text(scanPhase)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.interpolate)
                    .animation(.easeInOut(duration: 0.2), value: scanPhase)

                Text("Elapsed: \(formatElapsed(elapsedSeconds))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Text("Duplicate detection hashes every candidate file with SHA-256.\nLarge home folders can take 5–15 minutes.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
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
        scanPhase = "Scanning home folder..."

        // Elapsed timer
        let timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
            }
        }

        Task {
            scanPhase = "Scanning home folder..."
            try? await Task.sleep(for: .milliseconds(400))

            scanPhase = "Grouping files by size..."
            try? await Task.sleep(for: .milliseconds(400))

            scanPhase = "Hashing candidate files in parallel..."

            let module = DuplicatesModule()
            let scanResults = await module.scan()

            scanPhase = "Finalizing..."
            try? await Task.sleep(for: .milliseconds(300))

            timerTask.cancel()
            results = scanResults
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
        results = []; selectedItems = []
        completion = nil; cleaning = nil; cleanTask = nil
        scanComplete = false; elapsedSeconds = 0
    }
}
