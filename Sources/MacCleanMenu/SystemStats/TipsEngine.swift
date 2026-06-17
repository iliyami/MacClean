import Foundation
import AppKit
import MacCleanKit

/// Builds a short list of actionable suggestions for the popover.
/// Each tip has a stable id so the user can dismiss it for 30 days
/// (`SharedAppState.dismissTip`); the engine respects those dismissals.
///
/// MVP tips:
///   * `trash_large` — Trash > 1 GB
///   * `caches_large` — User caches > 2 GB
///
/// Future tips (separate phases): unused-apps, TM snapshot bloat,
/// outdated app updates.
public actor TipsEngine {
    public struct Tip: Sendable, Identifiable, Equatable {
        public let id: String
        public let title: String
        public let body: String
        /// Bytes the tip estimates the user could reclaim. Used for
        /// sorting (biggest payoff first) and the headline number.
        public let estimatedSavings: UInt64
        public let symbol: String

        public init(id: String, title: String, body: String, estimatedSavings: UInt64, symbol: String) {
            self.id = id
            self.title = title
            self.body = body
            self.estimatedSavings = estimatedSavings
            self.symbol = symbol
        }
    }

    public init() {}

    public func generateTips() async -> [Tip] {
        async let trash = trashTip()
        async let caches = cachesTip()

        var tips: [Tip] = []
        if let t = await trash { tips.append(t) }
        if let c = await caches { tips.append(c) }

        return tips
            .filter { !SharedAppState.isTipDismissed(id: $0.id) }
            .sorted { $0.estimatedSavings > $1.estimatedSavings }
    }

    private static let trashSizeMinimum: UInt64 = 1 * 1024 * 1024 * 1024  // 1 GB
    private static let cachesSizeMinimum: UInt64 = 2 * 1024 * 1024 * 1024 // 2 GB

    private func trashTip() async -> Tip? {
        let size = await directorySize(MCConstants.userTrash)
        guard size >= Self.trashSizeMinimum else { return nil }
        return Tip(
            id: "trash_large",
            title: L10n.tr("废纸篓占用了 \(FileSizeFormatter.format(size))", "Trash is taking \(FileSizeFormatter.format(size))"),
            body: L10n.tr("通过 \(MCConstants.appName) 清空废纸篓以释放空间。", "Empty the Trash from \(MCConstants.appName) to reclaim space."),
            estimatedSavings: size,
            symbol: "trash"
        )
    }

    private func cachesTip() async -> Tip? {
        let size = await directorySize(MCConstants.userCaches)
        guard size >= Self.cachesSizeMinimum else { return nil }
        return Tip(
            id: "caches_large",
            title: L10n.tr("用户缓存已增长到 \(FileSizeFormatter.format(size))", "User caches grew to \(FileSizeFormatter.format(size))"),
            body: L10n.tr("在 \(MCConstants.appName) 中运行“系统垃圾”以清理可再生成的缓存文件。", "Run System Junk in \(MCConstants.appName) to clear regenerable cache files."),
            estimatedSavings: size,
            symbol: "internaldrive"
        )
    }

    /// Lightweight directory size — single `du -sk` equivalent via
    /// FileManager. The user shouldn't pay a 30s scan for a tip; cap
    /// to a shallow walk and fall back to 0 on errors.
    private func directorySize(_ url: URL) async -> UInt64 {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        )
        var total: UInt64 = 0
        var sampled = 0
        let cap = 50_000  // hard cap so a runaway dir can't stall the popover
        while let next = enumerator?.nextObject() as? URL {
            sampled += 1
            if sampled > cap { break }
            if let values = try? next.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isDirectoryKey]),
               values.isDirectory == false,
               let size = values.totalFileAllocatedSize {
                total += UInt64(size)
            }
            // Yield occasionally so we don't hog the actor.
            if sampled % 5_000 == 0 { await Task.yield() }
        }
        return total
    }
}

/// Click-to-act on a tip. `open()` brings the main Mac Sai app to the
/// foreground; `open(moduleID:)` additionally deep-links straight to the
/// relevant module via the `macclean://module/<id>` URL scheme.
public enum TipAction {
    @MainActor
    public static func open() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MCConstants.bundleIdentifier) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}

public extension TipAction {
    /// Foreground the main app and deep-link to a specific module via the
    /// `macclean://module/<id>` URL scheme. Falls back to plainly opening
    /// the app when no module id is available.
    @MainActor
    static func open(moduleID: String?) {
        guard let moduleID, let url = URL(string: "macclean://module/\(moduleID)") else {
            open()   // fallback: just foreground the app
            return
        }
        NSWorkspace.shared.open(url)
    }
}
