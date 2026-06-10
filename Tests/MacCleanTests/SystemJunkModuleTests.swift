import XCTest
import Foundation
@testable import MacClean
import MacCleanKit

final class SystemJunkModuleTests: XCTestCase {

    func testRegistersAll17Categories() {
        XCTAssertEqual(SystemJunkModule.allCategories.count, 17)
    }

    func testAllCategoriesAreUnique() {
        let scanCategories = SystemJunkModule.allCategories.map { $0.scanCategory }
        XCTAssertEqual(Set(scanCategories).count, scanCategories.count,
                       "Every category must declare a distinct ScanCategory")
    }

    func testModuleMetadata() {
        let m = SystemJunkModule()
        XCTAssertEqual(m.id, "system_junk")
        XCTAssertEqual(m.name, "System Junk")
        XCTAssertEqual(m.category, .cleanup)
        XCTAssertTrue(m.includedInSmartScan)
    }
}
