import XCTest
@testable import MacCleanKit

final class AppPermissionsTests: XCTestCase {

    func testSettingsURLsMatchPermissionManagerScheme() {
        XCTAssertEqual(
            AppPermissionsSettings.url(for: .fullDiskAccess).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )
        XCTAssertEqual(
            AppPermissionsSettings.url(for: .camera).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        )
        XCTAssertEqual(
            AppPermissionsSettings.url(for: .microphone).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
        XCTAssertEqual(
            AppPermissionsSettings.url(for: .screenRecording).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
        XCTAssertEqual(
            AppPermissionsSettings.url(for: .automation).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )
    }

    func testParserKeepsAllowedAndLimitedDropsDeniedAndUnknown() {
        let rows = [
            TCCAccessRow(service: "kTCCServiceCamera", client: "com.foo.cam", clientType: 0, authValue: 2, indirectObjectIdentifier: nil),
            TCCAccessRow(service: "kTCCServiceCamera", client: "com.foo.denied", clientType: 0, authValue: 0, indirectObjectIdentifier: nil),
            TCCAccessRow(service: "kTCCServiceMicrophone", client: "com.foo.limited", clientType: 0, authValue: 3, indirectObjectIdentifier: nil),
            TCCAccessRow(service: "kTCCServiceBogus", client: "com.foo.x", clientType: 0, authValue: 2, indirectObjectIdentifier: nil),
        ]
        let grants = TCCAccessParser.grants(from: rows)
        XCTAssertEqual(grants.map(\.client), ["com.foo.cam", "com.foo.limited"])
        XCTAssertEqual(grants[0].permission, .camera)
        XCTAssertFalse(grants[0].isLimited)
        XCTAssertEqual(grants[1].permission, .microphone)
        XCTAssertTrue(grants[1].isLimited)
        XCTAssertFalse(grants[0].clientIsPath)
    }

    func testParserPathClientAndAutomationTarget() {
        let rows = [
            TCCAccessRow(service: "kTCCServiceSystemPolicyAllFiles", client: "/usr/bin/rsync", clientType: 1, authValue: 2, indirectObjectIdentifier: nil),
            TCCAccessRow(service: "kTCCServiceAppleEvents", client: "com.foo.script", clientType: 0, authValue: 2, indirectObjectIdentifier: "com.apple.finder"),
        ]
        let grants = TCCAccessParser.grants(from: rows)
        XCTAssertEqual(grants.count, 2)
        XCTAssertEqual(grants[0].permission, .fullDiskAccess)
        XCTAssertTrue(grants[0].clientIsPath)
        XCTAssertEqual(grants[1].permission, .automation)
        XCTAssertEqual(grants[1].indirectObjectIdentifier, "com.apple.finder")
    }

    func testParserIgnoresSentinelIndirectObjectOnAutomation() {
        let row = TCCAccessRow(
            service: "kTCCServiceAppleEvents",
            client: "com.foo.script",
            clientType: 0,
            authValue: 2,
            indirectObjectIdentifier: "UNUSED"
        )
        let grants = TCCAccessParser.grants(from: [row])
        XCTAssertEqual(grants.count, 1)
        XCTAssertNil(grants[0].indirectObjectIdentifier)
    }

    func testParserEmpty() {
        XCTAssertTrue(TCCAccessParser.grants(from: []).isEmpty)
    }

    func testParserDedupesIdenticalGrants() {
        let row = TCCAccessRow(service: "kTCCServiceCamera", client: "com.foo.cam", clientType: 0, authValue: 2, indirectObjectIdentifier: nil)
        let grants = TCCAccessParser.grants(from: [row, row])
        XCTAssertEqual(grants.count, 1)
    }

    func testOverviewGroupsGrantsByAppAndSortsPermissions() {
        let grants = [
            AppPermissionGrant(permission: .microphone, client: "com.z.last", clientIsPath: false, isLimited: false, indirectObjectIdentifier: nil),
            AppPermissionGrant(permission: .camera, client: "com.a.first", clientIsPath: false, isLimited: true, indirectObjectIdentifier: nil),
            AppPermissionGrant(permission: .fullDiskAccess, client: "com.a.first", clientIsPath: false, isLimited: false, indirectObjectIdentifier: nil),
            AppPermissionGrant(permission: .automation, client: "com.a.first", clientIsPath: false, isLimited: false, indirectObjectIdentifier: "com.apple.finder"),
        ]
        let apps = AppPermissionOverview.apps(from: grants)
        XCTAssertEqual(apps.map(\.client), ["com.a.first", "com.z.last"])
        XCTAssertEqual(apps[0].permissions, [.camera, .fullDiskAccess, .automation])
        XCTAssertEqual(apps[0].grants.count, 3)
        XCTAssertTrue(apps[0].grants.contains { $0.permission == .camera && $0.isLimited })
        XCTAssertEqual(apps[1].permissions, [.microphone])
    }

    func testOverviewKeepsPathClientsDistinctFromBundleIDs() {
        let grants = [
            AppPermissionGrant(permission: .fullDiskAccess, client: "/usr/bin/rsync", clientIsPath: true, isLimited: false, indirectObjectIdentifier: nil),
            AppPermissionGrant(permission: .fullDiskAccess, client: "com.rsync.gui", clientIsPath: false, isLimited: false, indirectObjectIdentifier: nil),
        ]
        let apps = AppPermissionOverview.apps(from: grants)
        XCTAssertEqual(apps.count, 2)
        XCTAssertEqual(Set(apps.map(\.clientIsPath)), [true, false])
    }

    func testOverviewEmpty() {
        XCTAssertTrue(AppPermissionOverview.apps(from: []).isEmpty)
    }
}
