import XCTest
@testable import MacClean
import MacCleanKit

final class FileListExpansionTests: XCTestCase {

    // MARK: - Default state

    func testCategoriesAreExpandedByDefault() {
        let expansion = FileListExpansion()
        XCTAssertTrue(expansion.isExpanded(.userCaches))
        XCTAssertTrue(expansion.isExpanded(.trashBins))
        XCTAssertTrue(expansion.isExpanded(.userLogs))
    }

    func testEveryCaseExpandedByDefault() {
        let expansion = FileListExpansion()
        for category in ScanCategory.allCases {
            XCTAssertTrue(expansion.isExpanded(category),
                          "\(category) should be expanded by default")
        }
    }

    // MARK: - Toggle

    func testToggleCollapsesThenReExpands() {
        var expansion = FileListExpansion()

        expansion.toggle(.userCaches)
        XCTAssertFalse(expansion.isExpanded(.userCaches), "toggle should collapse")

        expansion.toggle(.userCaches)
        XCTAssertTrue(expansion.isExpanded(.userCaches), "second toggle should re-expand")
    }

    func testToggleIsIdempotentRoundTrip() {
        var expansion = FileListExpansion()
        // Two full round-trips must return to the default (expanded) state.
        for _ in 0..<2 {
            expansion.toggle(.userLogs)
            expansion.toggle(.userLogs)
        }
        XCTAssertTrue(expansion.isExpanded(.userLogs))
    }

    func testOddNumberOfTogglesLeavesCollapsed() {
        var expansion = FileListExpansion()
        expansion.toggle(.trashBins)
        expansion.toggle(.trashBins)
        expansion.toggle(.trashBins)
        XCTAssertFalse(expansion.isExpanded(.trashBins))
    }

    // MARK: - Per-category isolation

    func testCollapseIsPerCategory() {
        var expansion = FileListExpansion()
        expansion.toggle(.userCaches)

        XCTAssertFalse(expansion.isExpanded(.userCaches),
                       "collapsed category should report collapsed")
        XCTAssertTrue(expansion.isExpanded(.trashBins),
                      "untouched category should stay expanded")
        XCTAssertTrue(expansion.isExpanded(.userLogs),
                      "untouched category should stay expanded")
    }

    func testReExpandingOneLeavesAnotherCollapsed() {
        var expansion = FileListExpansion()
        expansion.toggle(.userCaches)
        expansion.toggle(.userLogs)
        // Re-expand only userCaches.
        expansion.toggle(.userCaches)

        XCTAssertTrue(expansion.isExpanded(.userCaches))
        XCTAssertFalse(expansion.isExpanded(.userLogs),
                       "userLogs should remain collapsed")
    }

    // MARK: - collapseAll / expandAll

    func testCollapseAllCollapsesGivenCategories() {
        var expansion = FileListExpansion()
        let cats: [ScanCategory] = [.userCaches, .trashBins, .userLogs]
        expansion.collapseAll(cats)

        for c in cats {
            XCTAssertFalse(expansion.isExpanded(c), "\(c) should be collapsed")
        }
    }

    func testCollapseAllLeavesUnlistedCategoriesExpanded() {
        var expansion = FileListExpansion()
        expansion.collapseAll([.userCaches, .userLogs])
        // A category not in the list stays expanded.
        XCTAssertTrue(expansion.isExpanded(.trashBins))
    }

    func testCollapseAllOnEmptyListIsNoOp() {
        var expansion = FileListExpansion()
        expansion.collapseAll([])
        XCTAssertTrue(expansion.isExpanded(.userCaches))
    }

    func testCollapseAllIsIdempotent() {
        var expansion = FileListExpansion()
        expansion.collapseAll([.userCaches])
        expansion.collapseAll([.userCaches])
        XCTAssertFalse(expansion.isExpanded(.userCaches))
        // Re-expanding once should fully expand (no duplicate state lingers).
        expansion.toggle(.userCaches)
        XCTAssertTrue(expansion.isExpanded(.userCaches))
    }

    func testExpandAllReExpandsEverything() {
        var expansion = FileListExpansion()
        expansion.collapseAll(ScanCategory.allCases)
        for c in ScanCategory.allCases {
            XCTAssertFalse(expansion.isExpanded(c))
        }

        expansion.expandAll()
        for c in ScanCategory.allCases {
            XCTAssertTrue(expansion.isExpanded(c), "\(c) should be expanded after expandAll")
        }
    }

    func testExpandAllOnFreshStateIsNoOp() {
        var expansion = FileListExpansion()
        expansion.expandAll()
        XCTAssertTrue(expansion.isExpanded(.userCaches))
    }
}
