import XCTest
@testable import MacClean
import MacCleanKit

final class AppPermissionsClientTests: XCTestCase {

    private final class Capture: @unchecked Sendable {
        var url: URL?
    }

    func testLoadMergesRowsFromBothDatabases() async {
        let user = [
            TCCAccessRow(service: "kTCCServiceCamera", client: "com.foo.cam", clientType: 0, authValue: 2, indirectObjectIdentifier: nil),
        ]
        let system = [
            TCCAccessRow(service: "kTCCServiceSystemPolicyAllFiles", client: "com.foo.fda", clientType: 0, authValue: 2, indirectObjectIdentifier: nil),
        ]
        let client = AppPermissionsClient(
            userDatabaseURL: URL(filePath: "/tmp/user-tcc.db"),
            systemDatabaseURL: URL(filePath: "/tmp/system-tcc.db"),
            readRows: { url in
                if url.path.hasSuffix("user-tcc.db") { return user }
                if url.path.hasSuffix("system-tcc.db") { return system }
                return []
            },
            openURL: { _ in }
        )
        let snapshot = await client.load()
        XCTAssertEqual(snapshot.listing, .loaded)
        XCTAssertEqual(Set(snapshot.grants.map(\.client)), ["com.foo.cam", "com.foo.fda"])
    }

    func testLoadMapsPermissionDeniedToNeedsFullDiskAccess() async {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM), userInfo: nil)
        let client = AppPermissionsClient(
            userDatabaseURL: URL(filePath: "/tmp/user-tcc.db"),
            systemDatabaseURL: URL(filePath: "/tmp/system-tcc.db"),
            readRows: { _ in throw posix },
            openURL: { _ in }
        )
        let snapshot = await client.load()
        XCTAssertEqual(snapshot.listing, .needsFullDiskAccess)
        XCTAssertTrue(snapshot.grants.isEmpty)
    }

    func testLoadMapsOtherErrorsToListingUnavailable() async {
        struct Boom: Error {}
        let client = AppPermissionsClient(
            userDatabaseURL: URL(filePath: "/tmp/user-tcc.db"),
            systemDatabaseURL: URL(filePath: "/tmp/system-tcc.db"),
            readRows: { _ in throw Boom() },
            openURL: { _ in }
        )
        let snapshot = await client.load()
        XCTAssertEqual(snapshot.listing, .unavailable)
        XCTAssertTrue(snapshot.grants.isEmpty)
    }

    func testLoadPartialReadStillLoaded() async {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM), userInfo: nil)
        let user = [
            TCCAccessRow(service: "kTCCServiceCamera", client: "com.foo.cam", clientType: 0, authValue: 2, indirectObjectIdentifier: nil),
        ]
        let client = AppPermissionsClient(
            userDatabaseURL: URL(filePath: "/tmp/user-tcc.db"),
            systemDatabaseURL: URL(filePath: "/tmp/system-tcc.db"),
            readRows: { url in
                if url.path.hasSuffix("user-tcc.db") { return user }
                throw posix
            },
            openURL: { _ in }
        )
        let snapshot = await client.load()
        XCTAssertEqual(snapshot.listing, .loaded)
        XCTAssertEqual(snapshot.grants.map(\.client), ["com.foo.cam"])
    }

    func testOpenSettingsUsesKitURL() async {
        let capture = Capture()
        let client = AppPermissionsClient(
            userDatabaseURL: URL(filePath: "/tmp/u"),
            systemDatabaseURL: URL(filePath: "/tmp/s"),
            readRows: { _ in [] },
            openURL: { capture.url = $0 }
        )
        client.openSettings(for: .camera)
        XCTAssertEqual(capture.url, AppPermissionsSettings.url(for: .camera))
    }
}
