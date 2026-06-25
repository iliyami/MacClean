import Foundation
import AppKit
import SwiftUI
import MacCleanKit

@MainActor
public final class FileHandlerViewModel: ObservableObject {
    @Published public var handlers: [HandlerEntry] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var showError = false
    @Published public var searchText = ""

    private let service = LaunchServicesService.shared

    public var filteredHandlers: [HandlerEntry] {
        if searchText.isEmpty { return handlers }
        let q = searchText.lowercased()
        return handlers.filter { h in
            if h.fileTypeDescription.lowercased().contains(q) { return true }
            if let ct = h.contentType, ct.lowercased().contains(q) { return true }
            if let app = getAppInfo(for: h), app.name.lowercased().contains(q) { return true }
            if let bid = h.appBundleIdentifier, bid.lowercased().contains(q) { return true }
            return false
        }
    }

    public func loadHandlers() {
        isLoading = true
        Task.detached { [weak self] in
            let handlers = LaunchServicesService.shared.loadHandlers()
            await MainActor.run {
                self?.handlers = handlers
                self?.isLoading = false
            }
        }
    }

    public func deleteHandler(_ handler: HandlerEntry) {
        guard let idx = handlers.firstIndex(of: handler) else { return }
        handlers.remove(at: idx)
        saveHandlers()
    }

    private func saveHandlers() {
        let currentHandlers = handlers
        Task.detached {
            do {
                try LaunchServicesService.shared.saveHandlers(currentHandlers)
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = L10n.tr("保存失败: \(error.localizedDescription)", "Save failed: \(error.localizedDescription)")
                    self?.showError = true
                }
            }
        }
    }

    public func getAppInfo(for handler: HandlerEntry) -> (name: String, icon: NSImage)? {
        if let bid = handler.appBundleIdentifier {
            return service.getAppInfo(for: bid)
        }
        if handler.urlScheme != nil {
            return service.getURLSchemeAppInfo(for: handler.urlScheme)
        }
        return nil
    }
}
