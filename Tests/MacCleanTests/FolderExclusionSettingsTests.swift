import XCTest

final class FolderExclusionSettingsTests: XCTestCase {

    func testSettingsPageHasExcludedFoldersSection() throws {
        let src = try String(contentsOf: sourceURL("Sources/MacClean/Views/Settings/SettingsPageView.swift"), encoding: .utf8)
        XCTAssertTrue(src.contains("excludedFoldersSection"))
        XCTAssertTrue(src.contains("FolderExclusionPreferences"))
        XCTAssertTrue(
            src.contains("cannot be deleted") || src.contains("无法被"),
            "Copy must honestly say Mac Sai will not delete excluded folders"
        )
        XCTAssertFalse(
            src.contains("revoke"),
            "Do not overclaim capabilities"
        )
    }

    func testScanCoordinatorUsesActionableFilter() throws {
        let src = try String(contentsOf: sourceURL("Sources/MacClean/Core/Scanner/ScanCoordinator.swift"), encoding: .utf8)
        XCTAssertTrue(
            src.contains("CleanFilter.isActionable"),
            "Coordinator second pass must honor user exclusions"
        )
    }

    func testDuplicatesDisplayGroupsHonorExclusions() throws {
        let src = try String(contentsOf: sourceURL("Sources/MacClean/Modules/Duplicates/DuplicatesModule.swift"), encoding: .utf8)
        XCTAssertTrue(
            src.contains("CleanFilter.isActionable"),
            "Duplicates display groups must drop excluded copies"
        )
    }

    func testSafetyGuardDefinesUserExcluded() throws {
        let src = try String(contentsOf: sourceURL("Sources/MacCleanKit/SafetyGuard.swift"), encoding: .utf8)
        XCTAssertTrue(src.contains("case userExcluded"))
        XCTAssertTrue(src.contains("PathExclusion.isExcluded"))
    }

    private func sourceURL(_ relative: String) -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: relative)
    }
}
