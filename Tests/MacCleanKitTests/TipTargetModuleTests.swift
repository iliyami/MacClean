import XCTest
@testable import MacCleanKit

final class TipTargetModuleTests: XCTestCase {
    func testTipMapsToModule() {
        XCTAssertEqual(MenuTipRouting.moduleID(forTipID: "trash_large"), "trash-bins")
        XCTAssertEqual(MenuTipRouting.moduleID(forTipID: "caches_large"), "system-junk")
        XCTAssertNil(MenuTipRouting.moduleID(forTipID: "unknown"))
    }
}
