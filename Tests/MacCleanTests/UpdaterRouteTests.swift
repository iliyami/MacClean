import XCTest
import Foundation
@testable import MacClean

final class UpdaterRouteTests: XCTestCase {
    let dmg = URL(string: "https://example.com/App-4.3.dmg")!
    let appPath = URL(filePath: "/Applications/App.app")

    func testMacAppStoreAppRoutesToAppStore() {
        XCTAssertEqual(UpdaterActions.route(isMacAppStore: true, downloadURL: dmg, appPath: appPath), .appStore)
    }
    func testSparkleAppWithURLRoutesToDownload() {
        XCTAssertEqual(UpdaterActions.route(isMacAppStore: false, downloadURL: dmg, appPath: appPath), .download(dmg))
    }
    func testNoURLFallsBackToLaunchingTheApp() {
        XCTAssertEqual(UpdaterActions.route(isMacAppStore: false, downloadURL: nil, appPath: appPath), .launchApp(appPath))
    }

    // MARK: - hasUpdate (regression for #105: no downgrade offers)

    func testOffersOnlyGenuinelyNewerVersions() {
        XCTAssertTrue(UpdaterActions.hasUpdate(current: "3.6.8", available: "3.7.0"))
        XCTAssertTrue(UpdaterActions.hasUpdate(current: "1.163.1", available: "1.164.0"))
    }

    func testDoesNotOfferDowngrades() {
        // The exact cases from issue #105.
        XCTAssertFalse(UpdaterActions.hasUpdate(current: "3.6.8", available: "3.4"))
        XCTAssertFalse(UpdaterActions.hasUpdate(current: "1.163.1", available: "1.154.0"))
        XCTAssertFalse(UpdaterActions.hasUpdate(current: "4.8.8", available: "3.7.1"))
        XCTAssertFalse(UpdaterActions.hasUpdate(current: "4.2.18", available: "1.2.7"))
    }

    func testDoesNotOfferSameVersionOrMissing() {
        XCTAssertFalse(UpdaterActions.hasUpdate(current: "3.6.8", available: "3.6.8"))
        XCTAssertFalse(UpdaterActions.hasUpdate(current: "3.6.8", available: nil))
    }
}
