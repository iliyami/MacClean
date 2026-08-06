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

    // MARK: Single-pair clone-swap

    /// Replace `copy` with an APFS clone of `master`, in place and atomically.
    /// Any failed precondition or error leaves the original `copy` untouched.
    public static func consolidate(master: URL, copy: URL,
                                   safetyGuard: SafetyGuard = SafetyGuard()) -> ConsolidationOutcome {
        if let reason = ineligibilityReason(master: master, copy: copy, safetyGuard: safetyGuard) {
            return .skipped(reason)
        }
        // Re-verify identical NOW (TOCTOU guard: the file may have changed since the scan).
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

        // Clone master into a unique hidden temp in the copy's own directory
        // (same volume, so the later rename is atomic).
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
}
