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
}
