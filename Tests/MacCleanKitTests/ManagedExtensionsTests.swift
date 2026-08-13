import XCTest
@testable import MacCleanKit

final class ManagedExtensionsTests: XCTestCase {

    private let home = "/Users/tester"

    // MARK: - Apple / third-party

    func testAppleBundleIDIsVendorApple() {
        XCTAssertTrue(ManagedExtensionPolicy.isAppleVendor(
            bundleID: "com.apple.preference.security",
            resolvedPath: "\(home)/Library/PreferencePanes/Security.prefPane"
        ))
    }

    func testSystemPathIsVendorAppleEvenWithoutBundleID() {
        XCTAssertTrue(ManagedExtensionPolicy.isAppleVendor(
            bundleID: "",
            resolvedPath: "/System/Library/PreferencePanes/DateAndTime.prefPane"
        ))
    }

    func testLibraryApplePrefixIsVendorApple() {
        XCTAssertTrue(ManagedExtensionPolicy.isAppleVendor(
            bundleID: "com.example.helper",
            resolvedPath: "/Library/Apple/System/Library/PreferencePanes/Foo.prefPane"
        ))
    }

    func testThirdPartyPaneIsNotApple() {
        XCTAssertFalse(ManagedExtensionPolicy.isAppleVendor(
            bundleID: "com.barebones.bbedit",
            resolvedPath: "\(home)/Library/PreferencePanes/BBEdit.prefPane"
        ))
    }

    // MARK: - App bundle contents

    func testAppexPathIsInsideAppContents() {
        XCTAssertTrue(ManagedExtensionPolicy.isInsideAppBundleContents(
            "/Applications/1Password.app/Contents/PlugIns/Safari.appex"
        ))
    }

    func testUserPaneIsNotInsideAppContents() {
        XCTAssertFalse(ManagedExtensionPolicy.isInsideAppBundleContents(
            "\(home)/Library/PreferencePanes/Secrets.prefPane"
        ))
    }

    func testHostAppWalksUpFromAppex() {
        let appex = URL(filePath: "/Applications/Ghostery.app/Contents/PlugIns/Ghostery.appex")
        XCTAssertEqual(
            ManagedExtensionPolicy.hostAppURL(forAppex: appex)?.path(percentEncoded: false),
            "/Applications/Ghostery.app"
        )
    }

    // MARK: - Removal policy

    func testUserPrefPaneIsTrashable() {
        let item = pane(
            path: "\(home)/Library/PreferencePanes/BetterTouchTool.prefPane",
            bundleID: "com.hegenberg.BetterTouchTool"
        )
        XCTAssertEqual(removal(item), .trash)
    }

    func testUserInternetPluginIsTrashable() {
        let item = plugin(
            path: "\(home)/Library/Internet Plug-Ins/Silverlight.plugin",
            bundleID: "com.microsoft.SilverlightPlugin"
        )
        XCTAssertEqual(removal(item), .trash)
    }

    func testLegacySafariExtensionInUserLibraryIsTrashable() {
        let item = safari(
            path: "\(home)/Library/Safari/Extensions/Old.safariextz",
            bundleID: "com.example.old-safari"
        )
        XCTAssertEqual(removal(item), .trash)
    }

    func testComputerPrefPaneIsRevealOnly() {
        let item = pane(
            path: "/Library/PreferencePanes/Growl.prefPane",
            bundleID: "com.growl.prefPane"
        )
        XCTAssertEqual(removal(item), .revealInFinder)
    }

    func testComputerPluginIsRevealOnly() {
        let item = plugin(
            path: "/Library/Internet Plug-Ins/Flash Player.plugin",
            bundleID: "com.macromedia.FlashPlayer"
        )
        XCTAssertEqual(removal(item), .revealInFinder)
    }

    func testSafariAppexIsNeverTrashable() {
        let item = safari(
            path: "/Applications/1Password.app/Contents/PlugIns/Safari.appex",
            bundleID: "com.1password.safari.extension",
            host: URL(filePath: "/Applications/1Password.app")
        )
        XCTAssertEqual(removal(item), .none)
    }

    func testApplePaneIsNotRemovable() {
        let item = pane(
            path: "\(home)/Library/PreferencePanes/Dummy.prefPane",
            bundleID: "com.apple.preference.dummy"
        )
        XCTAssertEqual(removal(item), .none)
    }

    func testSymlinkResolvingToSystemIsNotTrashable() {
        let item = pane(
            path: "\(home)/Library/PreferencePanes/Trap.prefPane",
            bundleID: "com.evil.trap"
        )
        XCTAssertEqual(
            ManagedExtensionPolicy.removal(
                for: item,
                resolvedPath: "/System/Library/PreferencePanes/Trap.prefPane",
                home: home
            ),
            .none
        )
    }

    func testAdversarialPathInsideAppContentsIsNeverTrashable() {
        let item = plugin(
            path: "\(home)/Library/Internet Plug-Ins/Fake.app/Contents/PlugIns/Evil.plugin",
            bundleID: "com.evil.plugin"
        )
        XCTAssertEqual(removal(item), .none)
    }

    func testTrashPlanDropsAppexAndKeepsUserPane() {
        let paneItem = pane(
            path: "\(home)/Library/PreferencePanes/Foo.prefPane",
            bundleID: "com.example.foo"
        )
        let appexItem = safari(
            path: "/Applications/Bar.app/Contents/PlugIns/Bar.appex",
            bundleID: "com.example.bar.safari",
            host: URL(filePath: "/Applications/Bar.app")
        )
        let urls = ManagedExtensionPolicy.trashURLs(
            from: [paneItem, appexItem],
            home: home,
            resolvedPath: { $0.path(percentEncoded: false) }
        )
        XCTAssertEqual(
            urls.map { $0.path(percentEncoded: false) },
            ["\(home)/Library/PreferencePanes/Foo.prefPane"]
        )
    }

    func testTrashPlanDropsComputerDomainPane() {
        let item = pane(
            path: "/Library/PreferencePanes/Growl.prefPane",
            bundleID: "com.growl.prefPane"
        )
        XCTAssertTrue(
            ManagedExtensionPolicy.trashURLs(
                from: [item],
                home: home,
                resolvedPath: { $0.path(percentEncoded: false) }
            ).isEmpty
        )
    }

    // MARK: - Catalog

    func testCatalogBuildsUserPaneFromPlist() {
        let url = URL(filePath: "\(home)/Library/PreferencePanes/Bartender.prefPane")
        let item = ManagedExtensionCatalog.item(
            kind: .preferencePane,
            url: url,
            plist: [
                "CFBundleIdentifier": "com.surteesstudios.Bartender",
                "CFBundleName": "Bartender",
                "CFBundleDisplayName": "Bartender 5",
            ],
            resolvedPath: url.path(percentEncoded: false),
            home: home
        )
        XCTAssertEqual(item?.name, "Bartender 5")
        XCTAssertEqual(item?.bundleIdentifier, "com.surteesstudios.Bartender")
        XCTAssertEqual(item?.domain, .user)
        XCTAssertEqual(item?.kind, .preferencePane)
        XCTAssertFalse(item?.isApple ?? true)
    }

    func testCatalogSkipsApplePane() {
        let url = URL(filePath: "/Library/PreferencePanes/Apple.prefPane")
        XCTAssertNil(
            ManagedExtensionCatalog.item(
                kind: .preferencePane,
                url: url,
                plist: ["CFBundleIdentifier": "com.apple.preference.desktopscreeneffect"],
                resolvedPath: url.path(percentEncoded: false),
                home: home
            )
        )
    }

    func testCatalogSkipsNonSafariAppex() {
        let url = URL(filePath: "/Applications/Thing.app/Contents/PlugIns/FinderSync.appex")
        XCTAssertNil(
            ManagedExtensionCatalog.item(
                kind: .safariExtension,
                url: url,
                plist: [
                    "CFBundleIdentifier": "com.example.findersync",
                    "CFBundleName": "Finder Sync",
                    "NSExtension": [
                        "NSExtensionPointIdentifier": "com.apple.FinderSync",
                    ],
                ],
                resolvedPath: url.path(percentEncoded: false),
                home: home
            )
        )
    }

    func testCatalogKeepsSafariWebExtensionAppex() {
        let url = URL(filePath: "/Applications/Ghostery.app/Contents/PlugIns/Ghostery.appex")
        let item = ManagedExtensionCatalog.item(
            kind: .safariExtension,
            url: url,
            plist: [
                "CFBundleIdentifier": "com.ghostery.safari",
                "CFBundleDisplayName": "Ghostery",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.Safari.web-extension",
                ],
            ],
            resolvedPath: url.path(percentEncoded: false),
            home: home
        )
        XCTAssertEqual(item?.kind, .safariExtension)
        XCTAssertEqual(item?.safariPointIdentifier, "com.apple.Safari.web-extension")
        XCTAssertEqual(
            item?.hostAppPath?.path(percentEncoded: false),
            "/Applications/Ghostery.app"
        )
        XCTAssertEqual(item?.election, .unknown)
    }

    func testCatalogKeepsLegacySafariPackageWithoutExtensionPoint() {
        let url = URL(filePath: "\(home)/Library/Safari/Extensions/Old.safariextz")
        let item = ManagedExtensionCatalog.item(
            kind: .safariExtension,
            url: url,
            plist: ["CFBundleIdentifier": "com.example.old"],
            resolvedPath: url.path(percentEncoded: false),
            home: home
        )
        XCTAssertEqual(item?.name, "Old")
        XCTAssertEqual(item?.domain, .user)
    }

    func testCatalogFallsBackToFileNameWhenPlistMissing() {
        let url = URL(filePath: "\(home)/Library/Internet Plug-Ins/Silverlight.plugin")
        let item = ManagedExtensionCatalog.item(
            kind: .internetPlugin,
            url: url,
            plist: nil,
            resolvedPath: url.path(percentEncoded: false),
            home: home
        )
        XCTAssertEqual(item?.name, "Silverlight")
        XCTAssertEqual(item?.bundleIdentifier, "")
    }

    // MARK: - pluginkit parser

    func testPluginKitParserReadsElectionPathAndSDK() {
        let output = """
             +    com.1password.safari.extension(8.10.40)
            \t\tPath = /Applications/1Password.app/Contents/PlugIns/Safari.appex
            \t\tUUID = ABC-DEF
            \t\tVersion = 8.10.40
            \t\tDisplay Name = 1Password
            \t\tSDK = com.apple.Safari.web-extension
            \t\tParent Bundle ID = com.1password.1password

                 -    com.ghostery.safari(1.0)
            \t\tPath = /Applications/Ghostery.app/Contents/PlugIns/Ghostery.appex
            \t\tSDK = com.apple.Safari.content-blocker
            """
        let records = PluginKitParser.records(from: output)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].election, .enabled)
        XCTAssertEqual(records[0].bundleIdentifier, "com.1password.safari.extension")
        XCTAssertEqual(
            records[0].path,
            "/Applications/1Password.app/Contents/PlugIns/Safari.appex"
        )
        XCTAssertEqual(records[0].sdk, "com.apple.Safari.web-extension")
        XCTAssertEqual(records[1].election, .disabled)
        XCTAssertEqual(records[1].bundleIdentifier, "com.ghostery.safari")
    }

    func testPluginKitParserEmptyAndInvalid() {
        XCTAssertTrue(PluginKitParser.records(from: "").isEmpty)
        XCTAssertTrue(PluginKitParser.records(from: "match: Connection invalid\n").isEmpty)
    }

    func testMergeElectionsOverlaysMatchingBundleID() {
        let url = URL(filePath: "/Applications/Ghostery.app/Contents/PlugIns/Ghostery.appex")
        guard let item = ManagedExtensionCatalog.item(
            kind: .safariExtension,
            url: url,
            plist: [
                "CFBundleIdentifier": "com.ghostery.safari",
                "CFBundleName": "Ghostery",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.Safari.web-extension",
                ],
            ],
            resolvedPath: url.path(percentEncoded: false),
            home: home
        ) else {
            return XCTFail("expected catalog item")
        }
        XCTAssertEqual(item.election, .unknown)
        let merged = ManagedExtensionCatalog.mergeElections(
            [item],
            pluginkit: [
                PluginKitRecord(
                    election: .disabled,
                    bundleIdentifier: "com.ghostery.safari",
                    path: url.path(percentEncoded: false),
                    sdk: "com.apple.Safari.web-extension"
                ),
            ]
        )
        XCTAssertEqual(merged.first?.election, .disabled)
    }

    func testSafariSettingsURLIsSafariSettingsDeepLink() {
        XCTAssertEqual(
            ManagedExtensionPolicy.safariSettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.Safari-Settings"
        )
    }

    // MARK: - Helpers

    private func pane(path: String, bundleID: String) -> ManagedExtension {
        ManagedExtension(
            kind: .preferencePane,
            name: URL(filePath: path).deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundleID,
            path: URL(filePath: path),
            hostAppPath: nil,
            domain: ManagedExtensionPolicy.domain(of: path, home: home) ?? .local,
            isApple: ManagedExtensionPolicy.isAppleVendor(bundleID: bundleID, resolvedPath: path),
            election: .unknown,
            safariPointIdentifier: nil
        )
    }

    private func plugin(path: String, bundleID: String) -> ManagedExtension {
        ManagedExtension(
            kind: .internetPlugin,
            name: URL(filePath: path).deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundleID,
            path: URL(filePath: path),
            hostAppPath: nil,
            domain: ManagedExtensionPolicy.domain(of: path, home: home) ?? .local,
            isApple: ManagedExtensionPolicy.isAppleVendor(bundleID: bundleID, resolvedPath: path),
            election: .unknown,
            safariPointIdentifier: nil
        )
    }

    private func safari(path: String, bundleID: String, host: URL? = nil) -> ManagedExtension {
        ManagedExtension(
            kind: .safariExtension,
            name: URL(filePath: path).deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundleID,
            path: URL(filePath: path),
            hostAppPath: host,
            domain: ManagedExtensionPolicy.domain(of: path, home: home) ?? .local,
            isApple: ManagedExtensionPolicy.isAppleVendor(bundleID: bundleID, resolvedPath: path),
            election: .unknown,
            safariPointIdentifier: "com.apple.Safari.web-extension"
        )
    }

    private func removal(_ item: ManagedExtension) -> ManagedExtensionRemoval {
        ManagedExtensionPolicy.removal(
            for: item,
            resolvedPath: item.path.path(percentEncoded: false),
            home: home
        )
    }
}
