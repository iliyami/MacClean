import Foundation
import MacCleanKit

/// Pure helpers turning Smart Scan's per-module results into the inputs
/// `CleanActions.executeUserClean` expects. SwiftUI-free for testing.
enum SmartScanCleanup {
    static func allResults(from modules: [ModuleScanResult]) -> [ScanResult] {
        modules.flatMap(\.categories).filter { !$0.items.isEmpty }
    }

    /// Pre-check every item in auto-select categories (mirrors per-module views).
    static func defaultSelection(from modules: [ModuleScanResult]) -> Set<URL> {
        var urls: Set<URL> = []
        for result in allResults(from: modules) where result.autoSelect {
            urls.formUnion(result.items.map(\.url))
        }
        return urls
    }
}
