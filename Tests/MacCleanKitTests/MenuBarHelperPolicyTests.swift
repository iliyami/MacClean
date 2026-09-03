import XCTest
@testable import MacCleanKit

final class MenuBarHelperPolicyTests: XCTestCase {

    // MARK: - Duplicate keep-one (issue #138)

    func testLoneInstanceDoesNotExit() {
        XCTAssertFalse(
            MenuBarInstancePolicy.shouldExitAsDuplicate(
                selfPID: 42,
                selfLaunchDate: Date(timeIntervalSince1970: 100),
                siblings: []
            )
        )
    }

    func testTwoInstancesRacingNeverBothExit() {
        let a = MenuBarInstance(pid: 100, launchDate: Date(timeIntervalSince1970: 1))
        let b = MenuBarInstance(pid: 200, launchDate: Date(timeIntervalSince1970: 1.05))
        let aExits = MenuBarInstancePolicy.shouldExitAsDuplicate(
            selfPID: a.pid, selfLaunchDate: a.launchDate, siblings: [b]
        )
        let bExits = MenuBarInstancePolicy.shouldExitAsDuplicate(
            selfPID: b.pid, selfLaunchDate: b.launchDate, siblings: [a]
        )
        XCTAssertNotEqual(aExits, bExits, "exactly one of the two copies must stay")
        XCTAssertTrue(aExits || bExits)
        XCTAssertFalse(aExits, "older launchDate must be the survivor")
    }

    func testEqualLaunchDatesKeepLowestPID() {
        let date = Date(timeIntervalSince1970: 50)
        XCTAssertFalse(
            MenuBarInstancePolicy.shouldExitAsDuplicate(
                selfPID: 10, selfLaunchDate: date,
                siblings: [MenuBarInstance(pid: 20, launchDate: date)]
            )
        )
        XCTAssertTrue(
            MenuBarInstancePolicy.shouldExitAsDuplicate(
                selfPID: 20, selfLaunchDate: date,
                siblings: [MenuBarInstance(pid: 10, launchDate: date)]
            )
        )
    }

    func testThreeInstancesKeepExactlyOne() {
        let instances = [
            MenuBarInstance(pid: 3, launchDate: Date(timeIntervalSince1970: 30)),
            MenuBarInstance(pid: 1, launchDate: Date(timeIntervalSince1970: 10)),
            MenuBarInstance(pid: 2, launchDate: Date(timeIntervalSince1970: 20)),
        ]
        let exits = instances.map { me in
            MenuBarInstancePolicy.shouldExitAsDuplicate(
                selfPID: me.pid,
                selfLaunchDate: me.launchDate,
                siblings: instances.filter { $0.pid != me.pid }
            )
        }
        XCTAssertEqual(exits.filter { $0 }.count, 2)
        XCTAssertFalse(exits[1], "pid 1 has the oldest launchDate")
    }

    func testMissingLaunchDateFallsBackToLowestPID() {
        XCTAssertFalse(
            MenuBarInstancePolicy.shouldExitAsDuplicate(
                selfPID: 5, selfLaunchDate: nil,
                siblings: [MenuBarInstance(pid: 9, launchDate: nil)]
            )
        )
        XCTAssertTrue(
            MenuBarInstancePolicy.shouldExitAsDuplicate(
                selfPID: 9, selfLaunchDate: nil,
                siblings: [MenuBarInstance(pid: 5, launchDate: nil)]
            )
        )
    }

    func testKnownLaunchDateBeatsMissingDate() {
        let dated = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(
            MenuBarInstancePolicy.shouldExitAsDuplicate(
                selfPID: 1, selfLaunchDate: dated,
                siblings: [MenuBarInstance(pid: 2, launchDate: nil)]
            )
        )
        XCTAssertTrue(
            MenuBarInstancePolicy.shouldExitAsDuplicate(
                selfPID: 2, selfLaunchDate: nil,
                siblings: [MenuBarInstance(pid: 1, launchDate: dated)]
            )
        )
    }

    // MARK: - Keep-alive

    func testDisableTerminatesARunningHelper() {
        XCTAssertEqual(
            MenuBarKeepAlivePolicy.action(
                preferenceEnabled: false,
                helperIsRunning: true,
                userQuit: false,
                alreadyWaitedAfterRegister: true,
                launchInFlight: false
            ),
            .terminate
        )
    }

    func testDisableDoesNothingWhenAlreadyStopped() {
        XCTAssertEqual(
            MenuBarKeepAlivePolicy.action(
                preferenceEnabled: false,
                helperIsRunning: false,
                userQuit: false,
                alreadyWaitedAfterRegister: true,
                launchInFlight: false
            ),
            .none
        )
    }

    func testEnableWaitsOnceAfterRegisterBeforeOpening() {
        XCTAssertEqual(
            MenuBarKeepAlivePolicy.action(
                preferenceEnabled: true,
                helperIsRunning: false,
                userQuit: false,
                alreadyWaitedAfterRegister: false,
                launchInFlight: false
            ),
            .waitThenRecheck
        )
    }

    func testEnableLaunchesAfterGraceIfStillMissing() {
        XCTAssertEqual(
            MenuBarKeepAlivePolicy.action(
                preferenceEnabled: true,
                helperIsRunning: false,
                userQuit: false,
                alreadyWaitedAfterRegister: true,
                launchInFlight: false
            ),
            .launch
        )
    }

    func testEnableDoesNothingWhenHelperAlreadyRunning() {
        XCTAssertEqual(
            MenuBarKeepAlivePolicy.action(
                preferenceEnabled: true,
                helperIsRunning: true,
                userQuit: false,
                alreadyWaitedAfterRegister: false,
                launchInFlight: false
            ),
            .none
        )
    }

    func testUserQuitDoesNotRelaunchWhileToggleStaysOn() {
        XCTAssertEqual(
            MenuBarKeepAlivePolicy.action(
                preferenceEnabled: true,
                helperIsRunning: false,
                userQuit: true,
                alreadyWaitedAfterRegister: true,
                launchInFlight: false
            ),
            .none
        )
    }

    func testLaunchInFlightPreventsASecondOpen() {
        XCTAssertEqual(
            MenuBarKeepAlivePolicy.action(
                preferenceEnabled: true,
                helperIsRunning: false,
                userQuit: false,
                alreadyWaitedAfterRegister: true,
                launchInFlight: true
            ),
            .none
        )
    }

    func testUserQuitFlagRoundTripsThroughInjectedDefaults() {
        let suite = "menu-bar-keep-alive-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("could not open isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(MenuBarKeepAlive.isUserQuit(defaults))
        MenuBarKeepAlive.setUserQuit(true, defaults: defaults)
        XCTAssertTrue(MenuBarKeepAlive.isUserQuit(defaults))
        MenuBarKeepAlive.setUserQuit(false, defaults: defaults)
        XCTAssertFalse(MenuBarKeepAlive.isUserQuit(defaults))
    }

    func testSharedKeysStayStable() {
        XCTAssertEqual(MenuBarKeepAlive.preferenceKey, "showMenuBarWidget")
        XCTAssertEqual(MenuBarKeepAlive.userQuitKey, "menuBarWidgetUserQuit")
    }
}
