import XCTest
@testable import MacCleanKit

final class CleanFilterTests: XCTestCase {
    private var tmpRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "CleanFilterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore perms before delete so the test sandbox doesn't leak.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: tmpRoot.path)
        try? FileManager.default.removeItem(at: tmpRoot)
        try super.tearDownWithError()
    }

    // MARK: Cleanable cases

    func testFileInUserOwnedWritableDirIsCleanable() throws {
        let file = tmpRoot.appending(path: "cache.bin")
        FileManager.default.createFile(atPath: file.path, contents: Data([1, 2, 3]))
        XCTAssertTrue(CleanFilter.isCleanableByCurrentProcess(file))
    }

    func testWritableDirectoryIsCleanable() throws {
        let dir = tmpRoot.appending(path: "subdir")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertTrue(CleanFilter.isCleanableByCurrentProcess(dir))
    }

    // MARK: Non-cleanable cases

    func testNonexistentPathIsNotCleanable() {
        let ghost = tmpRoot.appending(path: "does-not-exist-\(UUID().uuidString)")
        XCTAssertFalse(CleanFilter.isCleanableByCurrentProcess(ghost))
    }

    func testFileWhoseParentIsNotWritableIsNotCleanable() throws {
        // Simulates the `/Library/Caches/com.apple.InferenceProviderService/foo.cache`
        // case: parent dir exists and the file exists, but we don't have
        // write permission on the parent so `unlink` would fail.
        let lockedParent = tmpRoot.appending(path: "locked")
        try FileManager.default.createDirectory(at: lockedParent, withIntermediateDirectories: true)
        let file = lockedParent.appending(path: "trapped.txt")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        // Remove write bit on the parent (read+execute only).
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: lockedParent.path)

        XCTAssertFalse(CleanFilter.isCleanableByCurrentProcess(file))

        // Restore so tearDown can clean up.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: lockedParent.path)
    }

    func testDirectoryWhoseContentsAreNotWritableIsNotCleanable() throws {
        // Simulates `~/Library/Caches/com.apple.containermanagerd/`: we own
        // the parent, but the directory itself rejects writes. This is the
        // closest portable analogue of the data-vault case — we can't
        // actually set UF_DATAVAULT from userland, but stripping our own
        // write bit on the dir reproduces the syscall-level denial that
        // `isCleanableByCurrentProcess` keys on.
        let dataVaultLike = tmpRoot.appending(path: "vaulted")
        try FileManager.default.createDirectory(at: dataVaultLike, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: dataVaultLike.path)

        XCTAssertFalse(CleanFilter.isCleanableByCurrentProcess(dataVaultLike))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: dataVaultLike.path)
    }

    func testFilesInsideUnwritableDirectoryAreNotCleanable() throws {
        // Even individual files inside an unwritable parent should be
        // dropped — this is what catches every leaf inside a root-owned
        // junk directory before the user sees them.
        let parent = tmpRoot.appending(path: "rootlike")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let leaf1 = parent.appending(path: "a.log")
        let leaf2 = parent.appending(path: "b.log")
        FileManager.default.createFile(atPath: leaf1.path, contents: Data())
        FileManager.default.createFile(atPath: leaf2.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: parent.path)

        XCTAssertFalse(CleanFilter.isCleanableByCurrentProcess(leaf1))
        XCTAssertFalse(CleanFilter.isCleanableByCurrentProcess(leaf2))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: parent.path)
    }
}
