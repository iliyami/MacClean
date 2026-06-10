import Foundation
import MacCleanKit
import OSLog

/// Walks an entire `.app` bundle and thins every fat Mach-O inside it via
/// `ThinBinaryOperation`, preserving each binary's original code signature.
///
/// We deliberately do NOT re-sign the bundle. `lipo -thin` keeps the kept
/// architecture slice signed exactly as the developer shipped it, so a
/// normally-laid-out bundle stays validly signed by its original identity
/// (Developer ID + Team ID + notarization) with no further work. Re-signing
/// ad-hoc — what an earlier version did — strips the Team ID and bricks
/// hardened-runtime apps (library validation kills them at launch) while also
/// breaking keychain access and notarization.
///
/// The one hazard is a universal binary that the bundle seals as a plain
/// resource (e.g. a helper nested under `Contents/Resources/`): thinning it
/// invalidates the bundle signature and we can't fix that without the
/// developer's private key. So if the bundle was validly signed before
/// thinning and is no longer valid after, we roll the entire bundle back to
/// its original state and fail — an unchanged app beats a broken one.
public actor ThinAppBundleOperation {

    public struct Result: Sendable {
        public let binariesProcessed: Int
        public let binariesThinned: Int
        public let bytesSaved: UInt64
        public let perBinaryErrors: [String: String]   // path → error
        public let bundleVerifyFailed: Bool
    }

    public enum OpError: Error, LocalizedError, Sendable {
        case noFatBinariesFound
        case bundleInUse(pids: [String])
        case bundleVerifyFailed(stderr: String)

        public var errorDescription: String? {
            switch self {
            case .noFatBinariesFound:
                "no fat (universal) Mach-O binaries found in bundle"
            case .bundleInUse(let pids):
                "bundle is in use by process(es) \(pids.joined(separator: ", ")) — quit the app and try again"
            case .bundleVerifyFailed(let s):
                "thinning would have invalidated the app's code signature, so it was rolled back: \(s)"
            }
        }
    }

    private let logger = Logger(subsystem: MCConstants.bundleIdentifier,
                                category: "ThinAppBundleOperation")

    public init() {}

    public func thin(bundle: URL, to targetArch: BinaryArch) async throws -> Result {
        // Pre-flight: nothing else may be using the bundle. If the user is
        // running Slack and tries to thin Slack, lipo would succeed but the
        // running process holds stale handles into the old binary that's
        // now sitting in our temp dir. Refuse rather than half-mutate.
        let busyPIDs = try Self.pidsHoldingFilesIn(bundle: bundle)
        if !busyPIDs.isEmpty {
            throw OpError.bundleInUse(pids: busyPIDs)
        }

        let binaries = MachOWalker.fatBinaries(in: bundle)
        guard !binaries.isEmpty else { throw OpError.noFatBinariesFound }

        // Was the bundle validly signed before we touched it? Only then do we
        // owe it a post-thin validity guarantee. An unsigned/dev bundle has no
        // signature to preserve or break, so thinning is best-effort there.
        let bundleWasSigned = Self.codesignVerifiesDeep(bundle)

        let fm = FileManager.default
        let backupDir = fm.temporaryDirectory
            .appending(path: "macclean-bundlethin-\(UUID().uuidString)")
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        // Cleaned up explicitly on success and on rollback; defer is the
        // backstop for any unexpected throw in between.
        defer { try? fm.removeItem(at: backupDir) }

        let op = ThinBinaryOperation()
        var thinned = 0
        var saved: UInt64 = 0
        var perBin: [String: String] = [:]
        var rollback: [(binary: URL, backup: URL)] = []

        for (index, binary) in binaries.enumerated() {
            let backupURL = backupDir.appending(path: "\(index).original")
            do {
                let r = try await op.thin(binary: binary, to: targetArch, backupTo: backupURL)
                thinned += 1
                saved += r.bytesSaved
                rollback.append((binary: binary, backup: backupURL))
            } catch {
                let path = binary.path(percentEncoded: false)
                perBin[path] = error.localizedDescription
                logger.error("ThinBinaryOperation failed on \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Safety gate: a bundle that was validly signed must still be valid
        // after thinning. If it isn't (a universal binary was sealed as a
        // plain resource, say), restore every thinned binary from its backup
        // and fail — we will not leave the user a broken app, and we will not
        // "fix" it by re-signing it into a different identity.
        if thinned > 0, bundleWasSigned, !Self.codesignVerifiesDeep(bundle) {
            for entry in rollback {
                try? fm.removeItem(at: entry.binary)
                try? fm.moveItem(at: entry.backup, to: entry.binary)
            }
            try? fm.removeItem(at: backupDir)
            throw OpError.bundleVerifyFailed(
                stderr: "bundle no longer passes codesign --verify after thinning"
            )
        }

        try? fm.removeItem(at: backupDir)

        return Result(
            binariesProcessed: binaries.count,
            binariesThinned: thinned,
            bytesSaved: saved,
            perBinaryErrors: perBin,
            bundleVerifyFailed: false
        )
    }

    // MARK: - lsof pre-flight

    /// Returns the PIDs of any processes with open file descriptors anywhere
    /// inside `bundle`. Implemented via `lsof +D` — recursive directory
    /// scan. Returns an empty array if nothing is holding the bundle open.
    ///
    /// `lsof` exits 1 in BOTH cases of "no match" and "yes match, also some
    /// warnings printed to stderr" — so we ignore the exit code and parse
    /// stdout directly. Empty stdout → bundle is quiescent.
    static func pidsHoldingFilesIn(bundle: URL) throws -> [String] {
        let (_, stdout, _) = try runProcess("/usr/sbin/lsof", [
            "-F", "p",                                       // PID-only output
            "+D", bundle.path(percentEncoded: false),        // recurse into dir
        ])
        var pids = Set<String>()
        for line in stdout.split(separator: "\n") where line.first == "p" {
            pids.insert(String(line.dropFirst()))
        }
        return Array(pids)
    }

    // MARK: - codesign helpers

    /// True if the whole bundle (including nested code) passes
    /// `codesign --verify --deep`. Used both to learn whether the bundle was
    /// validly signed before thinning and to confirm it still is afterward.
    private static func codesignVerifiesDeep(_ bundle: URL) -> Bool {
        guard let (status, _, _) = try? runProcess("/usr/bin/codesign", [
            "--verify", "--deep", bundle.path(percentEncoded: false),
        ]) else { return false }
        return status == 0
    }

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
        let stdout = String(
            data: outPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: errPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
