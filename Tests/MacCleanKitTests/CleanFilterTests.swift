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

    // MARK: Array extension

    func testFilteringUncleanableKeepsCleanableItemsAndDropsRest() throws {
        // Real cleanable file in a writable dir.
        let okFile = tmpRoot.appending(path: "ok.cache")
        FileManager.default.createFile(atPath: okFile.path, contents: Data([1, 2, 3]))
        // Unwritable parent: simulates root-owned `/Library/Caches/com.apple.*`.
        let locked = tmpRoot.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let trapped = locked.appending(path: "trapped.log")
        FileManager.default.createFile(atPath: trapped.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: locked.path)

        let ok = FileItem(url: okFile, name: "ok.cache", size: 3, allocatedSize: 3, isDirectory: false)
        let bad = FileItem(url: trapped, name: "trapped.log", size: 0, allocatedSize: 0, isDirectory: false)

        let input: [ScanResult] = [
            ScanResult(category: .userCaches, items: [ok, bad])
        ]
        let filtered = input.filteringUncleanable()

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].items.count, 1, "Only the cleanable item should survive")
        XCTAssertEqual(filtered[0].items.first?.name, "ok.cache")
        // Category and autoSelect are preserved across the filter.
        XCTAssertEqual(filtered[0].category, .userCaches)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: locked.path)
    }

    func testFilteringUncleanableDropsUserExcludedFolders() throws {
        let excludedRoot = tmpRoot.appending(path: "keep-me")
        try FileManager.default.createDirectory(at: excludedRoot, withIntermediateDirectories: true)
        let inside = excludedRoot.appending(path: "offline.db")
        FileManager.default.createFile(atPath: inside.path, contents: Data([1]))

        let okRoot = tmpRoot.appending(path: "other")
        try FileManager.default.createDirectory(at: okRoot, withIntermediateDirectories: true)
        let okFile = okRoot.appending(path: "junk.cache")
        FileManager.default.createFile(atPath: okFile.path, contents: Data([2]))

        let keep = FileItem(url: inside, name: "offline.db", size: 1, allocatedSize: 1, isDirectory: false)
        let droppable = FileItem(url: okFile, name: "junk.cache", size: 1, allocatedSize: 1, isDirectory: false)
        let input = [ScanResult(category: .userCaches, items: [keep, droppable])]

        let filtered = input.filteringUncleanable(excludedFolders: [excludedRoot.path])
        XCTAssertEqual(filtered[0].items.map(\.name), ["junk.cache"])
    }

    // MARK: Selected-size estimate (must match what Clean actually frees)

    func testSelectedSizeCountsEachURLOnce() {
        // The same file can surface in two categories (large AND old) or —
        // before scanner dedup — from overlapping scan targets. Clean
        // trashes each path once, so the pre-clean estimate must dedupe by
        // URL too; otherwise it over-reports ("2 GB will be freed" but only
        // 934 MB actually freed).
        let url = URL(filePath: "/tmp/big.dmg")
        let item = FileItem(url: url, name: "big.dmg", size: 1000, allocatedSize: 1000, isDirectory: false)
        let results: [ScanResult] = [
            ScanResult(category: .largeFiles, items: [item]),
            ScanResult(category: .oldFiles, items: [item]),
        ]

        XCTAssertEqual(results.selectedSize([url]), 1000,
                       "a URL present in two results must count once")
    }

    func testSelectedSizeSumsDistinctSelectedItems() {
        let a = FileItem(url: URL(filePath: "/tmp/a.bin"), name: "a", size: 100, allocatedSize: 100, isDirectory: false)
        let b = FileItem(url: URL(filePath: "/tmp/b.bin"), name: "b", size: 250, allocatedSize: 250, isDirectory: false)
        let c = FileItem(url: URL(filePath: "/tmp/c.bin"), name: "c", size: 999, allocatedSize: 999, isDirectory: false)
        let results = [ScanResult(category: .largeFiles, items: [a, b, c])]

        // Only a + b are selected.
        XCTAssertEqual(results.selectedSize([a.url, b.url]), 350)
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
