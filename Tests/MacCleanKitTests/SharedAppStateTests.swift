import XCTest
@testable import MacCleanKit

final class SharedAppStateTests: AppLanguageTestCase {

    func testProtectionStatusFreshIsNotStale() {
        let p = SharedAppState.ProtectionStatus(
            lastScanDate: Date(),
            threatsFound: 0,
            scanDepth: "balanced"
        )
        XCTAssertFalse(p.isStale, "A scan that just happened shouldn't be stale")
    }

    func testProtectionStatusOneWeekOldIsStale() {
        let p = SharedAppState.ProtectionStatus(
            lastScanDate: Date().addingTimeInterval(-8 * 24 * 3600),
            threatsFound: 0,
            scanDepth: "balanced"
        )
        XCTAssertTrue(p.isStale, "A scan from 8 days ago crosses the 7-day staleness threshold")
    }

    func testProtectionStatusBoundaryNotStale() {
        // Exactly the 7-day window edge — should not flip to stale yet.
        // We subtract slightly less than 7 days to be safe against
        // timing flake.
        let p = SharedAppState.ProtectionStatus(
            lastScanDate: Date().addingTimeInterval(-6 * 24 * 3600 - 23 * 3600),
            threatsFound: 0,
            scanDepth: "balanced"
        )
        XCTAssertFalse(p.isStale)
    }

    func testProtectionStatusIsCodable() throws {
        let original = SharedAppState.ProtectionStatus(
            lastScanDate: Date(timeIntervalSince1970: 1_700_000_000),
            threatsFound: 5,
            scanDepth: "deep"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SharedAppState.ProtectionStatus.self, from: data)
        XCTAssertEqual(decoded, original)
    }
    func testProtectionStatusLocalizesStableAndLegacyDepthValues() {
        let values = ["quick", "Quick", "快速"]

        AppLanguage.current = .ru
        for value in values {
            let status = SharedAppState.ProtectionStatus(
                lastScanDate: Date(),
                threatsFound: 0,
                scanDepth: value
            )
            XCTAssertEqual(status.localizedScanDepth, "Быстро")
        }
    }

}
