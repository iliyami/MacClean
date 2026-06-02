import XCTest
@testable import MacCleanKit

final class SafetyGuardProtectedAppTests: XCTestCase {
    func testCriticalAppleAppsAreProtected() {
        let g = SafetyGuard()
        for id in ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Terminal"] {
            XCTAssertTrue(g.isProtectedApp(id), "\(id) must be protected")
        }
    }
    func testNonCriticalAppleAppsAreRemovable() {
        let g = SafetyGuard()
        XCTAssertFalse(g.isProtectedApp("com.apple.garageband"))
        XCTAssertFalse(g.isProtectedApp("com.apple.iMovie"))
    }
    func testThirdPartyAppsAreRemovable() {
        XCTAssertFalse(SafetyGuard().isProtectedApp("com.tinyspeck.slackmacgap"))
    }
}
