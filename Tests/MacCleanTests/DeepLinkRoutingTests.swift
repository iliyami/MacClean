import XCTest
@testable import MacClean

final class DeepLinkRoutingTests: XCTestCase {
    func testDeepLinkIDRoundTrips() {
        XCTAssertEqual(SidebarItem.systemJunk.deepLinkID, "system-junk")
        XCTAssertEqual(SidebarItem(deepLinkID: "system-junk"), .systemJunk)
        XCTAssertEqual(SidebarItem(deepLinkID: "trash-bins"), .trashBins)
        XCTAssertNil(SidebarItem(deepLinkID: "nonsense"))
    }
}
