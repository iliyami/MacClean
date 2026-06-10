import XCTest
@testable import MacCleanKit
import MacCleanTestSupport

/// Real lipo + codesign exercised against synthetic universal binaries.
///
/// These tests are slow-ish (each compiles a tiny C program with two -arch
/// flags), so we keep the suite small. The pure decision logic is exhaustively
/// tested in UniversalBinariesPolicyTests; here we only verify the system
/// operation actually does the right thing on real Mach-O files.
final class ThinBinaryOperationTests: XCTestCase {

    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "ThinBinaryOp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    private func makeFatBinary() throws -> URL {
        let url = workDir.appending(path: "hello")
        let built = try UniversalBinaryFixture.build(at: url)
        try XCTSkipUnless(built, "cc not available — can't build the fat-binary fixture")
        return url
    }

    // MARK: - The happy path

    func testThinsToHostArch_reducesSize_keepsCodesignValid_keepsExecutable() async throws {
        let binary = try makeFatBinary()

        let originalSize = try FileManager.default
            .attributesOfItem(atPath: binary.path(percentEncoded: false))[.size] as? UInt64
        XCTAssertNotNil(originalSize)
        XCTAssertEqual(Set(UniversalBinaryFixture.architectures(of: binary)),
                       Set(["x86_64", "arm64"]),
                       "fixture must start as a fat x86_64+arm64 binary")

        let op = ThinBinaryOperation()
        let result = try await op.thin(binary: binary, to: BundleHostInfo.current.hostArch)

        // Smaller on disk.
        XCTAssertLessThan(result.thinnedSize, result.originalSize)
        XCTAssertGreaterThan(result.bytesSaved, 0)

        // Now single-arch, matching host.
        let archsAfter = UniversalBinaryFixture.architectures(of: binary)
        XCTAssertEqual(archsAfter, [BundleHostInfo.current.hostArch.lipoName],
                       "binary should be single-arch matching host after thinning")

        // Signature preserved by lipo (NOT re-applied): the kept slice keeps
        // its original embedded signature, so it still verifies.
        XCTAssertTrue(UniversalBinaryFixture.codesignVerifies(binary),
                      "thinned binary must keep its original valid signature")

        // Still executable.
        let process = Process()
        process.executableURL = binary
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "thinned binary must run cleanly")
        let stdout = String(
            data: outPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       BundleHostInfo.current.hostArch.lipoName,
                       "thinned binary's runtime output identifies the kept arch")
    }

    // MARK: - Safety: non-fat binary refused

    func testRefusesNonFatBinary() async throws {
        // Build a single-arch binary by passing only the host arch.
        let url = workDir.appending(path: "single")
        let built = try UniversalBinaryFixture.build(
            at: url,
            architectures: [BundleHostInfo.current.hostArch.lipoName]
        )
        try XCTSkipUnless(built, "cc not available")
        XCTAssertEqual(UniversalBinaryFixture.architectures(of: url).count, 1)

        let op = ThinBinaryOperation()
        do {
            _ = try await op.thin(binary: url, to: BundleHostInfo.current.hostArch)
            XCTFail("should refuse non-fat input")
        } catch ThinBinaryOperation.OpError.notFat {
            // Expected.
        }
    }

    // MARK: - Atomicity: no backup file left behind on success

    func testCleansUpAfterSuccess() async throws {
        let binary = try makeFatBinary()
        let op = ThinBinaryOperation()
        _ = try await op.thin(binary: binary, to: BundleHostInfo.current.hostArch)

        let dirContents = try FileManager.default.contentsOfDirectory(
            atPath: workDir.path(percentEncoded: false)
        )
        let strays = dirContents.filter {
            $0.contains(".macclean-backup") || $0.contains(".macclean-thinning")
        }
        XCTAssertTrue(strays.isEmpty,
                      "no backup or temp artifacts should remain after success — saw \(strays)")
    }

    // (CleanActions routing now expects bundle URLs, not bare binaries.
    // That path is covered end-to-end in UniversalBinariesScannerTests.
    // ThinBinaryOperationTests stays focused on the bare-binary primitive.)

    // MARK: - Permissions preserved

    func testPreservesFileMode() async throws {
        let binary = try makeFatBinary()
        // Set a distinctive non-default mode so we can detect preservation.
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o750)],
            ofItemAtPath: binary.path(percentEncoded: false)
        )

        let op = ThinBinaryOperation()
        _ = try await op.thin(binary: binary, to: BundleHostInfo.current.hostArch)

        let modeAfter = try FileManager.default
            .attributesOfItem(atPath: binary.path(percentEncoded: false))[.posixPermissions] as? NSNumber
        XCTAssertEqual(modeAfter?.int16Value, 0o750,
                       "file mode must be preserved through thinning")
    }
}
