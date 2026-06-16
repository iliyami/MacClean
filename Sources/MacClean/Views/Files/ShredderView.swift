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
                    Text("Shredder")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Securely erase files beyond recovery")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }
            .padding(20)

            Spacer()

            if let result {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.white)
                    Text("\(result.erasedCount) files erased")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(FileSizeFormatter.format(result.totalSize))
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))

                    Button("Done") {
                        self.result = nil
                        filesToShred = []
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            } else if isProcessing {
                ProgressView("Shredding files...")
                    .foregroundStyle(.white)
                    .tint(.white)
            } else if filesToShred.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "scissors")
                        .font(.system(size: 50))
                        .foregroundStyle(.white.opacity(0.5))

                    Text("Drop files here to shred them")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.6))

                    Button("Select Files") {
                        selectFiles()
                    }
                    .buttonStyle(SuperEllipseButtonStyle(
                        gradient: ModuleTheme.files.gradient,
                        size: CGSize(width: 140, height: 44)
                    ))

                    // Erase mode picker
                    Picker("Mode", selection: $eraseMode) {
                        Text("Move to Trash").tag(SecureEraser.EraseMode.standard)
                        Text("Permanent Delete").tag(SecureEraser.EraseMode.permanent)
                        Text("Secure Erase").tag(SecureEraser.EraseMode.secure)
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
                    Text("\(filesToShred.count) files selected")
                        .font(.headline)
                        .foregroundStyle(.white)

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

                    Button("Shred") {
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
