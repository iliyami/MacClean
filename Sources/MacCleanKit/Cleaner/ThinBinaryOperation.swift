import Foundation
import MacCleanKit
import OSLog

/// Strips redundant architecture slices from a Mach-O universal binary.
///
/// Critically, this does **not** re-sign. Each architecture slice in a fat
/// Mach-O carries its own embedded code signature, so `lipo -thin` leaves the
/// kept slice signed exactly as the developer shipped it (Developer ID, Team
/// ID, notarization all intact). Re-signing would *destroy* that: an ad-hoc
/// signature has no Team ID, which breaks library validation (hardened-runtime
/// apps are killed at launch with "different Team IDs"), keychain access
/// groups, and notarization. So we thin and leave the original signature
/// alone.
///
/// Atomic per-binary: makes a backup, promotes the thinned file by rename, and
/// rolls back the backup if the promote fails. The backup location is supplied
/// by the caller (`backupTo:`) so an orchestrator can keep it for bundle-wide
/// rollback; the convenience `thin(binary:to:)` manages its own throwaway
/// backup for standalone use.
///
/// Pure decision-making lives in `UniversalBinariesPolicy` in MacCleanKit;
/// this type is the system-side actuator that actually invokes lipo.
public actor ThinBinaryOperation {

    public struct Result: Sendable {
        public let originalSize: UInt64
        public let thinnedSize: UInt64
        public var bytesSaved: UInt64 {
            originalSize > thinnedSize ? originalSize - thinnedSize : 0
        }
    }

    public enum OpError: Error, LocalizedError, Sendable {
        case notFat
        case raceDetected(String)
        case lipoFailed(stderr: String)
        case backupFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notFat:
                "input binary is not a fat (universal) Mach-O"
            case .raceDetected(let message):
                "binary changed under us while thinning: \(message)"
            case .lipoFailed(let stderr):
                "lipo failed: \(stderr)"
            case .backupFailed(let message):
                "atomic backup/promote failed: \(message)"
            }
        }
    }

    private let logger = Logger(subsystem: MCConstants.bundleIdentifier,
                                category: "ThinBinaryOperation")

    public init() {}

    /// Thin a standalone binary in place. Manages its own throwaway backup,
    /// removed on success or used to roll back a failed promote.
    public func thin(binary: URL, to targetArch: BinaryArch) async throws -> Result {
        let fm = FileManager.default
        let backupDir = fm.temporaryDirectory
            .appending(path: "macclean-thinning-\(UUID().uuidString)")
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: backupDir) }
        let backupURL = backupDir.appending(path: "\(binary.lastPathComponent).original")
        return try await thin(binary: binary, to: targetArch, backupTo: backupURL)
    }

    /// Thin `binary` to `targetArch` in place, moving the original aside to
    /// `backupURL`. The caller owns `backupURL`: on success it should delete
    /// it; for a multi-binary transaction it can keep every backup and restore
    /// from them if a later step (e.g. a bundle-wide signature check) fails.
    /// No code-signing happens here (see the type comment).
    public func thin(binary: URL, to targetArch: BinaryArch, backupTo backupURL: URL) async throws -> Result {
        let fm = FileManager.default
        let path = binary.path(percentEncoded: false)

        // 1. Confirm input is fat — if not, refuse cleanly without touching it.
        let archs = try Self.runLipoInfo(at: path)
        guard archs.count > 1 else {
            throw OpError.notFat
        }
        guard archs.contains(targetArch.lipoName) else {
            throw OpError.lipoFailed(stderr: "target arch \(targetArch.lipoName) not present in \(archs)")
        }

        let originalAttrs = try fm.attributesOfItem(atPath: path)
        let originalSize = (originalAttrs[.size] as? NSNumber)?.uint64Value ?? 0
        let originalMode = (originalAttrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0o755
        let originalInode = (originalAttrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0

        // 2. Stage the thinned output in a separate temp directory — NOT next
        //    to the original. codesign walks the bundle subtree looking for
        //    subcomponents to validate, so a stray file in the binary's parent
        //    dir (e.g. Contents/MacOS/) would be flagged when the bundle's
        //    signature is later verified.
        let workDir = fm.temporaryDirectory
            .appending(path: "macclean-thinning-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let thinningURL = workDir.appending(path: "\(binary.lastPathComponent).thinned")

        // Race check: re-stat immediately before lipo. If the file has been
        // replaced (different inode) or grown/shrunk (different size), abort
        // — something else is rewriting this file and our lipo would overwrite
        // their changes.
        let preLipoAttrs = try fm.attributesOfItem(atPath: path)
        let preLipoSize = (preLipoAttrs[.size] as? NSNumber)?.uint64Value ?? 0
        let preLipoInode = (preLipoAttrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        if preLipoInode != originalInode || preLipoSize != originalSize {
            throw OpError.raceDetected(
                "inode \(originalInode)→\(preLipoInode) or size \(originalSize)→\(preLipoSize) changed between start and lipo step"
            )
        }

        try Self.runLipoThin(
            input: path,
            output: thinningURL.path(percentEncoded: false),
            arch: targetArch.lipoName
        )
        try fm.setAttributes(
            [.posixPermissions: NSNumber(value: originalMode)],
            ofItemAtPath: thinningURL.path(percentEncoded: false)
        )

        // 3. Atomic-ish swap: move original out to the caller's backup, move
        //    thinned in. lipo already preserved the slice's signature, so no
        //    re-signing is needed or wanted.
        do {
            try fm.moveItem(at: binary, to: backupURL)
        } catch {
            throw OpError.backupFailed("could not back up original: \(error.localizedDescription)")
        }
        do {
            try fm.moveItem(at: thinningURL, to: binary)
        } catch {
            try? fm.moveItem(at: backupURL, to: binary)
            throw OpError.backupFailed("could not promote thinned file: \(error.localizedDescription)")
        }

        let thinnedAttrs = try fm.attributesOfItem(atPath: path)
        let thinnedSize = (thinnedAttrs[.size] as? NSNumber)?.uint64Value ?? 0
        logger.info("Thinned \(path, privacy: .public): \(originalSize) → \(thinnedSize)")
        return Result(originalSize: originalSize, thinnedSize: thinnedSize)
    }

    // MARK: - Shell-out helpers

    private static func runLipoInfo(at path: String) throws -> [String] {
        let (status, stdout, _) = try runProcess(
            "/usr/bin/lipo", ["-info", path]
        )
        guard status == 0 else { throw OpError.lipoFailed(stderr: stdout) }
        if let range = stdout.range(of: "are: ") {
            return stdout[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .map(String.init)
        }
        if let range = stdout.range(of: "is architecture: ") {
            return [stdout[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return []
    }

    private static func runLipoThin(input: String, output: String, arch: String) throws {
        let (status, _, stderr) = try runProcess(
            "/usr/bin/lipo", ["-thin", arch, input, "-output", output]
        )
        guard status == 0 else { throw OpError.lipoFailed(stderr: stderr) }
    }

    /// Returns `(status, stdout, stderr)`. Throws only if the process can't
    /// be launched at all.
    private static func runProcess(
        _ executable: String, _ args: [String]
    ) throws -> (Int32, String, String) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
