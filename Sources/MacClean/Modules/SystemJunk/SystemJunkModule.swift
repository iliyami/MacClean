import Foundation
import AppKit
import MacCleanKit

public struct SystemJunkModule: ScanModule {
    public let id = "system_junk"
    public var name: String { L10n.tr("系统垃圾", "System Junk") }
    public let category = ModuleCategory.cleanup

    private let scanner = TargetedScanner()

    public init() {}

    /// All categories the System Junk module runs. The pure target / filter
    /// declarations live in MacCleanKit and are tested there; this list is
    /// the only place the *full set* is composed.
    public static let allCategories: [JunkCategory] = [
        UserCacheCategory(),
        SystemCacheCategory(),
        UserLogCategory(),
        SystemLogCategory(),
        LanguageFilesCategory(),
        BrokenPreferencesCategory(),
        BrokenLoginItemsCategory(),
        DocumentVersionsCategory(),
        BrokenDownloadsCategory(),
        IOSDeviceBackupsCategory(),
        OldUpdatesCategory(),
        UniversalBinariesCategory(),
        XcodeJunkCategory(),
        DeletedUsersCategory(),
        UnusedDiskImagesCategory(),
        IncompleteDownloadsCategory(),
        AppLeftoversCategory(),
    ]

    public func scan() async -> [ScanResult] {
        let categories = Self.allCategories

        return await withTaskGroup(of: ScanResult?.self) { group in
            for cat in categories {
                group.addTask {
                    // UniversalBinaries needs a system-side scanner (walks
                    // .app bundles, shells out to lipo, asks the policy)
                    // rather than the targeted path enumerator.
                    if cat.scanCategory == .universalBinaries {
                        let items = UniversalBinariesScanner.scan()
                        guard !items.isEmpty else { return nil }
                        return ScanResult(
                            category: .universalBinaries,
                            items: items,
                            autoSelect: cat.scanCategory.autoSelect
                        )
                    }
                    // App leftovers: enumerates the safe Library subdirs for
                    // bundle-id-named entries whose owning app is uninstalled.
                    if cat.scanCategory == .appLeftovers {
                        let items = AppLeftoversScanner.scan()
                        guard !items.isEmpty else { return nil }
                        return ScanResult(
                            category: .appLeftovers,
                            items: items,
                            autoSelect: cat.scanCategory.autoSelect
                        )
                    }
                    let items = await scanner.scan(targets: cat.targets)
                    var filtered = items

                    // Apply category-specific post-filter logic.
                    if let brokenPrefs = cat as? BrokenPreferencesCategory {
                        filtered = brokenPrefs.filterBroken(
                            items,
                            loadData: { try? Data(contentsOf: $0) },
                            appExistsForBundleID: {
                                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
                            }
                        )
                    } else if let brokenLogin = cat as? BrokenLoginItemsCategory {
                        filtered = brokenLogin.filterBroken(
                            items,
                            loadData: { try? Data(contentsOf: $0) },
                            fileExists: { FileManager.default.fileExists(atPath: $0) },
                            appExistsForBundleID: {
                                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
                            }
                        )
                    }

                    guard !filtered.isEmpty else { return nil }
                    return ScanResult(
                        category: cat.scanCategory,
                        items: filtered,
                        autoSelect: cat.scanCategory.autoSelect
                    )
                }
            }

            var results: [ScanResult] = []
            for await result in group {
                if let result {
                    results.append(result)
                }
            }
            return results
                .filteringUncleanable()
                .sorted { $0.totalSize > $1.totalSize }
        }
    }
}
