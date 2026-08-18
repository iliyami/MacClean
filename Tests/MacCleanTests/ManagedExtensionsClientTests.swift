import XCTest
@testable import MacClean
@testable import MacCleanKit

final class ManagedExtensionsClientTests: XCTestCase {

    func testLoadListsUserPaneAndSkipsApple() async {
        let home = URL(filePath: "/Users/tester")
        let userPanes = home.appending(path: "Library/PreferencePanes")
        let apple = userPanes.appending(path: "Security.prefPane")
        let third = userPanes.appending(path: "Bartender.prefPane")
        let client = makeClient(
            home: home,
            children: [userPanes.path(percentEncoded: false): [apple, third]],
            plists: [
                apple.appending(path: "Contents/Info.plist").path(percentEncoded: false): [
                    "CFBundleIdentifier": "com.apple.preference.security",
                    "CFBundleName": "Security",
                ],
                third.appending(path: "Contents/Info.plist").path(percentEncoded: false): [
                    "CFBundleIdentifier": "com.surteesstudios.Bartender",
                    "CFBundleDisplayName": "Bartender 5",
                ],
            ]
        )
        let items = await client.load()
        XCTAssertEqual(items.map(\.name), ["Bartender 5"])
        XCTAssertEqual(items.first?.kind, .preferencePane)
        XCTAssertEqual(client.removal(for: items[0]), .trash)
    }

    func testLoadListsComputerPaneAsRevealOnly() async {
        let home = URL(filePath: "/Users/tester")
        let computer = URL(filePath: "/Library")
        let panes = computer.appending(path: "PreferencePanes")
        let growl = panes.appending(path: "Growl.prefPane")
        let client = makeClient(
            home: home,
            computerLibrary: computer,
            children: [panes.path(percentEncoded: false): [growl]],
            plists: [
                growl.appending(path: "Contents/Info.plist").path(percentEncoded: false): [
                    "CFBundleIdentifier": "com.growl.prefPane",
                    "CFBundleName": "Growl",
                ],
            ]
        )
        let items = await client.load()
        XCTAssertEqual(items.map(\.name), ["Growl"])
        XCTAssertEqual(client.removal(for: items[0]), .revealInFinder)
        XCTAssertTrue(client.trashURLs(from: items).isEmpty)
    }

    func testLoadFindsSafariAppexAndNeverTrashesIt() async {
        let home = URL(filePath: "/Users/tester")
        let apps = URL(filePath: "/Applications")
        let host = apps.appending(path: "Ghostery.app")
        let plugins = host.appending(path: "Contents/PlugIns")
        let appex = plugins.appending(path: "Ghostery.appex")
        let client = makeClient(
            home: home,
            applicationsDirectories: [apps],
            appBundles: [apps.path(percentEncoded: false): [host]],
            children: [plugins.path(percentEncoded: false): [appex]],
            plists: [
                appex.appending(path: "Contents/Info.plist").path(percentEncoded: false): [
                    "CFBundleIdentifier": "com.ghostery.safari",
                    "CFBundleDisplayName": "Ghostery",
                    "NSExtension": [
                        "NSExtensionPointIdentifier": "com.apple.Safari.web-extension",
                    ],
                ],
            ]
        )
        let items = await client.load()
        XCTAssertEqual(items.map(\.bundleIdentifier), ["com.ghostery.safari"])
        XCTAssertEqual(client.removal(for: items[0]), .none)
        XCTAssertTrue(client.trashURLs(from: items).isEmpty)
    }

    func testLoadSkipsFinderSyncAppex() async {
        let home = URL(filePath: "/Users/tester")
        let apps = URL(filePath: "/Applications")
        let host = apps.appending(path: "Thing.app")
        let plugins = host.appending(path: "Contents/PlugIns")
        let appex = plugins.appending(path: "FinderSync.appex")
        let client = makeClient(
            home: home,
            applicationsDirectories: [apps],
            appBundles: [apps.path(percentEncoded: false): [host]],
            children: [plugins.path(percentEncoded: false): [appex]],
            plists: [
                appex.appending(path: "Contents/Info.plist").path(percentEncoded: false): [
                    "CFBundleIdentifier": "com.example.findersync",
                    "CFBundleName": "Finder Sync",
                    "NSExtension": [
                        "NSExtensionPointIdentifier": "com.apple.FinderSync",
                    ],
                ],
            ]
        )
        let items = await client.load()
        XCTAssertTrue(items.isEmpty)
    }

    func testTrashPlanRefusesAdversarialAppContentsPath() async {
        let home = URL(filePath: "/Users/tester")
        let plugins = home.appending(path: "Library/Internet Plug-Ins")
        let trapped = plugins.appending(path: "Fake.app/Contents/PlugIns/Evil.plugin")
        let client = makeClient(
            home: home,
            children: [plugins.path(percentEncoded: false): [trapped]],
            plists: [
                trapped.appending(path: "Contents/Info.plist").path(percentEncoded: false): [
                    "CFBundleIdentifier": "com.evil.plugin",
                    "CFBundleName": "Evil",
                ],
            ]
        )
        let items = await client.load()
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(client.trashURLs(from: items).isEmpty)
    }

    func testSymlinkToSystemIsNotTrashed() async {
        let home = URL(filePath: "/Users/tester")
        let panes = home.appending(path: "Library/PreferencePanes")
        let trap = panes.appending(path: "Trap.prefPane")
        let client = makeClient(
            home: home,
            children: [panes.path(percentEncoded: false): [trap]],
            plists: [
                trap.appending(path: "Contents/Info.plist").path(percentEncoded: false): [
                    "CFBundleIdentifier": "com.evil.trap",
                    "CFBundleName": "Trap",
                ],
            ],
            resolved: [
                trap.path(percentEncoded: false): "/System/Library/PreferencePanes/Trap.prefPane",
            ]
        )
        let items = await client.load()
        XCTAssertTrue(items.isEmpty, "Apple/system resolved paths must not be listed")
        XCTAssertTrue(client.trashURLs(from: items).isEmpty)
    }

    func testPluginKitElectionIsMerged() async {
        let home = URL(filePath: "/Users/tester")
        let apps = URL(filePath: "/Applications")
        let host = apps.appending(path: "Ghostery.app")
        let plugins = host.appending(path: "Contents/PlugIns")
        let appex = plugins.appending(path: "Ghostery.appex")
        let client = makeClient(
            home: home,
            applicationsDirectories: [apps],
            appBundles: [apps.path(percentEncoded: false): [host]],
            children: [plugins.path(percentEncoded: false): [appex]],
            plists: [
                appex.appending(path: "Contents/Info.plist").path(percentEncoded: false): [
                    "CFBundleIdentifier": "com.ghostery.safari",
                    "CFBundleName": "Ghostery",
                    "NSExtension": [
                        "NSExtensionPointIdentifier": "com.apple.Safari.content-blocker",
                    ],
                ],
            ],
            pluginKit: """
                 -    com.ghostery.safari(1.0)
                \t\tPath = \(appex.path(percentEncoded: false))
                \t\tSDK = com.apple.Safari.content-blocker
                """
        )
        let items = await client.load()
        XCTAssertEqual(items.first?.election, .disabled)
    }

    func testOpenSafariSettingsUsesPolicyURL() {
        final class Capture: @unchecked Sendable {
            var url: URL?
        }
        let capture = Capture()
        var client = makeClient(home: URL(filePath: "/Users/tester"))
        client.openURL = { capture.url = $0 }
        client.openSafariSettings()
        XCTAssertEqual(capture.url, ManagedExtensionPolicy.safariSettingsURL)
    }

    func testLoadEmptyWhenDirectoriesMissing() async {
        let client = makeClient(home: URL(filePath: "/Users/tester"))
        let items = await client.load()
        XCTAssertTrue(items.isEmpty)
    }

    func testClientDoesNotElectOrDeleteAppex() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let clientSrc = try String(
            contentsOf: root.appending(path: "Sources/MacClean/Modules/Extensions/ManagedExtensionsClient.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(clientSrc.contains("\"-e\""))
        XCTAssertFalse(clientSrc.contains("pluginkit -e"))
        let viewSrc = try String(
            contentsOf: root.appending(path: "Sources/MacClean/Views/Applications/ExtensionsView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(viewSrc.contains("pluginkit"))
    }

    func testUserPluginIsInTrashPlan() async {
        let home = URL(filePath: "/Users/tester")
        let dir = home.appending(path: "Library/Internet Plug-Ins")
        let plugin = dir.appending(path: "Silverlight.plugin")
        let client = makeClient(
            home: home,
            children: [dir.path(percentEncoded: false): [plugin]],
            plists: [
                plugin.appending(path: "Contents/Info.plist").path(percentEncoded: false): [
                    "CFBundleIdentifier": "com.microsoft.SilverlightPlugin",
                    "CFBundleName": "Silverlight",
                ],
            ]
        )
        let items = await client.load()
        XCTAssertEqual(
            client.trashURLs(from: items).map { $0.path(percentEncoded: false) },
            [plugin.path(percentEncoded: false)]
        )
    }

    // MARK: - Fixture client

    private func makeClient(
        home: URL,
        computerLibrary: URL = URL(filePath: "/Library"),
        applicationsDirectories: [URL] = [],
        appBundles: [String: [URL]] = [:],
        children: [String: [URL]] = [:],
        plists: [String: [String: Any]] = [:],
        resolved: [String: String] = [:],
        pluginKit: String = ""
    ) -> ManagedExtensionsClient {
        var serialized: [String: Data] = [:]
        for (path, plist) in plists {
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
                serialized[path] = data
            }
        }
        let dataByPath = serialized
        return ManagedExtensionsClient(
            home: home,
            computerLibrary: computerLibrary,
            applicationsDirectories: applicationsDirectories,
            listDirectory: { url in
                children[url.path(percentEncoded: false)] ?? []
            },
            readData: { url in
                dataByPath[url.path(percentEncoded: false)]
            },
            resolveSymlinks: { url in
                let path = url.path(percentEncoded: false)
                if let resolved = resolved[path] {
                    return URL(filePath: resolved)
                }
                return url
            },
            appBundles: { dir in
                appBundles[dir.path(percentEncoded: false)] ?? []
            },
            pluginKitOutput: { pluginKit },
            openURL: { _ in },
            reveal: { _ in }
        )
    }

    // Regression: capturing a command whose output exceeds the ~64KB pipe
    // buffer must not deadlock. Before the fix, waitUntilExit ran before the
    // pipe was drained and the Extensions page hung on "Looking for extensions…".
    func testCaptureStandardOutputDoesNotDeadlockOnLargeOutput() {
        // ~205 KB of stdout, well past the pipe buffer.
        let script = "for i in $(seq 1 5000); do echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; done"
        let out = ManagedExtensionsClient.captureStandardOutput(
            of: URL(filePath: "/bin/sh"), arguments: ["-c", script])
        XCTAssertEqual(out.filter { $0 == "\n" }.count, 5000)
        XCTAssertGreaterThan(out.count, 200_000)
    }
}
