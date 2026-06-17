import SwiftUI
import MacCleanKit

struct MailAttachmentsView: View {
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

    private let module = MailAttachmentsModule()

    var body: some View {
        ModuleContainerView(
            title: L10n.tr("邮件附件", "Mail Attachments"),
            subtitle: L10n.tr("查找来自邮件、Outlook 和 Spark 的缓存邮件附件", "Find cached email attachments from Mail, Outlook, and Spark"),
            theme: .cleanup,
            emptyMessage: L10n.tr("未找到附件", "No attachments found"),
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
            if let e = appState.scanResultsStore.entry(for: .mailAttachments) {
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
                for: .mailAttachments
            )
        }
    }

    private func scan() {
        isScanning = true
        scanComplete = false
        scanProgress = 0
        Task {
            let scanStart = Date()

            scanPhase = L10n.tr("正在扫描 Apple Mail...", "Scanning Apple Mail...")
            scanProgress = 0.2
            try? await Task.sleep(for: .milliseconds(400))

            scanPhase = L10n.tr("正在扫描 Outlook...", "Scanning Outlook...")
            scanProgress = 0.45

            async let scanTask = module.scan()
            try? await Task.sleep(for: .milliseconds(400))

            scanPhase = L10n.tr("正在扫描 Spark...", "Scanning Spark...")
            scanProgress = 0.7

            results = await scanTask

            scanPhase = L10n.tr("正在分析附件...", "Analyzing attachments...")
            scanProgress = 0.9

            let elapsed = Date().timeIntervalSince(scanStart)
            if elapsed < 2.0 {
                try? await Task.sleep(for: .milliseconds(Int((2.0 - elapsed) * 1000)))
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
        results = []; selectedItems = []; completion = nil; cleaning = nil; cleanTask = nil; scanComplete = false
    }
}
