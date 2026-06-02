import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit
import MacCleanTestSupport

final class LaunchAgentsManagerTests: XCTestCase {
    func testToggleFlipsDisabledKeyInPlist() async throws {
        try await TestFixtures.withTempDir { dir in
            let plistURL = dir.appending(path: "com.example.zoom.plist")
            let plist: [String: Any] = ["Label": "com.example.zoom", "Disabled": false]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)

            let agent = LaunchAgentsManager.LaunchAgent(
                label: "com.example.zoom", path: plistURL,
                program: "/Applications/zoom.us.app", isSystem: false, isEnabled: true
            )
            let mgr = LaunchAgentsManager()
            try mgr.toggleAgent(agent, enabled: false)

            let after = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
            XCTAssertEqual(after["Disabled"] as? Bool, true)
        }
    }

    func testToggleRefusesSystemAgents() {
        let agent = LaunchAgentsManager.LaunchAgent(
            label: "com.apple.x", path: URL(filePath: "/Library/LaunchAgents/com.apple.x.plist"),
            program: nil, isSystem: true, isEnabled: true
        )
        XCTAssertThrowsError(try LaunchAgentsManager().toggleAgent(agent, enabled: false))
    }
}
