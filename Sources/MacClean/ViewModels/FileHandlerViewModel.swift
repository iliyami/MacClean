import Foundation
import AppKit
import SwiftUI
import MacCleanKit

/// View model for browsing and managing user-customised file-type and URL-scheme
/// associations.  Every delete is preceded by a backup so all changes are
/// reversible via the restore-history panel.
@MainActor
public final class FileHandlerViewModel: ObservableObject {
    @Published public var handlers: [HandlerEntry] = []
    @Published public var isLoading = false
    @Published public var searchText = ""
    @Published public var errorMessage: String?
    @Published public var showError = false
    @Published public var backups: [URL] = []
    @Published public var showRestoreSheet = false
    @Published public var isRestoring = false

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

    // MARK: - Delete (with auto-backup)

    public func deleteHandler(_ handler: HandlerEntry) {
        Task.detached { [weak self] in
            do {
                try LaunchServicesService.shared.deleteHandler(handler)
                await MainActor.run {
                    self?.loadHandlers()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = L10n.tr("删除失败：\(error.localizedDescription)",
                                                  "Delete failed: \(error.localizedDescription)")
                    self?.showError = true
                }
            }
        }
    }

    // MARK: - Restore

    public func loadBackups() {
        backups = service.listBackups()
    }

    public func restoreBackup(from url: URL) {
        isRestoring = true
        Task.detached { [weak self] in
            do {
                try LaunchServicesService.shared.restoreBackup(from: url)
                await MainActor.run {
                    self?.isRestoring = false
                    self?.showRestoreSheet = false
                    self?.loadHandlers()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isRestoring = false
                    self?.errorMessage = L10n.tr("还原失败：\(error.localizedDescription)",
                                                  "Restore failed: \(error.localizedDescription)")
                    self?.showError = true
                }
            }
        }
    }

    // MARK: - App Info

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
