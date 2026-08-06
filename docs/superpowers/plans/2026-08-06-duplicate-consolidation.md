# Duplicate Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Consolidate" mode to the Duplicates module that reclaims space by replacing selected duplicate copies with APFS clones of the kept master, keeping every path working.

**Architecture:** A pure `FileConsolidator` in `MacCleanKit` performs a safe per-copy clone-swap (re-hash, `clonefile` to a temp in the copy's directory, verify, atomic `rename`). `DuplicatesView` gets a mode toggle that routes the existing selection to either the delete path or `FileConsolidator`. A pure mapping helper turns display groups + selection into consolidation work.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Darwin (`clonefile(2)`, `rename(2)`, `statfs`), CryptoKit (SHA256).

## Global Constraints

- Swift 6 strict concurrency; new public types are `Sendable`.
- Bump `VERSION` and `Sources/MacCleanKit/Constants.swift` `appVersion` together; this feature is a minor bump: **1.18.7 -> 1.19.0**.
- Pre-push gate (all must pass): `bash scripts/check-version-sync.sh && swift build && swift test`.
- No em dashes in README/docs/user-facing copy. No AI attribution or Co-Authored-By in commits.
- All UI strings use `L10n.tr("<zh>", "<en>", "<ru>")`.
- `MacCleanKit` must not import the `MacClean` app module (dependency points one way). Hashing used by the consolidator therefore lives in `MacCleanKit`.
- v1 scope: APFS + same-volume only; everything else skipped with a reason. Do not modify the scanner to hide already-consolidated groups (deferred).

---

### Task 1: `FileHashing.sha256` in MacCleanKit

**Files:**
- Create: `Sources/MacCleanKit/FileHashing.swift`
- Test: `Tests/MacCleanTests/FileHashingTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum FileHashing { static func sha256(_ url: URL) -> String? }` — streaming SHA256 hex digest of a file's contents, `nil` if unreadable.

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FileHashingTests`
Expected: FAIL to build ("cannot find 'FileHashing' in scope").

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import CryptoKit

/// Streaming SHA256 of a file's contents as a lowercase hex string.
/// Lives in MacCleanKit so both DuplicatesModule and FileConsolidator can hash
/// without the app module. Returns nil if the file cannot be opened.
public enum FileHashing {
    public static func sha256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 65536)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FileHashingTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MacCleanKit/FileHashing.swift Tests/MacCleanTests/FileHashingTests.swift
git commit -m "Add FileHashing.sha256 in MacCleanKit"
```

---

### Task 2: FileConsolidator types + eligibility

**Files:**
- Create: `Sources/MacCleanKit/FileConsolidator.swift`
- Test: `Tests/MacCleanTests/FileConsolidatorTests.swift`

**Interfaces:**
- Consumes: `SafetyGuard` (`SafetyGuard().validatePath(_:) throws`), `FileHashing.sha256`.
- Produces:
  - `enum ConsolidationOutcome: Equatable, Sendable { case reclaimed(bytes: UInt64); case skipped(SkipReason); case failed(String) }`
  - `enum SkipReason: Equatable, Sendable { case contentChanged, notSameVolume, cloningUnsupported, notRegularFile, notWritable, protectedPath }`
  - `struct SkippedItem: Equatable, Sendable { let url: URL; let reason: SkipReason }`
  - `struct FailedItem: Equatable, Sendable { let url: URL; let message: String }`
  - `struct ConsolidationSummary: Equatable, Sendable { var reclaimedBytes: UInt64; var consolidatedCount: Int; var skipped: [SkippedItem]; var failed: [FailedItem] }`
  - `struct GroupConsolidation: Sendable { let master: URL; let copies: [URL] }`
  - `enum FileConsolidator` with `static func ineligibilityReason(master:copy:safetyGuard:) -> SkipReason?`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FileConsolidatorTests`
Expected: FAIL to build ("cannot find 'FileConsolidator'").

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum ConsolidationOutcome: Equatable, Sendable {
    case reclaimed(bytes: UInt64)
    case skipped(SkipReason)
    case failed(String)
}

public enum SkipReason: Equatable, Sendable {
    case contentChanged
    case notSameVolume
    case cloningUnsupported
    case notRegularFile
    case notWritable
    case protectedPath
}

public struct SkippedItem: Equatable, Sendable {
    public let url: URL
    public let reason: SkipReason
    public init(url: URL, reason: SkipReason) { self.url = url; self.reason = reason }
}

public struct FailedItem: Equatable, Sendable {
    public let url: URL
    public let message: String
    public init(url: URL, message: String) { self.url = url; self.message = message }
}

public struct ConsolidationSummary: Equatable, Sendable {
    public var reclaimedBytes: UInt64
    public var consolidatedCount: Int
    public var skipped: [SkippedItem]
    public var failed: [FailedItem]
    public init(reclaimedBytes: UInt64 = 0, consolidatedCount: Int = 0,
                skipped: [SkippedItem] = [], failed: [FailedItem] = []) {
        self.reclaimedBytes = reclaimedBytes
        self.consolidatedCount = consolidatedCount
        self.skipped = skipped
        self.failed = failed
    }
}

public struct GroupConsolidation: Sendable {
    public let master: URL
    public let copies: [URL]
    public init(master: URL, copies: [URL]) { self.master = master; self.copies = copies }
}

/// Replaces redundant duplicate copies with APFS clones of a master so every
/// path keeps working while identical files stop costing N times their size.
/// Pure and filesystem-only; no UI or global state.
public enum FileConsolidator {

    // MARK: Eligibility (step 1 of the swap; also powers the dry-run estimate)

    /// nil means the pair passes every precondition for a clone-swap.
    public static func ineligibilityReason(master: URL, copy: URL,
                                           safetyGuard: SafetyGuard) -> SkipReason? {
        guard isRegularFile(master), isRegularFile(copy) else { return .notRegularFile }
        guard sameVolume(master, copy) else { return .notSameVolume }
        guard supportsCloning(copy) else { return .cloningUnsupported }
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: copy.path(percentEncoded: false)),
              fm.isWritableFile(atPath: copy.deletingLastPathComponent().path(percentEncoded: false))
        else { return .notWritable }
        do { try safetyGuard.validatePath(copy) } catch { return .protectedPath }
        return nil
    }

    static func isRegularFile(_ url: URL) -> Bool {
        guard let v = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]) else { return false }
        return (v.isRegularFile ?? false) && !(v.isSymbolicLink ?? false) && !(v.isPackage ?? false)
    }

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let va = (try? a.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
        let vb = (try? b.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
        guard let va, let vb else { return false }
        return (va as AnyObject).isEqual(vb)
    }

    static func supportsCloning(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeSupportsFileCloningKey]))?
            .volumeSupportsFileCloning ?? false
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FileConsolidatorTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MacCleanKit/FileConsolidator.swift Tests/MacCleanTests/FileConsolidatorTests.swift
git commit -m "FileConsolidator: types and eligibility checks (#65)"
```

---

### Task 3: The single-pair clone-swap

**Files:**
- Modify: `Sources/MacCleanKit/FileConsolidator.swift`
- Test: `Tests/MacCleanTests/FileConsolidatorTests.swift`

**Interfaces:**
- Consumes: `ineligibilityReason`, `FileHashing.sha256`, Darwin `clonefile`, `rename`, `statfs`.
- Produces: `static func consolidate(master: URL, copy: URL, safetyGuard: SafetyGuard = SafetyGuard()) -> ConsolidationOutcome`

- [ ] **Step 1: Write the failing tests**

```swift
    func testConsolidateKeepsBothFilesReclaimsAndPreservesCopyMetadata() throws {
        let payload = Data(repeating: 0xAB, count: 64 * 1024)
        let master = try write("master.bin", payload)
        let copy = try write("copy.bin", payload)
        // Give the copy its own perms + mtime so we can prove they survive.
        let mtime = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o644)), .modificationDate: mtime],
            ofItemAtPath: copy.path(percentEncoded: false))

        let outcome = FileConsolidator.consolidate(master: master, copy: copy)

        guard case .reclaimed(let bytes) = outcome else {
            return XCTFail("expected reclaimed, got \(outcome)")
        }
        XCTAssertGreaterThan(bytes, 0)
        // Both paths still exist and are byte-identical.
        XCTAssertEqual(try Data(contentsOf: master), payload)
        XCTAssertEqual(try Data(contentsOf: copy), payload)
        // Copy kept its own metadata, not the master's.
        let attrs = try FileManager.default.attributesOfItem(atPath: copy.path(percentEncoded: false))
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.int16Value, 0o644)
        XCTAssertEqual((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0, mtime.timeIntervalSince1970, accuracy: 1)
        // No leftover temp files in the directory.
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))
        XCTAssertEqual(names.filter { $0.contains("consolidate-") }, [])
    }

    func testConsolidateSkipsWhenContentChanged() throws {
        let master = try write("m", Data("original".utf8))
        let copy = try write("c", Data("DIFFERENT".utf8))
        XCTAssertEqual(FileConsolidator.consolidate(master: master, copy: copy), .skipped(.contentChanged))
        // Untouched.
        XCTAssertEqual(try Data(contentsOf: copy), Data("DIFFERENT".utf8))
    }

    func testConsolidateIsIdempotentAndKeepsIntegrity() throws {
        let payload = Data(repeating: 0x5A, count: 32 * 1024)
        let master = try write("m", payload)
        let copy = try write("c", payload)
        _ = FileConsolidator.consolidate(master: master, copy: copy)
        let second = FileConsolidator.consolidate(master: master, copy: copy)
        // Second run must not corrupt anything (byte count may be optimistic).
        if case .failed(let msg) = second { XCTFail("second run failed: \(msg)") }
        XCTAssertEqual(try Data(contentsOf: copy), payload)
        XCTAssertEqual(try Data(contentsOf: master), payload)
    }

    /// Proves it actually CLONED (shared extents) rather than copied: a plain
    /// copy-over would net ~0 free space; a clone frees the copy's blocks.
    func testConsolidateActuallyReclaimsDiskSpace() throws {
        let size = 20 * 1024 * 1024
        let payload = Data(repeating: 0xC3, count: size)
        let master = try write("big-master.bin", payload)
        let copy = try write("big-copy.bin", payload)

        func freeBytes() -> UInt64 {
            var s = statfs()
            let r = dir.path(percentEncoded: false).withCString { statfs($0, &s) }
            return r == 0 ? UInt64(s.f_bavail) * UInt64(s.f_bsize) : 0
        }
        let before = freeBytes()
        guard case .reclaimed = FileConsolidator.consolidate(master: master, copy: copy) else {
            return XCTFail("expected reclaimed")
        }
        let after = freeBytes()
        // Freed at least 70% of the copy (tolerance for FS noise). A non-clone
        // copy-over would be ~0 or negative.
        XCTAssertGreaterThan(Int64(after) - Int64(before), Int64(Double(size) * 0.7),
                             "expected clone to free most of the copy's blocks")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FileConsolidatorTests`
Expected: FAIL to build ("no member 'consolidate'").

- [ ] **Step 3: Write minimal implementation**

Add to the `FileConsolidator` enum (import `Darwin` at top of the file if not already imported by Foundation):

```swift
    // MARK: Single-pair clone-swap

    public static func consolidate(master: URL, copy: URL,
                                   safetyGuard: SafetyGuard = SafetyGuard()) -> ConsolidationOutcome {
        if let reason = ineligibilityReason(master: master, copy: copy, safetyGuard: safetyGuard) {
            return .skipped(reason)
        }
        // Re-verify identical NOW (TOCTOU guard).
        guard let masterHash = FileHashing.sha256(master),
              let copyHash = FileHashing.sha256(copy),
              masterHash == copyHash else {
            return .skipped(.contentChanged)
        }

        let fm = FileManager.default
        let copyPath = copy.path(percentEncoded: false)

        // Snapshot metadata + allocated size (the reclaimed figure).
        let attrs = try? fm.attributesOfItem(atPath: copyPath)
        let perms = attrs?[.posixPermissions] as? NSNumber
        let mtime = attrs?[.modificationDate] as? Date
        let reclaimed = UInt64((try? copy.resourceValues(
            forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)

        // Clone master into a unique hidden temp in the copy's own directory.
        let tempURL = copy.deletingLastPathComponent()
            .appendingPathComponent(".\(copy.lastPathComponent).consolidate-\(UUID().uuidString)")
        let tempPath = tempURL.path(percentEncoded: false)
        let cloned = master.path(percentEncoded: false).withCString { src in
            tempPath.withCString { dst in clonefile(src, dst, 0) == 0 }
        }
        guard cloned else { return .failed("clonefile failed for \(copyPath)") }

        // Verify the clone byte-for-byte before we swap it in.
        guard FileHashing.sha256(tempURL) == masterHash else {
            try? fm.removeItem(at: tempURL)
            return .failed("clone verification failed for \(copyPath)")
        }

        // Restore the copy's own permissions + mtime onto the clone.
        var restore: [FileAttributeKey: Any] = [:]
        if let perms { restore[.posixPermissions] = perms }
        if let mtime { restore[.modificationDate] = mtime }
        if !restore.isEmpty { try? fm.setAttributes(restore, ofItemAtPath: tempPath) }

        // Atomic swap (same volume => rename is atomic). Original stays intact on failure.
        let swapped = tempPath.withCString { t in copyPath.withCString { c in rename(t, c) == 0 } }
        guard swapped else {
            try? fm.removeItem(at: tempURL)
            return .failed("atomic swap failed for \(copyPath)")
        }
        return .reclaimed(bytes: reclaimed)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FileConsolidatorTests`
Expected: PASS (7 tests total in the class).

- [ ] **Step 5: Commit**

```bash
git add Sources/MacCleanKit/FileConsolidator.swift Tests/MacCleanTests/FileConsolidatorTests.swift
git commit -m "FileConsolidator: safe single-pair clone-swap (#65)"
```

---

### Task 4: Batch consolidation + dry-run estimate

**Files:**
- Modify: `Sources/MacCleanKit/FileConsolidator.swift`
- Test: `Tests/MacCleanTests/FileConsolidatorTests.swift`

**Interfaces:**
- Consumes: `consolidate(master:copy:)`, `ineligibilityReason`.
- Produces:
  - `static func consolidate(groups: [GroupConsolidation], safetyGuard: SafetyGuard = SafetyGuard()) -> ConsolidationSummary`
  - `static func estimateReclaimable(groups: [GroupConsolidation], safetyGuard: SafetyGuard = SafetyGuard()) -> UInt64`

- [ ] **Step 1: Write the failing tests**

```swift
    func testBatchAggregatesReclaimedAndSkipped() throws {
        let payload = Data(repeating: 0x11, count: 8 * 1024)
        let master = try write("gm", payload)
        let good = try write("good", payload)
        let changed = try write("changed", Data("nope".utf8))
        let group = GroupConsolidation(master: master, copies: [good, changed])

        let summary = FileConsolidator.consolidate(groups: [group])

        XCTAssertEqual(summary.consolidatedCount, 1)
        XCTAssertGreaterThan(summary.reclaimedBytes, 0)
        XCTAssertEqual(summary.skipped, [SkippedItem(url: changed, reason: .contentChanged)])
        XCTAssertEqual(summary.failed, [])
    }

    func testEstimateSumsEligibleCopiesAndWritesNothing() throws {
        let payload = Data(repeating: 0x22, count: 16 * 1024)
        let master = try write("em", payload)
        let a = try write("ea", payload)
        let b = try write("eb", payload)
        let changed = try write("ec", Data("x".utf8))
        let before = try Data(contentsOf: a)

        let est = FileConsolidator.estimateReclaimable(
            groups: [GroupConsolidation(master: master, copies: [a, b, changed])])

        // a and b are eligible (identical + same volume); changed is a
        // different size but still ELIGIBLE by step-1 checks (estimate does not
        // hash), so all three regular files count. Estimate is a cheap preview.
        XCTAssertGreaterThan(est, 0)
        // Nothing was written.
        XCTAssertEqual(try Data(contentsOf: a), before)
        XCTAssertEqual(try Data(contentsOf: master), payload)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FileConsolidatorTests`
Expected: FAIL to build ("no member 'consolidate(groups:'").

- [ ] **Step 3: Write minimal implementation**

Add to `FileConsolidator`:

```swift
    // MARK: Batch + estimate

    public static func consolidate(groups: [GroupConsolidation],
                                   safetyGuard: SafetyGuard = SafetyGuard()) -> ConsolidationSummary {
        var summary = ConsolidationSummary()
        for group in groups {
            for copy in group.copies {
                if Task.isCancelled { return summary }
                switch consolidate(master: group.master, copy: copy, safetyGuard: safetyGuard) {
                case .reclaimed(let bytes):
                    summary.reclaimedBytes += bytes
                    summary.consolidatedCount += 1
                case .skipped(let reason):
                    summary.skipped.append(SkippedItem(url: copy, reason: reason))
                case .failed(let message):
                    summary.failed.append(FailedItem(url: copy, message: message))
                }
            }
        }
        return summary
    }

    public static func estimateReclaimable(groups: [GroupConsolidation],
                                           safetyGuard: SafetyGuard = SafetyGuard()) -> UInt64 {
        var total: UInt64 = 0
        for group in groups {
            for copy in group.copies
            where ineligibilityReason(master: group.master, copy: copy, safetyGuard: safetyGuard) == nil {
                total += UInt64((try? copy.resourceValues(
                    forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FileConsolidatorTests`
Expected: PASS (9 tests total in the class).

- [ ] **Step 5: Commit**

```bash
git add Sources/MacCleanKit/FileConsolidator.swift Tests/MacCleanTests/FileConsolidatorTests.swift
git commit -m "FileConsolidator: batch consolidation and dry-run estimate (#65)"
```

---

### Task 5: Selection mapping + DuplicatesView consolidate mode

**Files:**
- Create: `Sources/MacClean/Views/Files/DuplicatesConsolidation.swift`
- Modify: `Sources/MacClean/Views/Files/DuplicatesView.swift`
- Test: `Tests/MacCleanTests/DuplicatesConsolidationTests.swift`

**Interfaces:**
- Consumes: `DuplicateDisplayGroup` (`.original: FileItem`, `.duplicates: [FileItem]`, `FileItem.url`), `FileConsolidator.GroupConsolidation`, `FileConsolidator.consolidate(groups:)`, `estimateReclaimable`.
- Produces:
  - `enum DuplicatesActionMode: Equatable { case remove, consolidate }`
  - `enum DuplicatesConsolidation { static func groups(from: [DuplicateDisplayGroup], selection: Set<URL>) -> [GroupConsolidation] }`

- [ ] **Step 1: Write the failing test (pure mapping)**

```swift
import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit

final class DuplicatesConsolidationTests: XCTestCase {
    private func item(_ path: String, _ size: UInt64 = 100) -> FileItem {
        FileItem(url: URL(filePath: path), name: URL(filePath: path).lastPathComponent,
                 size: size, allocatedSize: size, isDirectory: false, modificationDate: nil)
    }

    func testMapsSelectedCopiesUnderTheirOriginalAsMaster() {
        let g = DuplicateDisplayGroup(
            original: item("/A/report.psd"),
            duplicates: [item("/B/report.psd"), item("/C/report.psd")])
        let selection: Set<URL> = [URL(filePath: "/B/report.psd")]  // only one copy chosen

        let groups = DuplicatesConsolidation.groups(from: [g], selection: selection)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].master, URL(filePath: "/A/report.psd"))
        XCTAssertEqual(groups[0].copies, [URL(filePath: "/B/report.psd")])
    }

    func testGroupsWithNoSelectedCopiesAreExcluded() {
        let g = DuplicateDisplayGroup(
            original: item("/A/a"), duplicates: [item("/B/a")])
        XCTAssertTrue(DuplicatesConsolidation.groups(from: [g], selection: []).isEmpty)
    }

    func testOriginalIsNeverTreatedAsACopyEvenIfSelected() {
        let g = DuplicateDisplayGroup(
            original: item("/A/a"), duplicates: [item("/B/a")])
        // Selecting the original must not add it as a copy to clone over.
        let groups = DuplicatesConsolidation.groups(
            from: [g], selection: [URL(filePath: "/A/a"), URL(filePath: "/B/a")])
        XCTAssertEqual(groups[0].copies, [URL(filePath: "/B/a")])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DuplicatesConsolidationTests`
Expected: FAIL to build ("cannot find 'DuplicatesConsolidation'").

- [ ] **Step 3: Write minimal implementation**

Create `Sources/MacClean/Views/Files/DuplicatesConsolidation.swift`:

```swift
import Foundation
import MacCleanKit

/// Whether the Duplicates action deletes copies or consolidates them into clones.
enum DuplicatesActionMode: Equatable {
    case remove
    case consolidate
}

/// Pure mapping from display groups + the user's selection to the consolidation
/// work list: per group, the kept original is the master and the selected
/// duplicates are the copies to replace with clones. Groups with no selected
/// copy are dropped. Testable without SwiftUI.
enum DuplicatesConsolidation {
    static func groups(from displayGroups: [DuplicateDisplayGroup],
                       selection: Set<URL>) -> [GroupConsolidation] {
        displayGroups.compactMap { group in
            let copies = group.duplicates
                .map(\.url)
                .filter { selection.contains($0) }
            guard !copies.isEmpty else { return nil }
            return GroupConsolidation(master: group.original.url, copies: copies)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DuplicatesConsolidationTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MacClean/Views/Files/DuplicatesConsolidation.swift Tests/MacCleanTests/DuplicatesConsolidationTests.swift
git commit -m "Duplicates: pure selection-to-consolidation mapping (#65)"
```

- [ ] **Step 6: Wire the mode toggle + consolidate action into DuplicatesView**

In `Sources/MacClean/Views/Files/DuplicatesView.swift`:

1. Add state near the other `@State` declarations:

```swift
    @State private var actionMode: DuplicatesActionMode = .remove
    @State private var consolidateConfirm = false
    @State private var consolidateSummary: ConsolidationSummary?
    @State private var consolidateTask: Task<Void, Never>?
```

2. In the results branch (the `!results.isEmpty` `ModuleContainerView` at lines ~44-66), above the results content, add a mode Picker:

```swift
    Picker("", selection: $actionMode) {
        Text(L10n.tr("删除重复项", "Remove duplicates", "Удалить дубликаты")).tag(DuplicatesActionMode.remove)
        Text(L10n.tr("合并", "Consolidate", "Объединить")).tag(DuplicatesActionMode.consolidate)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .padding(.horizontal, 20)
```

3. Route the primary action by mode. Where the container's `onClean: clean` is passed, wrap it:

```swift
    onClean: { actionMode == .consolidate ? (consolidateConfirm = true) : clean() },
```

4. Add the confirmation + done handling. Add a `.confirmationDialog` on the results view:

```swift
    .confirmationDialog(
        L10n.tr("合并所选副本？", "Consolidate selected copies?", "Объединить выбранные копии?"),
        isPresented: $consolidateConfirm, titleVisibility: .visible
    ) {
        Button(L10n.tr("合并", "Consolidate", "Объединить")) { consolidate() }
        Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) {}
    } message: {
        let est = FileConsolidator.estimateReclaimable(
            groups: DuplicatesConsolidation.groups(from: displayGroups, selection: selectedItems))
        Text(L10n.tr(
            "保留所有副本，预计释放 \(FileSizeFormatter.format(est))",
            "Keeps every copy, frees about \(FileSizeFormatter.format(est))",
            "Сохраняет все копии, освободит примерно \(FileSizeFormatter.format(est))"))
    }
```

5. Add the `consolidate()` runner and reset wiring (mirrors `clean()` / cancel patterns):

```swift
    private func consolidate() {
        let groups = DuplicatesConsolidation.groups(from: displayGroups, selection: selectedItems)
        cleaning = CleaningEngine.Progress(
            totalItems: groups.reduce(0) { $0 + $1.copies.count },
            processedItems: 0, removedSoFar: 0, freedBytesSoFar: 0)
        consolidateTask?.cancel()
        consolidateTask = Task {
            let summary = await Task.detached { FileConsolidator.consolidate(groups: groups) }.value
            cleaning = nil
            consolidateSummary = summary
            completion = CleanSummary(
                selectedCount: summary.consolidatedCount + summary.skipped.count + summary.failed.count,
                removedCount: summary.consolidatedCount,
                freedBytes: summary.reclaimedBytes,
                errorMessages: summary.failed.map(\.message)
                    + summary.skipped.map { "\($0.url.lastPathComponent): \(skipLabel($0.reason))" })
        }
    }

    private func skipLabel(_ reason: SkipReason) -> String {
        switch reason {
        case .contentChanged: L10n.tr("内容已更改", "content changed", "содержимое изменилось")
        case .notSameVolume: L10n.tr("跨卷", "different volume", "другой том")
        case .cloningUnsupported: L10n.tr("非 APFS 卷", "not an APFS volume", "не том APFS")
        case .notRegularFile: L10n.tr("非普通文件", "not a regular file", "не обычный файл")
        case .notWritable: L10n.tr("不可写", "not writable", "недоступно для записи")
        case .protectedPath: L10n.tr("受保护路径", "protected path", "защищённый путь")
        }
    }
```

6. In `reset()`, add `consolidateTask?.cancel(); consolidateTask = nil; consolidateSummary = nil; actionMode = .remove`.

7. Add `import MacCleanKit` if not present (it is, via existing usage).

- [ ] **Step 7: Build and run the related suites**

Run: `swift build && swift test --filter DuplicatesConsolidationTests`
Expected: build succeeds; mapping tests pass. Manually confirm the results screen shows the segmented toggle and the confirm dialog reports an estimate.

- [ ] **Step 8: Commit**

```bash
git add Sources/MacClean/Views/Files/DuplicatesView.swift
git commit -m "Duplicates: consolidate mode toggle, confirm, and done reporting (#65)"
```

---

### Task 6: README, version bump, full gate

**Files:**
- Modify: `README.md`, `README.ru.md`, `README.zh-CN.md`
- Modify: `VERSION`, `Sources/MacCleanKit/Constants.swift`

**Interfaces:**
- Consumes: everything above. Produces: shippable feature.

- [ ] **Step 1: Add a Duplicates consolidation bullet to each README**

In the data-safety / features list of each README, add one line (place it near the Duplicates/deletion bullets), matching each file's language:

- `README.md`: `- **Duplicate consolidation** - reclaim space without deleting: on APFS, redundant copies are replaced with copy-on-write clones of a kept master, so every path keeps working and identical files stop costing N times their size`
- `README.ru.md`: Russian translation of the same line.
- `README.zh-CN.md`: Chinese translation of the same line.

- [ ] **Step 2: Bump the version**

```bash
printf '1.19.0\n' > VERSION
```

Edit `Sources/MacCleanKit/Constants.swift`: `appVersion = "1.18.7"` -> `appVersion = "1.19.0"`.

- [ ] **Step 3: Run the full gate**

Run: `bash scripts/check-version-sync.sh && swift build && swift test`
Expected: `Version sync OK: 1.19.0`, build succeeds, all tests pass (0 failures).

- [ ] **Step 4: Commit**

```bash
git add README.md README.ru.md README.zh-CN.md VERSION Sources/MacCleanKit/Constants.swift
git commit -m "Duplicate consolidation: docs and version bump to 1.19.0 (#65)"
```

---

## Self-Review

**Spec coverage:**
- FileConsolidator backend (types, eligibility, single-pair, batch, estimate) -> Tasks 2-4. ✓
- Safe clone-swap chain (re-hash, clone to temp, verify, atomic rename, metadata preserve) -> Task 3. ✓
- Hashing available in MacCleanKit -> Task 1. ✓
- UI mode toggle + confirm estimate + done reporting -> Task 5. ✓
- Selection-to-work mapping (master = kept original) -> Task 5. ✓
- APFS/same-volume-only skips with reasons -> Task 2 (`ineligibilityReason`) surfaced in Task 5 done screen. ✓
- Real space-reclaim proof + metadata/idempotency/differ tests -> Task 3. ✓
- Docs + minor version bump -> Task 6. ✓

**Placeholder scan:** No TBD/TODO; every code and test step is concrete. ✓

**Type consistency:** `ConsolidationOutcome`, `SkipReason`, `SkippedItem`, `FailedItem`, `ConsolidationSummary`, `GroupConsolidation`, `FileConsolidator.consolidate(master:copy:)`, `consolidate(groups:)`, `estimateReclaimable(groups:)`, `ineligibilityReason(master:copy:safetyGuard:)`, `FileHashing.sha256`, `DuplicatesActionMode`, `DuplicatesConsolidation.groups(from:selection:)` are used identically across tasks. `ConsolidationSummary` uses structs (not tuples) so `Equatable` synthesizes. ✓

**Note vs spec:** the spec sketched `skipped`/`failed` as tuple arrays; the plan uses `SkippedItem`/`FailedItem` structs so `ConsolidationSummary: Equatable` compiles. Behaviour is unchanged.
