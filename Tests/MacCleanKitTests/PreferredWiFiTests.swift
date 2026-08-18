import XCTest
@testable import MacCleanKit

final class PreferredWiFiTests: XCTestCase {

    private let hardwareFixture = """
        Hardware Port: Ethernet
        Device: en1
        Ethernet Address: 11:22:33:44:55:66

        Hardware Port: Wi-Fi
        Device: en0
        Ethernet Address: aa:bb:cc:dd:ee:ff

        Hardware Port: Thunderbolt Bridge
        Device: bridge0
        Ethernet Address: 00:11:22:33:44:55
        """

    private let preferredFixture = """
        Preferred networks on en0:
        \tHome Network
        \tCafe WiFi
        \t'; rm -rf /
        """

    func testHardwarePortsFindsWiFiDeviceOnly() {
        XCTAssertEqual(PreferredWiFiParser.wifiDevices(from: hardwareFixture), ["en0"])
    }

    func testHardwarePortsFindsAirPortAndWLAN() {
        let airport = """
            Hardware Port: AirPort
            Device: en2
            Ethernet Address: 00:00:00:00:00:00
            """
        XCTAssertEqual(PreferredWiFiParser.wifiDevices(from: airport), ["en2"])

        let wlan = """
            Hardware Port: WLAN
            Device: en3
            Ethernet Address: 00:00:00:00:00:00
            """
        XCTAssertEqual(PreferredWiFiParser.wifiDevices(from: wlan), ["en3"])
    }

    func testHardwarePortsEmptyWhenNoWiFi() {
        let ethernetOnly = """
            Hardware Port: Ethernet
            Device: en1
            Ethernet Address: 11:22:33:44:55:66
            """
        XCTAssertEqual(PreferredWiFiParser.wifiDevices(from: ethernetOnly), [])
    }

    func testPreferredNetworksStripsHeaderAndIndent() {
        let nets = PreferredWiFiParser.preferredNetworks(from: preferredFixture, device: "en0")
        XCTAssertEqual(nets.map(\.ssid), ["Home Network", "Cafe WiFi", "'; rm -rf /"])
        XCTAssertTrue(nets.allSatisfy { $0.device == "en0" })
    }

    func testPreferredNetworksEmptyList() {
        let output = "Preferred networks on en0:\n"
        XCTAssertTrue(PreferredWiFiParser.preferredNetworks(from: output, device: "en0").isEmpty)
    }

    func testPreferredNetworksNotAWiFiInterface() {
        let output = "en1 is not a Wi-Fi interface.\n"
        XCTAssertTrue(PreferredWiFiParser.preferredNetworks(from: output, device: "en1").isEmpty)
    }

    func testValidDevices() {
        XCTAssertTrue(PreferredWiFiCommands.isValidDevice("en0"))
        XCTAssertTrue(PreferredWiFiCommands.isValidDevice("en12"))
        XCTAssertFalse(PreferredWiFiCommands.isValidDevice("en0; reboot"))
        XCTAssertFalse(PreferredWiFiCommands.isValidDevice("en0 en1"))
        XCTAssertFalse(PreferredWiFiCommands.isValidDevice(""))
        XCTAssertFalse(PreferredWiFiCommands.isValidDevice("/tmp/x"))
        XCTAssertFalse(PreferredWiFiCommands.isValidDevice("$(whoami)"))
    }

    func testRemoveArgv() {
        XCTAssertEqual(
            PreferredWiFiCommands.removeArguments(device: "en0", ssid: "Cafe WiFi") ?? [],
            ["-removepreferredwirelessnetwork", "en0", "Cafe WiFi"]
        )
    }

    func testRemoveShellQuotesMetacharacters() {
        let line = PreferredWiFiCommands.removeShellCommand(device: "en0", ssid: "'; rm -rf /")
        XCTAssertEqual(
            line,
            "'/usr/sbin/networksetup' '-removepreferredwirelessnetwork' 'en0' ''\\''; rm -rf /'"
        )
    }

    func testRemoveShellRejectsIllegalDevice() {
        XCTAssertNil(PreferredWiFiCommands.removeShellCommand(device: "en0; reboot", ssid: "Home"))
    }

    func testBatchJoinsQuotedCommands() {
        let nets = [
            PreferredWiFiNetwork(device: "en0", ssid: "A"),
            PreferredWiFiNetwork(device: "en0", ssid: "B"),
        ]
        let batch = PreferredWiFiCommands.removeBatchShellCommand(networks: nets)
        XCTAssertEqual(
            batch,
            "'/usr/sbin/networksetup' '-removepreferredwirelessnetwork' 'en0' 'A' ; '/usr/sbin/networksetup' '-removepreferredwirelessnetwork' 'en0' 'B'"
        )
    }

    func testBatchNilIfAnyDeviceIllegal() {
        let nets = [
            PreferredWiFiNetwork(device: "en0", ssid: "A"),
            PreferredWiFiNetwork(device: "en0;x", ssid: "B"),
        ]
        XCTAssertNil(PreferredWiFiCommands.removeBatchShellCommand(networks: nets))
    }

    func testListCommands() {
        XCTAssertEqual(PreferredWiFiCommands.listHardwarePortsArguments, ["-listallhardwareports"])
        XCTAssertEqual(
            PreferredWiFiCommands.listPreferredArguments(device: "en0"),
            ["-listpreferredwirelessnetworks", "en0"]
        )
        XCTAssertNil(PreferredWiFiCommands.listPreferredArguments(device: "en0;x"))
    }
}
