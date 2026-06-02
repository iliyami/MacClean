import XCTest
import Foundation

/// Guard against shipping a `Button("Label") {}` whose action is empty —
/// the exact class of bug behind issues #32 (Updater) and #33 (Uninstaller),
/// where a button rendered fine but did nothing. Mirrors the approach of
/// `CleanIsNotDryRunRegressionTests`: scan the view source, fail on offenders.
final class NoEmptyButtonActionsTests: XCTestCase {

    func testNoViewHasAnEmptyButtonAction() throws {
        let viewsDir = URL(filePath: #filePath)
            .deletingLastPathComponent()   // Tests/MacCleanTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appending(path: "Sources/MacClean/Views")

        // Matches `Button(...) {}` and `Button(...) { }` (empty trailing
        // closure) but NOT `Button(..., role: .cancel) { }` which is a
        // legitimate no-op dismiss inside an .alert.
        let emptyAction = #"Button\((?!.*role:\s*\.cancel)[^)]*\)\s*\{\s*\}"#

        var offenders: [String] = []
        let enumerator = FileManager.default.enumerator(at: viewsDir, includingPropertiesForKeys: nil)!
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if src.range(of: emptyAction, options: .regularExpression) != nil {
                offenders.append(url.lastPathComponent)
            }
        }

        XCTAssertTrue(offenders.isEmpty,
            "These views have a Button with an empty action — it looks live but does nothing: \(offenders)")
    }
}
