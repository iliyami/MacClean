import SwiftUI
import AppKit
import MacCleanKit

/// In-app viewer for `~/Library/Logs/MacClean/operations.log`. Surfaced
/// from the completion screen so users can read the [ERROR] lines that
/// explain why some items couldn't be cleaned — and copy them onto a
/// GitHub issue without leaving the app.
struct LogViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    @State private var errorsOnly: Bool = true
    @State private var copied: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            logBody
            Divider().opacity(0.2)
            footer
        }
        .frame(minWidth: 640, idealWidth: 800, minHeight: 400, idealHeight: 540)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { loadLog() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr("活动日志", "Activity Log"))
                    .font(.system(size: 18, weight: .semibold))
                Text(L10n.tr("~/Library/Logs/MacClean/operations.log — 30 天后自动清理", "~/Library/Logs/MacClean/operations.log — pruned after 30 days"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Toggle(L10n.tr("仅显示错误", "Errors only"), isOn: $errorsOnly)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(14)
    }

    private var logBody: some View {
        Group {
            if displayedText.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: errorsOnly ? "checkmark.seal" : "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(errorsOnly
                         ? L10n.tr("没有记录到错误。", "No errors logged.")
                         : L10n.tr("日志为空。尚未执行过清理。", "Log is empty. Nothing has been cleaned yet."))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(displayedText)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                revealInFinder()
            } label: {
                Label(L10n.tr("在 Finder 中显示", "Reveal in Finder"), systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Button {
                copyAll()
            } label: {
                Label(copied ? L10n.tr("已复制", "Copied") : L10n.tr("复制全部", "Copy All"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(displayedText.isEmpty)
            .help(L10n.tr("将当前内容复制到剪贴板，可粘贴到 GitHub issue 中", "Copy what you see to the clipboard — paste into a GitHub issue"))

            Spacer()

            Button(L10n.tr("完成", "Done")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    // MARK: - Data

    private var displayedText: String {
        if !errorsOnly { return content }
        return content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains("[ERROR]") }
            .joined(separator: "\n")
    }

    private func loadLog() {
        content = CleanLogManager.readLogFile()
    }

    private func copyAll() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(displayedText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func revealInFinder() {
        let url = MCConstants.operationLogFile
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
