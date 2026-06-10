import XCTest
@testable import MacClean

final class UpdaterSecurityTests: XCTestCase {
    func testFeedURLMustBeHTTPS() {
        XCTAssertTrue(UpdaterActions.isAcceptableFeedURL(URL(string: "https://example.com/appcast.xml")!))
        XCTAssertFalse(UpdaterActions.isAcceptableFeedURL(URL(string: "http://example.com/appcast.xml")!))
        XCTAssertFalse(UpdaterActions.isAcceptableFeedURL(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(UpdaterActions.isAcceptableFeedURL(URL(string: "ftp://example.com/x")!))
    }

    func testDownloadURLMustBeHTTPS() {
        XCTAssertTrue(UpdaterActions.isSafeDownloadURL(URL(string: "https://example.com/app.dmg")!))
        XCTAssertFalse(UpdaterActions.isSafeDownloadURL(URL(string: "http://example.com/app.dmg")!))
        XCTAssertFalse(UpdaterActions.isSafeDownloadURL(URL(string: "file:///Applications/Evil.app")!))
    }
}
