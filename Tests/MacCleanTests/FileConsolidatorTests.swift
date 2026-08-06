import XCTest
import Foundation
@testable import MacCleanKit

final class FileConsolidatorTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "FileConsolidator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    @discardableResult
    func write(_ name: String, _ bytes: Data) throws -> URL {
        let u = dir.appending(path: name); try bytes.write(to: u); return u
    }

    func testEligibleIdenticalFilesHaveNoIneligibilityReason() throws {
        let m = try write("m", Data("same".utf8))
        let c = try write("c", Data("same".utf8))
        XCTAssertNil(FileConsolidator.ineligibilityReason(master: m, copy: c, safetyGuard: SafetyGuard()))
    }

    func testSymlinkCopyIsNotRegularFile() throws {
        let m = try write("m", Data("same".utf8))
        let link = dir.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: m)
        XCTAssertEqual(
            FileConsolidator.ineligibilityReason(master: m, copy: link, safetyGuard: SafetyGuard()),
            .notRegularFile)
    }

    func testDirectoryCopyIsNotRegularFile() throws {
        let m = try write("m", Data("same".utf8))
        let sub = dir.appending(path: "subdir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        XCTAssertEqual(
            FileConsolidator.ineligibilityReason(master: m, copy: sub, safetyGuard: SafetyGuard()),
            .notRegularFile)
    }
}
