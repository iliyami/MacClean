import Foundation
import MacCleanKit

public struct PrivacyModule: ScanModule {
    public let id = "privacy"
    public var name: String { L10n.tr("隐私清理", "Privacy") }
    public let category = ModuleCategory.protection

    public enum TimeFilter: Sendable {
        case today
        case lastWeek
        case lastMonth
        case lastYear
        case allTime

        var maxAge: TimeInterval? {
            switch self {
            case .today: 24 * 3600
            case .lastWeek: 7 * 24 * 3600
            case .lastMonth: 30 * 24 * 3600
            case .lastYear: 365 * 24 * 3600
            case .allTime: nil
            }
        }
    }

    private let scanner = TargetedScanner()
    private let timeFilter: TimeFilter

    public init(timeFilter: TimeFilter = .allTime) {
        self.timeFilter = timeFilter
    }

    public func scan() async -> [ScanResult] {
        async let browserItems = scanBrowserData()
        async let systemItems = scanSystemPrivacy()

        let browser = await browserItems
        let system = await systemItems

        var results: [ScanResult] = []
        if !browser.isEmpty {
            results.append(ScanResult(category: .browserPrivacy, items: browser))
        }
        if !system.isEmpty {
            results.append(ScanResult(category: .systemPrivacy, items: system))
        }
        return results.filteringUncleanable()
    }

    private func scanBrowserData() async -> [FileItem] {
        let targets = [
            // Safari
            ScanTarget(
                path: MCConstants.safariCache,
                recursive: true,
                maxAge: timeFilter.maxAge
            ),
            ScanTarget(
                path: MCConstants.userLibrary.appending(path: "Safari"),
                recursive: false,
                fileExtensions: ["db", "plist"],
                maxAge: timeFilter.maxAge
            ),
            // Chrome
            ScanTarget(
                path: MCConstants.chromeCache,
                recursive: true,
                maxAge: timeFilter.maxAge
            ),
            ScanTarget(
                path: MCConstants.chromeDefault.appending(path: "Cache"),
                recursive: true,
                maxAge: timeFilter.maxAge
            ),
            ScanTarget(
                path: MCConstants.chromeDefault.appending(path: "Code Cache"),
                recursive: true,
                maxAge: timeFilter.maxAge
            ),
            // Firefox
            ScanTarget(
                path: MCConstants.firefoxCache,
                recursive: true,
                maxAge: timeFilter.maxAge
            ),
        ]
        return await scanner.scan(targets: targets)
    }

    private func scanSystemPrivacy() async -> [FileItem] {
        let targets = [
            // Recent items database
            ScanTarget(
                path: MCConstants.userLibrary.appending(path: "Application Support/com.apple.sharedfilelist"),
                recursive: true,
                fileExtensions: ["sfl2", "sfl3"],
                maxAge: timeFilter.maxAge
            ),
            // Recent documents
            ScanTarget(
                path: MCConstants.userLibrary.appending(path: "RecentServers"),
                recursive: false,
                maxAge: timeFilter.maxAge
            ),
        ]
        return await scanner.scan(targets: targets)
    }
}
