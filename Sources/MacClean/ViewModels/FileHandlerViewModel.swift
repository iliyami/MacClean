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
        // MainActor Task: `self` stays on the main actor (never sent into a
        // detached context, which tripped Swift 6 region isolation on CI). Only
        // the plist read is offloaded, returning a Sendable [HandlerEntry].
        Task {
            let loaded = await Task.detached { LaunchServicesService.shared.loadHandlers() }.value
            handlers = loaded
            isLoading = false
        }
    }

    // MARK: - Delete (with auto-backup)

    public func deleteHandler(_ handler: HandlerEntry) {
        Task {
            do {
                try await Task.detached { try LaunchServicesService.shared.deleteHandler(handler) }.value
                loadHandlers()
            } catch {
                errorMessage = L10n.tr("删除失败：\(error.localizedDescription)",
                                       "Delete failed: \(error.localizedDescription)")
                showError = true
            }
        }
    }

    // MARK: - Restore

    public func loadBackups() {
        backups = service.listBackups()
    }

    public func restoreBackup(from url: URL) {
        isRestoring = true
        Task {
            do {
                try await Task.detached { try LaunchServicesService.shared.restoreBackup(from: url) }.value
                isRestoring = false
                showRestoreSheet = false
                loadHandlers()
            } catch {
                isRestoring = false
                errorMessage = L10n.tr("还原失败：\(error.localizedDescription)",
                                       "Restore failed: \(error.localizedDescription)")
                showError = true
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
