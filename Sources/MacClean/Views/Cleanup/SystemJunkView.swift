import SwiftUI
import MacCleanKit

struct SystemJunkView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = SystemJunkViewModel()
    @State private var showLargeSelectionConfirm = false
    @State private var showActivityLog = false

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                idleView
            case .scanning(let progress):
                scanningView(progress: progress)
            case .results:
                resultsView
            case .empty:
                emptyView
            case .cleaning(let progress):
                cleaningView(progress: progress)
            case .done(let summary):
                doneView(summary: summary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let e = appState.scanResultsStore.entry(for: .systemJunk) {
                viewModel.restore(results: e.results, selection: e.selection, scanComplete: e.scanComplete)
            }
        }
        .onDisappear {
            appState.scanResultsStore.save(
                results: viewModel.results,
                selection: viewModel.selectedItems,
                scanComplete: viewModel.isScanComplete,
                for: .systemJunk
            )
        }
    }

    private var idleView: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Text("System Junk")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)

                Text("Find and remove system caches, logs,\nlanguage files, and other junk")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }

            ScanButton(
                title: "Scan",
                subtitle: "System Junk",
                theme: .cleanup
            ) {
                viewModel.startScan()
            }

            Spacer()
        }
    }

    private func scanningView(progress: Double) -> some View {
        VStack(spacing: 0) {
            Spacer()

            ScanProgressRing(
                progress: progress,
                phase: viewModel.scanPhase,
                detail: "\(viewModel.filesFound) files found",
                theme: .cleanup
            )

            Spacer()
        }
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            HStack {
                SizeDisplay(size: viewModel.totalSelectedSize, label: "selected to clean")
                    .foregroundStyle(.white)

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(viewModel.selectedCount) of \(viewModel.totalFileCount) files")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))

                    Button("Clean") {
                        if viewModel.selectedCount > MCConstants.cleanConfirmationThreshold {
                            showLargeSelectionConfirm = true
                        } else {
                            viewModel.startCleaning(engine: appState.cleaningEngine)
                        }
                    }
                    .buttonStyle(SuperEllipseButtonStyle(
                        gradient: ModuleTheme.cleanup.buttonGradient,
                        size: CGSize(width: 110, height: 40)
                    ))
                    // Prevent clicking Clean with nothing checked — that
                    // path used to drop the user into a misleading "0 bytes
                    // cleaned up" screen that looked like a failed clean.
                    .disabled(viewModel.selectedCount == 0)
                    .opacity(viewModel.selectedCount == 0 ? 0.5 : 1.0)
                    .help(viewModel.selectedCount == 0
                          ? "Check at least one item to clean"
                          : "Move \(viewModel.selectedCount) item(s) to Trash")
                    .alert(
                        "Clean \(viewModel.selectedCount.formatted()) items?",
                        isPresented: $showLargeSelectionConfirm
                    ) {
                        Button("Cancel", role: .cancel) { }
                        Button("Continue", role: .destructive) {
                            viewModel.startCleaning(engine: appState.cleaningEngine)
                        }
                    } message: {
                        Text("That's about \(ByteCountFormatter.string(fromByteCount: Int64(viewModel.totalSelectedSize), countStyle: .file)) of data and may take several minutes. You can cancel mid-cleanup.")
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            FileListView(
                results: viewModel.results,
                selectedItems: $viewModel.selectedItems
            )
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.9))
            Text("No junk found")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text("Your Mac is clean!")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
            Button("Done") { viewModel.reset() }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.large)
            Spacer()
        }
    }

    private func cleaningView(progress: CleaningEngine.Progress?) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // Determinate progress when the engine has emitted at least one
            // snapshot; indeterminate spinner before the first chunk lands.
            ScanProgressRing(
                progress: progress?.fraction ?? 0.0,
                phase: cleaningPhaseText(progress),
                theme: .cleanup
            )

            if let progress {
                Text("\(progress.processedItems.formatted()) of \(progress.totalItems.formatted()) items")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }

            // Cancel button — engine honors Task.isCancelled at chunk
            // boundaries, so a cancel halts the operation and produces a
            // partial CleanResult (which the .done state shows honestly).
            Button("Cancel") { viewModel.cancelCleaning() }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.large)

            Spacer()
        }
    }

    /// See ModuleContainerView.cleanErrorDetail for the design rationale —
    /// this is the same UI, lifted here because SystemJunkView has its
    /// own state machine and doesn't route through ModuleContainerView.
    @ViewBuilder
    private func cleanErrorDetail(for summary: CleanSummary) -> some View {
        if summary.errorCount == 1, let msg = summary.firstErrorMessage {
            Text(msg)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .textSelection(.enabled)
        } else if !summary.topErrorGroups.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(summary.topErrorGroups, id: \.message) { group in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(group.count.formatted())×")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(minWidth: 50, alignment: .trailing)
                        Text(group.message)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                let shownTotal = summary.topErrorGroups.reduce(0) { $0 + $1.count }
                if summary.errorCount > shownTotal {
                    Text("…and \((summary.errorCount - shownTotal).formatted()) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 2)
                }
                Text("Full log: ~/Library/Logs/MacClean/operations.log")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 4)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)
        }
    }

    private func cleaningPhaseText(_ progress: CleaningEngine.Progress?) -> String {
        guard let progress, progress.totalItems > 0 else {
            return "Starting cleanup..."
        }
        let pct = Int((progress.fraction * 100).rounded())
        return "Cleaning… \(pct)%"
    }

    private func doneView(summary: CleanSummary) -> some View {
        VStack(spacing: 20) {
            Spacer()

            // Three distinguishable end-states. The user-reported confusion
            // (the Reddit "0 bytes cleaned up" screenshot) was the second
            // case: scan surfaced items but they were all in autoSelect=false
            // categories (most commonly Universal Binaries) so nothing was
            // checked when Clean was clicked. Saying "0 bytes" looked broken;
            // saying "Nothing was selected" tells the user what to do next.
            if summary.selectedCount == 0 {
                Image(systemName: "checklist.unchecked")
                    .font(.system(size: 52))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Nothing was selected")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Re-run the scan, check the items you want to remove, then click Clean.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else if summary.removedCount == 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange.opacity(0.85))
                Text("\(summary.selectedCount) item\(summary.selectedCount == 1 ? "" : "s") couldn't be cleaned")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                cleanErrorDetail(for: summary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white)
                SizeDisplay(size: summary.freedBytes, label: "cleaned up")
                    .foregroundStyle(.white)
                if summary.removedCount < summary.selectedCount {
                    // Partial success — tell them what got skipped.
                    Text("\(summary.removedCount) of \(summary.selectedCount) items removed" +
                         (summary.errorCount > 0 ? " — \(summary.errorCount) error\(summary.errorCount == 1 ? "" : "s")" : ""))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            HStack(spacing: 10) {
                if summary.errorCount > 0 {
                    Button {
                        showActivityLog = true
                    } label: {
                        Label("View Log", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .controlSize(.large)
                    .help("Open the activity log to see every error and copy details for a bug report")
                }
                Button("Done") { viewModel.reset() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .controlSize(.large)
            }
            Spacer()
        }
        .sheet(isPresented: $showActivityLog) { LogViewerView() }
    }
}
