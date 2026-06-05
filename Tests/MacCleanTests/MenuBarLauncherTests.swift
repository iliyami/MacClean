import XCTest
import ServiceManagement
@testable import MacClean
import MacCleanKit

/// Tests for the `MenuBarLauncher` SMAppService wrapper.
///
/// These tests deliberately **do not** call `register()` / `unregister()`
/// / `setEnabled()` — those mutate the real launchd database and would
/// plant a login item on every test run. See the comparable LaunchAgent
/// guidance: tests must not pollute the user's macOS state. The surface
/// we can safely exercise is the read-only side: identity, initial
/// state, status readability.
@MainActor
final class MenuBarLauncherTests: XCTestCase {

    func testSharedInstanceIsSingleton() {
        let a = MenuBarLauncher.shared
        let b = MenuBarLauncher.shared
        XCTAssertTrue(a === b, "shared should return the same instance every time")
    }

    func testInitialLastErrorIsNil() {
        // Fresh state from the singleton — no prior register attempt
        // should have left an error behind.
        XCTAssertNil(MenuBarLauncher.shared.lastError)
    }

    func testStatusIsReadableWithoutCrashing() {
        // The actual returned status depends on whether the helper is
        // bundled in the test runtime (it isn't, under `swift test`),
        // but reading the value must not crash and must yield a known
        // SMAppService.Status case.
        let status = MenuBarLauncher.shared.status
        let knownCases: [SMAppService.Status] = [
            .notRegistered, .enabled, .requiresApproval, .notFound,
        ]
        XCTAssertTrue(knownCases.contains(status),
                      "status returned an unexpected case: \(status)")
    }

    func testIsRegisteredMatchesStatus() {
        // isRegistered is the boolean projection of `status == .enabled`.
        // Whichever side launchd reports, the two must agree.
        let launcher = MenuBarLauncher.shared
        XCTAssertEqual(launcher.isRegistered, launcher.status == .enabled)
    }

    func testBundleIdentifierIsTheConstant() {
        // The Service Management identifier must equal the constant the
        // build script writes into MacCleanMenu.app's Info.plist
        // (`com.macclean.menu`). If these ever diverge, register() fails
        // silently with `.notFound`. Catch the drift here.
        XCTAssertEqual(MCConstants.menuBundleIdentifier, "com.macclean.menu")
    }

    // Regression coverage for issue #58 — "Crash On macOS 26.5.1".
    //
    // `openHelper(at:)` launches the menu-bar helper via
    // `NSWorkspace.openApplication`, whose result is delivered off the main
    // thread (LaunchServices' `com.apple.launchservices.open-queue`). The
    // shipped 1.8.3 build handled that result in a main-actor-isolated
    // completion closure; on the macOS 26 runtime the closure's main-actor
    // executor assertion traps (SIGTRAP) the instant it fires off-main,
    // crashing the app. The fix awaits the async overload so the continuation
    // resumes on the main actor.
    //
    // This drives that path with a URL that can't be opened: the launch fails,
    // the failure lands in `lastError`, and — the point of the test — the
    // process does NOT trap. On macOS 26, a regression to off-main `@MainActor`
    // access in this path would abort the test process instead of failing soft.
    func testOpenHelperRecordsFailureWithoutTrappingOffMainActor() async {
        let launcher = MenuBarLauncher.shared
        defer { launcher.lastError = nil }   // don't pollute the shared singleton

        let bogus = URL(fileURLWithPath:
            "/private/var/empty/MacCleanMenu-\(UUID().uuidString).app")
        await launcher.openHelper(at: bogus)

        // Reaching this line at all proves we survived the off-main hop.
        XCTAssertNotNil(launcher.lastError,
                        "A failed helper launch should surface via lastError")
    }
}
