import XCTest
@testable import MacCleanKit
import MacCleanTestSupport

final class ThinAppBundleOperationTests: XCTestCase {

    private var bundleURL: URL!

    override func setUpWithError() throws {
        let raw = FileManager.default.temporaryDirectory
            .appending(path: "AppOp-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        bundleURL = URL(filePath: raw.resolvingSymlinksInPath().path(percentEncoded: false))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bundleURL)
    }

    /// Build a minimal `.app`:
    ///   - Contents/Info.plist
    ///   - Contents/MacOS/<name> (real fat Mach-O via cc)
    private func writeMinimalApp(name: String, bundleID: String) throws {
        let macOS = bundleURL.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let exec = macOS.appending(path: name)
        let built = try UniversalBinaryFixture.build(at: exec)
        try XCTSkipUnless(built, "cc not available")

        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": name,
            "CFBundleName": name,
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL",
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try infoData.write(to: bundleURL.appending(path: "Contents/Info.plist"))
    }

    /// Add an embedded framework with one fat Mach-O inside, plus the
    /// Info.plist + symlinks codesign requires to recognize it as a bundle.
    private func addFramework(named name: String) throws {
        let fwRoot = bundleURL.appending(path: "Contents/Frameworks/\(name).framework")
        let versionsA = fwRoot.appending(path: "Versions/A")
        let resources = versionsA.appending(path: "Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        let binary = versionsA.appending(path: name)
        let built = try UniversalBinaryFixture.build(at: binary)
        try XCTSkipUnless(built, "cc not available")

        // Framework's own Info.plist — codesign refuses to recognize the
        // bundle without it ("bundle format unrecognized, invalid, or
        // unsuitable").
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.acme.\(name.lowercased()).framework",
            "CFBundleExecutable": name,
            "CFBundleName": name,
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "FMWK",
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try infoData.write(to: resources.appending(path: "Info.plist"))

        // Canonical framework symlink layout — must use the path-based
        // overload because URL(filePath:) resolves relative paths against
        // the current working directory, producing absolute symlinks that
        // point at nothing.
        let fm = FileManager.default
        try fm.createSymbolicLink(
            atPath: fwRoot.appending(path: "Versions/Current").path(percentEncoded: false),
            withDestinationPath: "A"
        )
        try fm.createSymbolicLink(
            atPath: fwRoot.appending(path: name).path(percentEncoded: false),
            withDestinationPath: "Versions/Current/\(name)"
        )
        try fm.createSymbolicLink(
            atPath: fwRoot.appending(path: "Resources").path(percentEncoded: false),
            withDestinationPath: "Versions/Current/Resources"
        )
    }

    private func archs(_ url: URL) -> [String] {
        UniversalBinaryFixture.architectures(of: url)
    }

    // MARK: - Tests

    func testThinsSingleBinaryApp() async throws {
        try writeMinimalApp(name: "MainApp", bundleID: "com.acme.main")
        let exec = bundleURL.appending(path: "Contents/MacOS/MainApp")
        XCTAssertEqual(Set(archs(exec)), Set(["x86_64", "arm64"]))

        // Seal the bundle the way a real shipped app is sealed, so we can
        // assert the signature SURVIVES thinning (lipo preserves each slice's
        // signature; the operation must not re-sign).
        try XCTSkipUnless(UniversalBinaryFixture.sealBundleAdHoc(at: bundleURL),
                          "codesign sealing unavailable")

        let op = ThinAppBundleOperation()
        let result = try await op.thin(bundle: bundleURL, to: BundleHostInfo.current.hostArch)

        XCTAssertEqual(result.binariesThinned, 1)
        XCTAssertEqual(result.binariesProcessed, 1)
        XCTAssertTrue(result.perBinaryErrors.isEmpty)
        XCTAssertGreaterThan(result.bytesSaved, 0)
        XCTAssertEqual(archs(exec), [BundleHostInfo.current.hostArch.lipoName])
        XCTAssertTrue(UniversalBinaryFixture.codesignVerifiesDeep(bundleURL),
                      "the bundle's signature must remain valid after thinning")
    }

    func testThinsAppWithEmbeddedFramework() async throws {
        try writeMinimalApp(name: "HostApp", bundleID: "com.acme.host")
        try addFramework(named: "Helper")
        let exec = bundleURL.appending(path: "Contents/MacOS/HostApp")
        let fwBinary = bundleURL.appending(path: "Contents/Frameworks/Helper.framework/Versions/A/Helper")

        try XCTSkipUnless(UniversalBinaryFixture.sealBundleAdHoc(at: bundleURL),
                          "codesign sealing unavailable")

        let op = ThinAppBundleOperation()
        let result = try await op.thin(bundle: bundleURL, to: BundleHostInfo.current.hostArch)

        // 2 binaries (main + framework), both should be thinned.
        XCTAssertEqual(result.binariesProcessed, 2)
        XCTAssertEqual(result.binariesThinned, 2,
                       "both main exec and framework binary should be thinned")
        XCTAssertTrue(result.perBinaryErrors.isEmpty,
                      "no per-binary errors expected: \(result.perBinaryErrors)")

        XCTAssertEqual(archs(exec), [BundleHostInfo.current.hostArch.lipoName])
        XCTAssertEqual(archs(fwBinary), [BundleHostInfo.current.hostArch.lipoName])
        XCTAssertTrue(UniversalBinaryFixture.codesignVerifiesDeep(bundleURL),
                      "bundle (including the framework) must stay validly signed after thinning")
    }

    func testRefusesWhenBundleHasAnOpenFile() async throws {
        try writeMinimalApp(name: "BusyApp", bundleID: "com.acme.busy")
        let exec = bundleURL.appending(path: "Contents/MacOS/BusyApp")

        // Hold the binary open from this test process — lsof +D <bundle>
        // will see at least one PID (us).
        let handle = try FileHandle(forReadingFrom: exec)
        defer { try? handle.close() }

        let op = ThinAppBundleOperation()
        do {
            _ = try await op.thin(bundle: bundleURL, to: BundleHostInfo.current.hostArch)
            XCTFail("operation must refuse when bundle has open file descriptors")
        } catch ThinAppBundleOperation.OpError.bundleInUse(let pids) {
            XCTAssertFalse(pids.isEmpty,
                           "bundleInUse error must surface at least one PID")
        }

        // Binary still original (untouched).
        XCTAssertEqual(Set(archs(exec)), Set(["x86_64", "arm64"]),
                       "binary must remain untouched after refusal")
    }

    /// Regression for the "apps quit working after thinning" bug.
    ///
    /// When a universal binary lives somewhere the bundle seals as a plain
    /// resource (e.g. a nested helper under Contents/Resources/), thinning it
    /// breaks the bundle's signature. The operation must NOT paper over that by
    /// re-signing (ad-hoc re-signing strips the original Team ID and bricks
    /// hardened-runtime apps). Instead it must roll the whole bundle back and
    /// report failure, leaving the app exactly as it was.
    func testRollsBackWhenThinningWouldBreakSignedBundle() async throws {
        try writeMinimalApp(name: "HostApp", bundleID: "com.acme.host")
        // A fat Mach-O placed under Contents/Resources/ is sealed by the
        // PARENT bundle as a resource (hashed in CodeResources), not as
        // independently-signed nested code — so thinning it breaks the seal.
        let resourceBinary = bundleURL.appending(path: "Contents/Resources/payload.bin")
        let built = try UniversalBinaryFixture.build(at: resourceBinary)
        try XCTSkipUnless(built, "cc not available")

        // Seal the whole bundle the way a real shipped app is sealed.
        try XCTSkipUnless(UniversalBinaryFixture.sealBundleAdHoc(at: bundleURL),
                          "codesign sealing unavailable")
        try XCTSkipUnless(UniversalBinaryFixture.codesignVerifiesDeep(bundleURL),
                          "sealed fixture must verify before thinning")

        let op = ThinAppBundleOperation()
        do {
            _ = try await op.thin(bundle: bundleURL, to: BundleHostInfo.current.hostArch)
            XCTFail("must refuse: thinning broke the bundle signature and we don't re-sign")
        } catch ThinAppBundleOperation.OpError.bundleVerifyFailed {
            // Expected.
        }

        // The resource binary must be rolled back to its original fat form…
        XCTAssertEqual(Set(archs(resourceBinary)), Set(["x86_64", "arm64"]),
                       "resource binary must be restored to fat after rollback")
        // …and the bundle must verify again (original signature intact).
        XCTAssertTrue(UniversalBinaryFixture.codesignVerifiesDeep(bundleURL),
                      "bundle signature must be intact after rollback")
    }

    func testThrowsWhenNoFatBinariesPresent() async throws {
        // App with only a non-fat main exec.
        let macOS = bundleURL.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let exec = macOS.appending(path: "Tiny")
        // Single-arch build (not fat).
        let built = try UniversalBinaryFixture.build(
            at: exec,
            architectures: [BundleHostInfo.current.hostArch.lipoName]
        )
        try XCTSkipUnless(built, "cc not available")

        let op = ThinAppBundleOperation()
        do {
            _ = try await op.thin(bundle: bundleURL, to: BundleHostInfo.current.hostArch)
            XCTFail("should refuse when no fat binaries exist")
        } catch ThinAppBundleOperation.OpError.noFatBinariesFound {
            // Expected.
        }
    }
}
