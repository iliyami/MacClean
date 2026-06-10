import XCTest
import Foundation
@testable import MacClean
import MacCleanKit

/// Smoke tests for every scan module: protocol conformance, metadata,
/// expected category, expected smart-scan inclusion.
final class ModuleMetadataTests: XCTestCase {

    private let allModules: [ScanModule] = [
        SystemJunkModule(),
        MailAttachmentsModule(),
        TrashBinsModule(),
        MalwareModule(),
        PrivacyModule(),
        OptimizationModule(),
        MaintenanceModule(),
        UninstallerModule(),
        UpdaterModule(),
        SpaceLensModule(),
        LargeOldFilesModule(),
        DuplicatesModule(),
        ShredderModule(),
    ]

    func testAllModulesHaveDistinctIDs() {
        let ids = allModules.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Every module needs a unique id")
    }

    func testAllModulesHaveDistinctNames() {
        let names = allModules.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "Every module needs a unique display name")
    }

    func testAllModulesDeclareCategory() {
        for m in allModules {
            XCTAssertFalse(m.id.isEmpty, "module \(type(of: m)) missing id")
            XCTAssertFalse(m.name.isEmpty, "module \(type(of: m)) missing name")
        }
    }

    func testHeavyModulesExcludedFromSmartScan() {
        let m = Dictionary(uniqueKeysWithValues: allModules.map { ($0.id, $0.includedInSmartScan) })
        // These three are intentionally opt-in (slow / interactive).
        XCTAssertEqual(m["duplicates"], false)
        XCTAssertEqual(m["space_lens"], false)
        XCTAssertEqual(m["shredder"], false)
        // Large & Old Files must NOT feed the Smart Scan "junk found" total:
        // big media (music, videos, project files) is not junk. It stays
        // discoverable in its own dedicated section, which scans on its own.
        XCTAssertEqual(m["large_old_files"], false)
    }

    func testCleanupCategoryModules() {
        let cleanup = allModules.filter { $0.category == .cleanup }
        let ids = Set(cleanup.map(\.id))
        XCTAssertTrue(ids.contains("system_junk"))
        XCTAssertTrue(ids.contains("mail_attachments"))
        XCTAssertTrue(ids.contains("trash_bins"))
    }

    func testProtectionCategoryModules() {
        let protection = allModules.filter { $0.category == .protection }
        XCTAssertTrue(protection.contains { $0.id == "malware" })
        XCTAssertTrue(protection.contains { $0.id == "privacy" })
    }

    func testPerformanceCategoryModules() {
        let performance = allModules.filter { $0.category == .performance }
        XCTAssertTrue(performance.contains { $0.id == "optimization" })
        XCTAssertTrue(performance.contains { $0.id == "maintenance" })
    }

    func testApplicationsCategoryModules() {
        let apps = allModules.filter { $0.category == .applications }
        XCTAssertTrue(apps.contains { $0.id == "uninstaller" })
        XCTAssertTrue(apps.contains { $0.id == "updater" })
    }

    func testFilesCategoryModules() {
        let files = allModules.filter { $0.category == .files }
        XCTAssertTrue(files.contains { $0.id == "space_lens" })
        XCTAssertTrue(files.contains { $0.id == "large_old_files" })
        XCTAssertTrue(files.contains { $0.id == "duplicates" })
        XCTAssertTrue(files.contains { $0.id == "shredder" })
    }
}
