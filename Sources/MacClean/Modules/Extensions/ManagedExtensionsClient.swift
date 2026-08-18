import AppKit
import Foundation
import MacCleanKit

/// Lists third-party panes, Internet Plug-Ins, and Safari extensions.
/// Filesystem / `pluginkit` / workspace are injected so tests never touch the live Mac.
struct ManagedExtensionsClient: Sendable {
    var home: URL
    var computerLibrary: URL
    var applicationsDirectories: [URL]
    var listDirectory: @Sendable (URL) -> [URL]
    var readData: @Sendable (URL) -> Data?
    var resolveSymlinks: @Sendable (URL) -> URL
    var appBundles: @Sendable (URL) -> [URL]
    var pluginKitOutput: @Sendable () async -> String
    var openURL: @Sendable (URL) -> Void
    var reveal: @Sendable (URL) -> Void

    static func live() -> ManagedExtensionsClient {
        ManagedExtensionsClient(
            home: MCConstants.home,
            computerLibrary: URL(filePath: "/Library"),
            applicationsDirectories: [
                URL(filePath: "/Applications"),
                MCConstants.home.appending(path: "Applications"),
            ],
            listDirectory: { url in
                (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
            },
            readData: { url in try? Data(contentsOf: url) },
            resolveSymlinks: { $0.resolvingSymlinksInPath() },
            appBundles: { AppDiscovery.appBundles(in: $0) },
            pluginKitOutput: { await Self.runPluginKit() },
            openURL: { url in
                Task { @MainActor in
                    NSWorkspace.shared.open(url)
                }
            },
            reveal: { url in
                Task { @MainActor in
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        )
    }

    func load() async -> [ManagedExtension] {
        var items: [ManagedExtension] = []
        items.append(contentsOf: scan(
            kind: .preferencePane,
            directories: [
                home.appending(path: "Library/PreferencePanes"),
                computerLibrary.appending(path: "PreferencePanes"),
            ],
            extensions: ["prefpane"]
        ))
        items.append(contentsOf: scan(
            kind: .internetPlugin,
            directories: [
                home.appending(path: "Library/Internet Plug-Ins"),
                computerLibrary.appending(path: "Internet Plug-Ins"),
            ],
            extensions: ["plugin", "webplugin"]
        ))
        items.append(contentsOf: scan(
            kind: .safariExtension,
            directories: [
                home.appending(path: "Library/Safari/Extensions"),
            ],
            extensions: ["safariextz", "safariextension"]
        ))
        items.append(contentsOf: scanSafariAppex())

        var seen = Set<String>()
        items = items.filter { seen.insert($0.id).inserted }

        let overlay = PluginKitParser.records(from: await pluginKitOutput())
        items = ManagedExtensionCatalog.mergeElections(items, pluginkit: overlay)
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func removal(for item: ManagedExtension) -> ManagedExtensionRemoval {
        ManagedExtensionPolicy.removal(
            for: item,
            resolvedPath: resolveSymlinks(item.path).path(percentEncoded: false),
            home: home.path(percentEncoded: false)
        )
    }

    func trashURLs(from items: [ManagedExtension]) -> [URL] {
        ManagedExtensionPolicy.trashURLs(
            from: items,
            home: home.path(percentEncoded: false),
            resolvedPath: { resolveSymlinks($0).path(percentEncoded: false) }
        )
    }

    func openSafariSettings() {
        openURL(ManagedExtensionPolicy.safariSettingsURL)
    }

    func revealInFinder(_ url: URL) {
        reveal(url)
    }

    // MARK: - Scan

    private func scan(
        kind: ManagedExtensionKind,
        directories: [URL],
        extensions: Set<String>
    ) -> [ManagedExtension] {
        var found: [ManagedExtension] = []
        for directory in directories {
            for url in listDirectory(directory) {
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                if let item = catalogItem(kind: kind, url: url) {
                    found.append(item)
                }
            }
        }
        return found
    }

    private func scanSafariAppex() -> [ManagedExtension] {
        var found: [ManagedExtension] = []
        for appsDir in applicationsDirectories {
            for app in appBundles(appsDir) {
                let plugIns = app.appending(path: "Contents/PlugIns")
                for url in listDirectory(plugIns) {
                    guard url.pathExtension.lowercased() == "appex" else { continue }
                    if let item = catalogItem(kind: .safariExtension, url: url) {
                        found.append(item)
                    }
                }
            }
        }
        return found
    }

    private func catalogItem(kind: ManagedExtensionKind, url: URL) -> ManagedExtension? {
        let plist = plist(at: url.appending(path: "Contents/Info.plist"))
            ?? plist(at: url.appending(path: "Info.plist"))
        let resolved = resolveSymlinks(url).path(percentEncoded: false)
        return ManagedExtensionCatalog.item(
            kind: kind,
            url: url,
            plist: plist,
            resolvedPath: resolved,
            home: home.path(percentEncoded: false)
        )
    }

    private func plist(at url: URL) -> [String: Any]? {
        guard let data = readData(url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist
    }

    private static func runPluginKit() async -> String {
        captureStandardOutput(of: URL(filePath: "/usr/bin/pluginkit"), arguments: ["-m", "-v"])
    }

    /// Run a process and return its stdout, draining the pipe BEFORE
    /// `waitUntilExit`. Reading after waiting deadlocks: a command with more
    /// output than the ~64KB pipe buffer (pluginkit lists hundreds of plug-ins)
    /// blocks writing while we block waiting, and the load never completes.
    /// stderr is discarded to /dev/null so it can't fill and deadlock either.
    static func captureStandardOutput(of executable: URL, arguments: [String]) -> String {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
