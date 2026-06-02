import Foundation
import AppKit
import MacCleanKit

public struct UpdaterModule: ScanModule {
    public let id = "updater"
    public let name = "Updater"
    public let category = ModuleCategory.applications

    public init() {}

    public func scan() async -> [ScanResult] {
        []
    }
}

// MARK: - App Update Checker

public actor AppUpdateChecker {
    public struct AppUpdate: Identifiable, Sendable {
        public let id: UUID = UUID()
        public let app: AppInfo
        public let currentVersion: String
        public let availableVersion: String?
        public let downloadURL: URL?
        public let updateSize: UInt64?
        public let hasUpdate: Bool
    }

    public init() {}

    public func checkForUpdates(apps: [AppInfo]) async -> [AppUpdate] {
        await withTaskGroup(of: AppUpdate?.self) { group in
            for app in apps where !app.isAppleApp {
                group.addTask {
                    await self.checkApp(app)
                }
            }

            var updates: [AppUpdate] = []
            for await update in group {
                if let update, update.hasUpdate {
                    updates.append(update)
                }
            }
            return updates.sorted { $0.app.name < $1.app.name }
        }
    }

    private func checkApp(_ app: AppInfo) async -> AppUpdate? {
        // Check for Sparkle-based update feeds
        let infoPlistURL = app.path.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        // Look for SUFeedURL (Sparkle update feed)
        guard let feedURLString = plist["SUFeedURL"] as? String,
              let feedURL = URL(string: feedURLString)
        else { return nil }

        // Fetch and parse the appcast XML
        guard let (data, _) = try? await URLSession.shared.data(from: feedURL) else { return nil }

        let parser = AppcastParser()
        let (latestVersion, downloadURL) = parser.parseLatestItem(from: data)

        let currentVersion = app.version ?? "0"
        let hasUpdate = latestVersion != nil && latestVersion != currentVersion

        return AppUpdate(
            app: app,
            currentVersion: currentVersion,
            availableVersion: latestVersion,
            downloadURL: downloadURL,
            updateSize: nil,
            hasUpdate: hasUpdate
        )
    }
}

// MARK: - Updater Actions

/// What the "Update" button does, chosen by how the app was installed.
public enum UpdaterRoute: Equatable {
    case appStore
    case download(URL)
    case launchApp(URL)
}

public enum UpdaterActions {
    public static func route(isMacAppStore: Bool, downloadURL: URL?, appPath: URL) -> UpdaterRoute {
        if isMacAppStore { return .appStore }
        if let downloadURL { return .download(downloadURL) }
        return .launchApp(appPath)
    }

    /// A Mac App Store app ships a receipt at Contents/_MASReceipt/receipt.
    public static func isMacAppStoreApp(at appPath: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: appPath.appending(path: "Contents/_MASReceipt/receipt").path(percentEncoded: false))
    }

    @MainActor
    public static func perform(_ update: AppUpdateChecker.AppUpdate) {
        switch route(isMacAppStore: isMacAppStoreApp(at: update.app.path),
                     downloadURL: update.downloadURL, appPath: update.app.path) {
        case .appStore:
            if let url = URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(url) }
        case .download(let url):
            Task { await downloadAndReveal(url) }
        case .launchApp(let appURL):
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        }
    }

    @MainActor
    static func downloadAndReveal(_ url: URL) async {
        do {
            let (tmp, response) = try await URLSession.shared.download(from: url)
            let name = response.suggestedFilename ?? url.lastPathComponent
            let dest = MCConstants.downloads.appending(path: name)
            // If the file is already there (a double-tap won the race, or the
            // user downloaded it earlier) just reveal it — don't clobber it.
            if FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) {
                NSWorkspace.shared.activateFileViewerSelecting([dest])
                return
            }
            try FileManager.default.moveItem(at: tmp, to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            NSWorkspace.shared.open(url)
        }
    }
}

// `AppcastParser` moved to MacCleanKit — see Sources/MacCleanKit/AppcastParser.swift.
