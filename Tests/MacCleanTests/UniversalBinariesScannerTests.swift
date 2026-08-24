import XCTest
@testable import MacClean
import MacCleanKit
import MacCleanTestSupport

/// Walks a synthetic `.app` bundle in /tmp to verify the scanner correctly
/// combines bundle inspection (Info.plist, _MASReceipt) with the pure
/// `UniversalBinariesPolicy` decision logic.
final class UniversalBinariesScannerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "UBScanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates a `.app` bundle structure with a real fat Mach-O executable.
    /// Returns the `.app` URL.
    private func makeFakeApp(
        name: String,
        bundleID: String,
        archs: [String] = ["x86_64", "arm64"],
        appStore: Bool = false
    ) throws -> URL {
        let appURL = root.appending(path: "\(name).app")
        let macOS = appURL.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

        let executableName = name.replacingOccurrences(of: " ", with: "")
        let exec = macOS.appending(path: executableName)
        let built = try UniversalBinaryFixture.build(at: exec, architectures: archs)
        try XCTSkipUnless(built, "cc not available")

        let infoPlist = appURL.appending(path: "Contents/Info.plist")
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": executableName,
            "CFBundleName": name,
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL",
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try plistData.write(to: infoPlist)

        if appStore {
            let receipt = appURL.appending(path: "Contents/_MASReceipt/receipt")
            try FileManager.default.createDirectory(
                at: receipt.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("fake-receipt".utf8).write(to: receipt)
        }
        return appURL
    }

    /// Adds a real fat Mach-O at `Contents/Frameworks/<frameworkName>` to an
    /// already-created app bundle, simulating a third-party framework
    /// (Sparkle, Electron/CEF, ffmpeg, …) that stayed universal even though
    /// the app's own main executable is thin/native.
    @discardableResult
    private func embedFatFramework(
        in appURL: URL,
        named frameworkName: String = "Sparkle",
        archs: [String] = ["x86_64", "arm64"]
    ) throws -> Bool {
        let binary = appURL.appending(path: "Contents/Frameworks/\(frameworkName)")
        return try UniversalBinaryFixture.build(at: binary, architectures: archs)
    }

    func testScanner_picksUpFatNonAppleApp() throws {
        let appURL = try makeFakeApp(name: "AcmeChat", bundleID: "com.acme.chat")

        let items = UniversalBinariesScanner.scan(in: root)
        XCTAssertEqual(items.count, 1, "AcmeChat should be eligible")
        // Surfaces the bundle URL (not the inner executable) so the cleanup
        // path can walk the whole bundle.
        XCTAssertEqual(items[0].url.standardizedFileURL,
                       appURL.standardizedFileURL)
        XCTAssertTrue(items[0].isDirectory,
                      "FileItem points at the .app bundle directory")
        XCTAssertGreaterThan(items[0].size, 0,
                             "estimated savings must be reported for the UI")
    }

    func testScanner_skipsAppleSystemBundleByID() throws {
        _ = try makeFakeApp(name: "Pretend Safari", bundleID: "com.apple.Safari")
        let items = UniversalBinariesScanner.scan(in: root)
        XCTAssertTrue(items.isEmpty, "com.apple.* bundles must be skipped by policy")
    }

    func testScanner_skipsAppStoreApps() throws {
        _ = try makeFakeApp(
            name: "AppStoreThing",
            bundleID: "com.example.appstore",
            appStore: true
        )
        let items = UniversalBinariesScanner.scan(in: root)
        XCTAssertTrue(items.isEmpty, "_MASReceipt presence must skip the bundle")
    }

    func testScanner_skipsSingleArchApp() throws {
        let onlyHost = BundleHostInfo.current.hostArch.lipoName
        _ = try makeFakeApp(name: "NativeOnly", bundleID: "com.example.native", archs: [onlyHost])
        let items = UniversalBinariesScanner.scan(in: root)
        XCTAssertTrue(items.isEmpty, "single-arch app already matches host — nothing to thin")
    }

    /// Regression test for the bug where eligibility was decided from the
    /// main executable alone: an app whose main exec is already thin/native
    /// but that still bundles a fat third-party framework (Sparkle,
    /// Electron/CEF, ffmpeg, …) must still be offered for thinning — there's
    /// real space to reclaim inside the framework even though the main exec
    /// itself has nothing to do.
    func testScanner_picksUpFatEmbeddedFrameworkEvenWhenMainExecIsThin() throws {
        let onlyHost = BundleHostInfo.current.hostArch.lipoName
        let appURL = try makeFakeApp(
            name: "ThinMainFatFramework", bundleID: "com.example.thinmain", archs: [onlyHost]
        )
        let embedded = try embedFatFramework(in: appURL)
        try XCTSkipUnless(embedded, "cc not available")

        let items = UniversalBinariesScanner.scan(in: root)
        XCTAssertEqual(
            items.count, 1,
            "app must still be offered: its embedded framework is fat even though the main exec is thin"
        )
        XCTAssertGreaterThan(items[0].size, 0, "estimated savings must reflect the fat framework")
    }

    /// A genuinely fully-thin app (main exec AND every embedded binary
    /// single-arch) has nothing to reclaim anywhere and must stay skipped.
    func testScanner_skipsAppWithNoFatBinariesAnywhere() throws {
        let onlyHost = BundleHostInfo.current.hostArch.lipoName
        let appURL = try makeFakeApp(
            name: "FullyThin", bundleID: "com.example.fullythin", archs: [onlyHost]
        )
        try XCTSkipUnless(
            try embedFatFramework(in: appURL, archs: [onlyHost]),
            "cc not available"
        )
        let items = UniversalBinariesScanner.scan(in: root)
        XCTAssertTrue(items.isEmpty, "nothing anywhere in the bundle is fat — nothing to thin")
    }

    /// Regression test: the scanner used to only look at `/Applications`,
    /// silently missing every app installed under `~/Applications`.
    func testScanAllApplicationsDirectories_mergesSystemAndUserApplications() throws {
        let systemApplications = root.appending(path: "Applications")
        let userHome = root.appending(path: "Home")
        let userApplications = userHome.appending(path: "Applications")
        try FileManager.default.createDirectory(at: systemApplications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userApplications, withIntermediateDirectories: true)

        // Build directly into each root instead of reusing makeFakeApp
        // (which always targets `root` itself).
        func makeApp(in dir: URL, name: String, bundleID: String) throws {
            let appURL = dir.appending(path: "\(name).app")
            let macOS = appURL.appending(path: "Contents/MacOS")
            try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
            let exec = macOS.appending(path: name)
            let built = try UniversalBinaryFixture.build(at: exec, architectures: ["x86_64", "arm64"])
            try XCTSkipUnless(built, "cc not available")
            let plist: [String: Any] = [
                "CFBundleIdentifier": bundleID, "CFBundleExecutable": name,
                "CFBundleName": name, "CFBundleVersion": "1",
                "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL",
            ]
            let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try plistData.write(to: appURL.appending(path: "Contents/Info.plist"))
        }

        try makeApp(in: systemApplications, name: "SystemWideApp", bundleID: "com.acme.systemwide")
        try makeApp(in: userApplications, name: "UserOnlyApp", bundleID: "com.acme.useronly")

        let items = UniversalBinariesScanner.scanAllApplicationsDirectories(
            systemApplications: systemApplications,
            home: userHome
        )
        let names = Set(items.map { $0.url.lastPathComponent })
        XCTAssertEqual(
            names, ["SystemWideApp.app", "UserOnlyApp.app"],
            "both the system-wide and the per-user Applications folder must be scanned"
        )
    }

    /// End-to-end: scan a synthetic app, take its FileItem, hand to
    /// CleanActions.executeUserClean as a .universalBinaries ScanResult.
    /// Confirm the inner binary on disk is now single-arch and the
    /// bundle's codesign is still valid.
    func testScannerToCleanActions_endToEnd_thinsTheBinaryInPlace() async throws {
        let appURL = try makeFakeApp(name: "AcmeChat", bundleID: "com.acme.chat")
        // Seal the bundle like a real shipped app so we can assert the
        // signature survives thinning (lipo preserves it; we never re-sign).
        try XCTSkipUnless(UniversalBinaryFixture.sealBundleAdHoc(at: appURL),
                          "codesign sealing unavailable")
        let items = UniversalBinariesScanner.scan(in: root)
        XCTAssertEqual(items.count, 1)
        let item = items[0]

        let result = await CleanActions.executeUserClean(
            results: [ScanResult(category: .universalBinaries, items: items, autoSelect: false)],
            selectedItems: [item.url],
            engine: CleaningEngine()
        )

        XCTAssertEqual(result.removedCount, 1)
        XCTAssertTrue(result.errors.isEmpty, "no errors expected: \(result.errors)")

        // Inner exec is now single-arch.
        let exec = appURL.appending(path: "Contents/MacOS/AcmeChat")
        XCTAssertEqual(UniversalBinaryFixture.architectures(of: exec),
                       [BundleHostInfo.current.hostArch.lipoName])
        // Bundle (and its deep contents) still verifies — thinning preserved
        // the original signature without re-signing.
        XCTAssertTrue(UniversalBinaryFixture.codesignVerifiesDeep(appURL),
                      "outer .app bundle should still pass codesign --verify --deep")

        // App bundle still exists (just smaller).
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path(percentEncoded: false)))
    }
}
