import XCTest
import Foundation
@testable import MacClean

final class SpaceLensNavigationTests: XCTestCase {
    let home = URL(filePath: "/Users/me")
    let caches = URL(filePath: "/Users/me/Library/Caches")
    let library = URL(filePath: "/Users/me/Library")

    func testDrillAppendsCrumb() {
        var nav = SpaceLensNavigation(root: home)
        nav.drillInto(library); nav.drillInto(caches)
        XCTAssertEqual(nav.current, caches)
        XCTAssertEqual(nav.breadcrumbs, [home, library, caches])
    }
    func testUpPopsOneLevel() {
        var nav = SpaceLensNavigation(root: home)
        nav.drillInto(library); nav.drillInto(caches)
        nav.up()
        XCTAssertEqual(nav.current, library)
        XCTAssertEqual(nav.breadcrumbs, [home, library])
    }
    func testUpAtRootIsNoOp() {
        var nav = SpaceLensNavigation(root: home)
        nav.up()
        XCTAssertEqual(nav.current, home)
        XCTAssertEqual(nav.breadcrumbs, [home])
    }
    func testHomeResetsToRoot() {
        var nav = SpaceLensNavigation(root: home)
        nav.drillInto(library); nav.drillInto(caches)
        nav.home()
        XCTAssertEqual(nav.current, home)
        XCTAssertEqual(nav.breadcrumbs, [home])
    }
    func testNavigateToCrumbTruncates() {
        var nav = SpaceLensNavigation(root: home)
        nav.drillInto(library); nav.drillInto(caches)
        nav.navigate(to: library)
        XCTAssertEqual(nav.current, library)
        XCTAssertEqual(nav.breadcrumbs, [home, library])
    }
}
