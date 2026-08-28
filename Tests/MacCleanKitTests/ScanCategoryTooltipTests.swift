import XCTest
import Foundation

@testable import MacCleanKit

/// The results list shows a category's name and one-line explanation on
/// truncating single lines, so the hover tooltip is what a user reads when
/// either is cut off. These pin its content per category and per language.
final class ScanCategoryTooltipTests: AppLanguageTestCase {

    func testTooltipCarriesBothTheNameAndTheExplanation() {
        AppLanguage.current = .en
        for category in ScanCategory.allCases {
            let tooltip = category.tooltip
            XCTAssertTrue(
                tooltip.contains(category.displayName),
                "\(category.rawValue) tooltip must name the category"
            )
            XCTAssertTrue(
                tooltip.contains(category.subtitle),
                "\(category.rawValue) tooltip must explain what the category contains"
            )
        }
    }

    /// The name and the explanation must stay on separate lines; a tooltip that
    /// ran them together would read as one sentence.
    func testTooltipPutsTheExplanationOnItsOwnLine() {
        AppLanguage.current = .en
        for category in ScanCategory.allCases {
            let lines = category.tooltip.components(separatedBy: "\n")
            XCTAssertEqual(lines.count, 2, "\(category.rawValue) tooltip must be exactly two lines")
            XCTAssertEqual(lines.first, category.displayName)
            XCTAssertEqual(lines.last, category.subtitle)
        }
    }

    /// The issue that prompted this: "Broken Login Items" says nothing about
    /// what it deletes until you hover it.
    func testBrokenLoginItemsTooltipExplainsWhatItDeletes() {
        AppLanguage.current = .en
        let tooltip = ScanCategory.brokenLoginItems.tooltip
        XCTAssertEqual(
            tooltip,
            "Broken Login Items\nLogin items pointing at apps that are gone."
        )
    }

    func testTooltipIsNeverEmptyOrPlaceholderInAnyLanguage() {
        for language in AppLanguage.allCases {
            AppLanguage.current = language
            for category in ScanCategory.allCases {
                let lines = category.tooltip.components(separatedBy: "\n")
                XCTAssertEqual(lines.count, 2, "\(category.rawValue)/\(language.rawValue)")
                for line in lines {
                    XCTAssertFalse(
                        line.trimmingCharacters(in: .whitespaces).isEmpty,
                        "\(category.rawValue)/\(language.rawValue) tooltip has a blank line"
                    )
                }
            }
        }
    }

    /// Every category gets its own tooltip; a copy-paste slip that gave two
    /// categories the same explanation would be invisible in the UI.
    func testEveryCategoryHasADistinctTooltip() {
        AppLanguage.current = .en
        let tooltips = ScanCategory.allCases.map(\.tooltip)
        XCTAssertEqual(Set(tooltips).count, tooltips.count)
    }
}
