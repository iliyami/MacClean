import XCTest
@testable import MacClean
@testable import MacCleanKit

final class PreferredWiFiClientTests: XCTestCase {

    private final class Capture: @unchecked Sendable {
        var shell: String?
        var adminCalls = 0
    }

    func testListParsesInjectedHardwareAndPreferredOutput() async {
        let client = PreferredWiFiClient(
            run: { _, args in
                if args == ["-listallhardwareports"] {
                    return ("""
                        Hardware Port: Wi-Fi
                        Device: en0
                        Ethernet Address: aa:bb:cc:dd:ee:ff
                        """, "", 0)
                }
                if args == ["-listpreferredwirelessnetworks", "en0"] {
                    return ("Preferred networks on en0:\n\tHome\n\tCafe\n", "", 0)
                }
                return ("", "unexpected \(args)", 1)
            },
            runAdminShell: { _ in ("", "not used", 1) }
        )
        let result = await client.listNetworks()
        let nets = try? result.get()
        XCTAssertEqual(nets?.map(\.ssid), ["Home", "Cafe"])
        XCTAssertEqual(nets?.first?.device, "en0")
    }

    func testListFailsWhenNoWiFiHardware() async {
        let client = PreferredWiFiClient(
            run: { _, _ in
                ("Hardware Port: Ethernet\nDevice: en1\nEthernet Address: 00:00:00:00:00:00\n", "", 0)
            },
            runAdminShell: { _ in ("", "", 1) }
        )
        let result = await client.listNetworks()
        guard case .failure(.noWiFiHardware) = result else {
            return XCTFail("expected noWiFiHardware, got \(result)")
        }
    }

    func testForgetSendsQuotedBatchToAdminRunner() async {
        let capture = Capture()
        let client = PreferredWiFiClient(
            run: { _, _ in ("", "", 1) },
            runAdminShell: { shell in
                capture.shell = shell
                return ("", "", 0)
            }
        )
        let nets = [PreferredWiFiNetwork(device: "en0", ssid: "Home Network")]
        let result = await client.forget(nets)
        guard case .success = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(
            capture.shell,
            "'/usr/sbin/networksetup' '-removepreferredwirelessnetwork' 'en0' 'Home Network'"
        )
    }

    func testForgetMapsOsascriptCancel() async {
        let client = PreferredWiFiClient(
            run: { _, _ in ("", "", 1) },
            runAdminShell: { _ in ("", "User canceled. (-128)", 1) }
        )
        let result = await client.forget([PreferredWiFiNetwork(device: "en0", ssid: "Home")])
        guard case .failure(.adminCancelled) = result else {
            return XCTFail("expected adminCancelled, got \(result)")
        }
    }

    func testForgetRejectsIllegalDeviceWithoutCallingAdmin() async {
        let capture = Capture()
        let client = PreferredWiFiClient(
            run: { _, _ in ("", "", 1) },
            runAdminShell: { _ in
                capture.adminCalls += 1
                return ("", "", 0)
            }
        )
        let result = await client.forget([PreferredWiFiNetwork(device: "en0; reboot", ssid: "Home")])
        guard case .failure(.invalidDevice) = result else {
            return XCTFail("expected invalidDevice, got \(result)")
        }
        XCTAssertEqual(capture.adminCalls, 0)
    }
}
