import SwiftUI
import MacCleanKit

struct ModuleContainerView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    let title: String
    let subtitle: String
    let theme: ModuleTheme
    let emptyMessage: String
    let results: [ScanResult]
    @Binding var selectedItems: Set<URL>
    let isScanning: Bool
    let scanProgress: Double
    let scanPhase: String
    let scanComplete: Bool
    /// `nil` until clean has run. When set, the doneView renders one of
    /// three honest end-states (nothing selected / everything errored /
    /// happy path) instead of an ambiguous "0 bytes cleaned up".
    let completion: CleanSummary?
    /// Non-nil while a clean is in flight. The container renders a
    /// progress ring + cancel button instead of the results list during
    /// this window. nil means "no clean in flight" — either before any
    /// clean or after one finishes (then `completion` takes over).
    let cleaning: CleaningEngine.Progress?
    /// True when the scan came back empty because a target couldn't be read
    /// (Full Disk Access not granted) rather than because there was nothing
    /// to clean. Drives the "Grant Full Disk Access" empty-state instead of
    /// the misleading "nothing to clean up" one.
    let permissionDenied: Bool
    let onScan: () -> Void
    let onClean: () -> Void
    let onCancelClean: (() -> Void)?
    let onReset: () -> Void
    /// Opens System Settings → Full Disk Access. Required when
    /// `permissionDenied` can be true; the empty-state button calls it.
    let onGrantAccess: (() -> Void)?
    /// When true, the Clean button ALWAYS shows an irreversible
    /// "Empty the Trash?" confirmation, regardless of selection size.
    /// Used only by the Trash Bins module, whose Clean permanently
    /// deletes (it empties ~/.Trash) rather than moving items to the Trash.
    let confirmEmptyTrash: Bool
    /// Optional replacement for the default flat `FileListView` in the results
    /// screen. When provided, the container keeps all of its chrome (selection
    /// header, Clean button + confirmations, cleaning/progress/done states) but
    /// renders this view for the item list instead. The Duplicates module uses
    /// it to show a grouped, keep-the-original layout while reusing everything
    /// else. The closure should read/write the same `selectedItems` binding.
    let resultsContent: (() -> AnyView)?

    init(
        title: String,
        subtitle: String,
        theme: ModuleTheme,
        emptyMessage: String = "No items found",
        results: [ScanResult],
        selectedItems: Binding<Set<URL>>,
        isScanning: Bool,
        scanProgress: Double = 0.5,
        scanPhase: String = "Scanning...",
        scanComplete: Bool = false,
        completion: CleanSummary? = nil,
        cleaning: CleaningEngine.Progress? = nil,
        permissionDenied: Bool = false,
        onScan: @escaping () -> Void,
        onClean: @escaping () -> Void,
        onCancelClean: (() -> Void)? = nil,
        onReset: @escaping () -> Void,
        onGrantAccess: (() -> Void)? = nil,
        confirmEmptyTrash: Bool = false,
        resultsContent: (() -> AnyView)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.emptyMessage = emptyMessage
        self.results = results
        self._selectedItems = selectedItems
        self.isScanning = isScanning
        self.scanProgress = scanProgress
        self.scanPhase = scanPhase
        self.scanComplete = scanComplete
        self.completion = completion
        self.cleaning = cleaning
        self.permissionDenied = permissionDenied
        self.onScan = onScan
        self.onClean = onClean
        self.onCancelClean = onCancelClean
        self.onReset = onReset
        self.onGrantAccess = onGrantAccess
        self.confirmEmptyTrash = confirmEmptyTrash
        self.resultsContent = resultsContent
    }

    @State private var showLargeSelectionConfirm = false
    @State private var showEmptyTrashConfirm = false
    @State private var showActivityLog = false

    private var totalSelected: UInt64 {
        // Dedupe by URL: a file can appear in two categories (large + old)
        // and Clean trashes it once, so summing per-item would over-report
        // versus what actually gets freed.
        results.selectedSize(selectedItems)
    }

    private var selectedCount: Int {
        selectedItems.count
    }

    private var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSelected), countStyle: .file)
    }

    var body: some View {
        Group {
            if let completion {
                doneView(summary: completion)
            } else if let cleaning {
                cleaningView(progress: cleaning)
            } else if !results.isEmpty {
                resultsView
            } else if isScanning {
                scanningView
            } else if scanComplete {
                if permissionDenied {
                    permissionDeniedView
                } else {
                    emptyResultsView
                }
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Renders the error summary on the post-clean screen. Single error
    /// gets the full message; multi-error shows the top-3 groups
    /// ("X items: <message>") sorted by count, so the user immediately
    /// sees what kind of failure dominated rather than a flat count
    /// pointing them at Console.app.
    @ViewBuilder
    private func cleanErrorDetail(for summary: CleanSummary) -> some View {
        if summary.errorCount == 1, let msg = summary.firstErrorMessage {
            Text(msg)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .textSelection(.enabled)
        } else if !summary.topErrorGroups.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(summary.topErrorGroups, id: \.message) { group in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(group.count.formatted())×")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.6))
                            .frame(minWidth: 50, alignment: .trailing)
                        Text(group.message)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.8))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                if summary.errorCount > summary.topErrorGroups.reduce(0, { $0 + $1.count }) {
                    let shownTotal = summary.topErrorGroups.reduce(0) { $0 + $1.count }
                    Text("…and \((summary.errorCount - shownTotal).formatted()) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.5))
                        .padding(.top, 2)
                }
                Text("Full log: ~/Library/Logs/MacClean/operations.log")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.45))
                    .padding(.top, 4)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)
        }
    }

    private func cleaningView(progress: CleaningEngine.Progress) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ScanProgressRing(
                progress: progress.fraction,
                phase: progress.totalItems > 0
                    ? "Cleaning… \(Int((progress.fraction * 100).rounded()))%"
                    : "Starting cleanup...",
                theme: theme
            )
            if progress.totalItems > 0 {
                Text("\(progress.processedItems.formatted()) of \(progress.totalItems.formatted()) items")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.65))
            }
            if let onCancelClean {
                Button("Cancel") { onCancelClean() }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .controlSize(.large)
            }
            Spacer()
        }
    }

    private var idleView: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            ScanButton(title: "Scan", subtitle: title, theme: theme, action: onScan)
            Spacer()
        }
    }

    private var scanningView: some View {
        VStack(spacing: 0) {
            Spacer()
            ScanProgressRing(progress: scanProgress, phase: scanPhase, theme: theme)
            Spacer()
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.primary.opacity(0.9))
            Text(emptyMessage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Scan complete — nothing to clean up")
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.55))
            Button("Done") { onReset() }
                .buttonStyle(.bordered)
                .tint(.primary)
                .controlSize(.large)
            Spacer()
        }
    }

    /// Shown when the scan came back empty only because macOS blocked the
    /// read (Full Disk Access not granted). Without this the user saw
    /// "nothing to clean up" over a Trash that was actually full.
    private var permissionDeniedView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 52))
                .foregroundStyle(.primary.opacity(0.9))
            Text("Full Disk Access needed")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
            Text("macOS is blocking access to this location. Grant \(MCConstants.appName) Full Disk Access, then scan again.")
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 10) {
                if let onGrantAccess {
                    Button("Open Settings") { onGrantAccess() }
                        .buttonStyle(.borderedProminent)
                        .tint(.primary)
                        .controlSize(.large)
                }
                Button("Rescan") { onScan() }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .controlSize(.large)
                Button("Done") { onReset() }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .controlSize(.large)
            }
            Spacer()
        }
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            HStack {
                SizeDisplay(size: totalSelected, label: "selected")
                    .foregroundStyle(.primary)
                Spacer()
                Button("Clean") {
                    if confirmEmptyTrash {
                        // Trash Bins: permanent + irreversible — always confirm.
                        showEmptyTrashConfirm = true
                    } else if selectedCount > MCConstants.cleanConfirmationThreshold {
                        showLargeSelectionConfirm = true
                    } else {
                        onClean()
                    }
                }
                    .buttonStyle(SuperEllipseButtonStyle(
                        gradient: theme.buttonGradient,
                        size: CGSize(width: 110, height: 40)
                    ))
                    // Prevent clicking Clean with nothing checked — the
                    // resulting "0 bytes cleaned up" screen used to be
                    // indistinguishable from a real cleanup failure.
                    .disabled(selectedCount == 0)
                    .opacity(selectedCount == 0 ? 0.5 : 1.0)
                    .help(selectedCount == 0
                          ? "Check at least one item to clean"
                          : confirmEmptyTrash
                            ? "Permanently delete \(selectedCount) item(s) from the Trash"
                            : "Move \(selectedCount) item(s) to Trash")
                    .alert(
                        "Clean \(selectedCount.formatted()) items?",
                        isPresented: $showLargeSelectionConfirm
                    ) {
                        Button("Cancel", role: .cancel) { }
                        Button("Continue", role: .destructive) { onClean() }
                    } message: {
                        Text("That's about \(formattedSelectedSize) of data and may take several minutes. You can cancel mid-cleanup.")
                    }
                    // Trash Bins empties ~/.Trash permanently — there is no
                    // recovery, so this confirmation fires on every Empty
                    // regardless of how many items are selected.
                    .alert(
                        "Empty the Trash?",
                        isPresented: $showEmptyTrashConfirm
                    ) {
                        Button("Cancel", role: .cancel) { }
                        Button("Empty Trash", role: .destructive) { onClean() }
                    } message: {
                        Text("This permanently deletes \(selectedCount.formatted()) item\(selectedCount == 1 ? "" : "s") (\(formattedSelectedSize)) and cannot be undone.")
                    }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Group {
                if let resultsContent {
                    resultsContent()
                } else {
                    FileListView(results: results, selectedItems: $selectedItems)
                }
            }
            .background {
                if removeBackgroundColors { Color.clear }
                else { Rectangle().fill(.ultraThinMaterial) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func doneView(summary: CleanSummary) -> some View {
        VStack(spacing: 20) {
            Spacer()

            // Three honest end-states. Previously this view rendered
            // "0 bytes cleaned up" for all of: nothing-selected,
            // everything-errored, AND no-junk-found cases — making the
            // app look broken when it was working correctly.
            if summary.selectedCount == 0 {
                Image(systemName: "checklist.unchecked")
                    .font(.system(size: 52))
                    .foregroundStyle(.primary.opacity(0.85))
                Text("Nothing was selected")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Re-run the scan, check the items you want to remove, then click Clean.")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else if summary.removedCount == 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange.opacity(0.85))
                Text("\(summary.selectedCount) item\(summary.selectedCount == 1 ? "" : "s") couldn't be cleaned")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                // Show the actual first error message instead of "Check
                // Console for details" — the user shouldn't need to open
                // Console.app to find out it was a limit / permission /
                // SafetyGuard issue. For multi-error cases, fall back to
                // the count summary.
                cleanErrorDetail(for: summary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.primary)
                SizeDisplay(size: summary.freedBytes, label: "cleaned up")
                    .foregroundStyle(.primary)
                if summary.removedCount < summary.selectedCount {
                    Text("\(summary.removedCount) of \(summary.selectedCount) items removed" +
                         (summary.errorCount > 0 ? " — \(summary.errorCount) error\(summary.errorCount == 1 ? "" : "s")" : ""))
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.65))
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
                    .tint(.primary)
                    .controlSize(.large)
                    .help("Open the activity log to see every error and copy details for a bug report")
                }
                Button("Done") { onReset() }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .controlSize(.large)
            }
            Spacer()
        }
        .sheet(isPresented: $showActivityLog) { LogViewerView() }
    }
}
