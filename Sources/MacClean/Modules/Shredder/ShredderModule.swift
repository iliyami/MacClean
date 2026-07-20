import Foundation
import MacCleanKit

public struct ShredderModule: ScanModule {
    public let id = "shredder"
    public var name: String { L10n.tr("文件粉碎", "Shredder", "Уничтожение файлов") }
    public let category = ModuleCategory.files
    public let includedInSmartScan = false

    public init() {}

    public func scan() async -> [ScanResult] {
        []
    }
}

// MARK: - Secure File Eraser

public actor SecureEraser {
    public enum EraseMode: Sendable {
        case standard   // Move to trash (recoverable)
        case permanent  // Remove immediately (TRIM handles SSD cleanup)
        case secure     // Overwrite then remove (best effort on SSD)
    }

    public struct EraseResult: Sendable {
        public let erasedCount: Int
        public let totalSize: UInt64
        public let errors: [(String, String)]
    }

    private let safetyGuard = SafetyGuard()

    public init() {}

    public func erase(urls: [URL], mode: EraseMode) async -> EraseResult {
        do {
            try safetyGuard.validateDeletion(paths: urls)
        } catch {
            return EraseResult(
                erasedCount: 0,
                totalSize: 0,
                errors: [("validation", error.localizedDescription)]
            )
        }

        var erasedCount = 0
        var totalSize: UInt64 = 0
        var errors: [(String, String)] = []

        for url in urls {
            if Task.isCancelled { break }

            do {
                try safetyGuard.validatePath(url)
            } catch {
                errors.append((url.path(percentEncoded: false), error.localizedDescription))
                continue
            }

            let size = fileSize(url)

            do {
                switch mode {
                case .standard:
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)

                case .permanent:
                    try FileManager.default.removeItem(at: url)

                case .secure:
                    try secureOverwrite(url)
                    try FileManager.default.removeItem(at: url)
                }

                erasedCount += 1
                totalSize += size
            } catch {
                errors.append((url.path(percentEncoded: false), error.localizedDescription))
            }
        }

        return EraseResult(erasedCount: erasedCount, totalSize: totalSize, errors: errors)
    }

    private func secureOverwrite(_ url: URL) throws {
        // On SSDs, TRIM handles physical block zeroing automatically after deletion.
        // This overwrite is best-effort: it writes over the logical file content,
        // but the SSD controller may redirect the write to a new physical block.
        // For true security, recommend FileVault (full-disk encryption).
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey])
        // Nothing to overwrite for a directory or an empty file: a legitimate
        // no-op (the caller still trashes/removes them). These must NOT throw.
        guard values.isDirectory != true else { return }
        // Never follow a symlink: opening it for writing would zero the TARGET
        // file's contents, not the link. Refuse rather than corrupt the target.
        guard values.isSymbolicLink != true else {
            throw SafetyGuard.SafetyError.symlinkTarget(url.path(percentEncoded: false))
        }
        let size = values.fileSize ?? 0
        guard size > 0 else { return }

        // Propagate an open failure instead of silently returning: a file we
        // couldn't overwrite must NOT be deleted and reported as a successful
        // secure erase (e.g. a read-only file in a writable directory).
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        // Single pass of zeros
        let bufferSize = min(size, 65536)
        let zeros = Data(count: bufferSize)
        var remaining = size

        handle.seek(toFileOffset: 0)
        while remaining > 0 {
            let writeSize = min(remaining, bufferSize)
            handle.write(zeros.prefix(writeSize))
            remaining -= writeSize
        }

        handle.truncateFile(atOffset: 0)
    }

    private func fileSize(_ url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return UInt64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }
}
