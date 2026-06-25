import SwiftUI
import AppKit
import MacCleanKit

struct FileHandlerView: View {
    @StateObject private var viewModel = FileHandlerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField(L10n.tr("搜索文件类型或应用...", "Search file type or app..."),
                          text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                Button(action: { viewModel.loadHandlers() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(L10n.tr("刷新", "Refresh"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                    .tint(.primary)
                Spacer()
            } else if viewModel.handlers.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(L10n.tr("没有自定义的文件打开方式", "No custom file associations"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if viewModel.filteredHandlers.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(L10n.tr("没有找到匹配的结果", "No matching results"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(viewModel.filteredHandlers) { handler in
                        HandlerRowView(
                            handler: handler,
                            appInfo: viewModel.getAppInfo(for: handler),
                            onDelete: { viewModel.deleteHandler(handler) }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert(L10n.tr("错误", "Error"), isPresented: $viewModel.showError) {
            Button("OK") { viewModel.showError = false }
        } message: {
            Text(viewModel.errorMessage ?? L10n.tr("发生未知错误", "An unknown error occurred"))
        }
        .onAppear { viewModel.loadHandlers() }
    }
}

// MARK: - Row View

private struct HandlerRowView: View {
    let handler: HandlerEntry
    let appInfo: (name: String, icon: NSImage)?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // App Icon
            if let info = appInfo {
                Image(nsImage: info.icon)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
            }

            // File Type
            VStack(alignment: .leading, spacing: 2) {
                Text(handler.fileTypeDescription)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineLimit(1)

                if let ct = handler.contentType {
                    Text("UTI: \(ct)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if handler.urlScheme != nil {
                    Text(L10n.tr("URL Scheme", "URL Scheme"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // App Name
            if let info = appInfo {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(info.name)
                        .font(.system(size: 13))
                    if let bid = handler.appBundleIdentifier {
                        Text(bid)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(L10n.tr("未知应用", "Unknown app"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(L10n.tr("删除此关联", "Remove this association"))
        }
        .padding(.vertical, 2)
    }
}
