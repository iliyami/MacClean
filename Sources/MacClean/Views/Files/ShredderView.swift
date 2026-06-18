import SwiftUI
import MacCleanKit

struct ShredderView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var filesToShred: [URL] = []
    @State private var eraseMode: SecureEraser.EraseMode = .standard
    @State private var isProcessing = false
    @State private var result: SecureEraser.EraseResult?

    private let eraser = SecureEraser()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("文件粉碎", "Shredder"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(L10n.tr("安全擦除文件，使其无法恢复", "Securely erase files beyond recovery"))
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                Spacer()
            }
            .padding(20)

            Spacer()

            if let result {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.primary)
                    Text(L10n.tr("已擦除 \(result.erasedCount) 个文件", "\(result.erasedCount) files erased"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(FileSizeFormatter.format(result.totalSize))
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.7))

                    Button(L10n.tr("完成", "Done")) {
                        self.result = nil
                        filesToShred = []
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
            } else if isProcessing {
                ProgressView(L10n.tr("正在粉碎文件...", "Shredding files..."))
                    .foregroundStyle(.primary)
                    .tint(.primary)
            } else if filesToShred.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "scissors")
                        .font(.system(size: 50))
                        .foregroundStyle(.primary.opacity(0.5))

                    Text(L10n.tr("将文件拖放到此处进行粉碎", "Drop files here to shred them"))
                        .font(.system(size: 16))
                        .foregroundStyle(.primary.opacity(0.6))

                    Button(L10n.tr("选择文件", "Select Files")) {
                        selectFiles()
                    }
                    .buttonStyle(SuperEllipseButtonStyle(
                        gradient: ModuleTheme.files.gradient,
                        size: CGSize(width: 140, height: 44)
                    ))

                    // Erase mode picker
                    Picker(L10n.tr("模式", "Mode"), selection: $eraseMode) {
                        Text(L10n.tr("移到废纸篓", "Move to Trash")).tag(SecureEraser.EraseMode.standard)
                        Text(L10n.tr("永久删除", "Permanent Delete")).tag(SecureEraser.EraseMode.permanent)
                        Text(L10n.tr("安全擦除", "Secure Erase")).tag(SecureEraser.EraseMode.secure)
                    }
                    .pickerStyle(.segmented)
                    // Hidden visually, kept for VoiceOver. Rendered inline,
                    // the label gets width-starved by the fixed 360pt frame
                    // (segments consume it all) and wraps one letter per
                    // line into a vertical "M o d e".
                    .labelsHidden()
                    .frame(width: 360)
                    .padding(.top, 8)
                }
            } else {
                VStack(spacing: 16) {
                    Text(L10n.tr("已选择 \(filesToShred.count) 个文件", "\(filesToShred.count) files selected"))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    List(filesToShred, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc")
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                filesToShred.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.inset)
                    .frame(maxHeight: 200)
                    .background {
                        if removeBackgroundColors { Color.clear }
                        else { Rectangle().fill(.ultraThinMaterial) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 40)

                    Button(L10n.tr("粉碎", "Shred")) {
                        shred()
                    }
                    .buttonStyle(SuperEllipseButtonStyle(
                        gradient: LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing),
                        size: CGSize(width: 140, height: 44)
                    ))
                }
            }

            Spacer()
        }
    }

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            filesToShred = panel.urls
        }
    }

    private func shred() {
        isProcessing = true
        Task {
            result = await eraser.erase(urls: filesToShred, mode: eraseMode)
            isProcessing = false
        }
    }
}
