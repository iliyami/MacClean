import XCTest
import Foundation
@testable import MacCleanKit

final class FileHashingTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "FileHashing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func write(_ name: String, _ bytes: Data) throws -> URL {
        let u = dir.appending(path: name); try bytes.write(to: u); return u
    }

    func testIdenticalContentHashesEqualDifferentContentDiffers() throws {
        let a = try write("a", Data("hello world".utf8))
        let b = try write("b", Data("hello world".utf8))
        let c = try write("c", Data("HELLO WORLD".utf8))
        XCTAssertEqual(FileHashing.sha256(a), FileHashing.sha256(b))
        XCTAssertNotNil(FileHashing.sha256(a))
        XCTAssertNotEqual(FileHashing.sha256(a), FileHashing.sha256(c))
    }

    func testMissingFileReturnsNil() {
        XCTAssertNil(FileHashing.sha256(dir.appending(path: "nope")))
    }

    func testEmptyFileHashesToKnownSHA256() throws {
        let e = try write("empty", Data())
        // SHA256 of empty input.
        XCTAssertEqual(FileHashing.sha256(e),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}
