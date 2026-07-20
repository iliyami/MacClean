import Foundation
import XCTest

@testable import MacCleanKit

final class MenuBarMetricTests: XCTestCase {
    func testCasesAndRawValuesStayStable() {
        XCTAssertEqual(
            MenuBarMetric.allCases.map(\.rawValue),
            ["diskFree", "gpuUsage", "memoryUsage", "temperature"]
        )
    }

    func testMissingAndUnknownValuesFallBackToDisk() {
        XCTAssertEqual(MenuBarMetric.resolve(nil), .diskFree)
        XCTAssertEqual(MenuBarMetric.resolve("futureMetric"), .diskFree)
        XCTAssertEqual(MenuBarMetric.resolve("temperature"), .batteryTemperature)
    }

    func testLocalizedNames() {
        let sharedDefaults = SharedAppState.defaults
        let sharedValue = sharedDefaults.object(forKey: AppLanguage.defaultsKey)
        let standardValue = UserDefaults.standard.object(forKey: AppLanguage.defaultsKey)
        defer {
            if let sharedValue {
                sharedDefaults.set(sharedValue, forKey: AppLanguage.defaultsKey)
            } else {
                sharedDefaults.removeObject(forKey: AppLanguage.defaultsKey)
            }
            if let standardValue {
                UserDefaults.standard.set(standardValue, forKey: AppLanguage.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.defaultsKey)
            }
        }

        AppLanguage.current = .en
        XCTAssertEqual(MenuBarMetric.diskFree.localizedName, "Free disk space")
        XCTAssertEqual(MenuBarMetric.gpuUsage.localizedName, "GPU usage")
        XCTAssertEqual(MenuBarMetric.memoryUsage.localizedName, "Memory usage")
        XCTAssertEqual(MenuBarMetric.batteryTemperature.localizedName, "Battery temperature")

        AppLanguage.current = .zhHans
        XCTAssertEqual(MenuBarMetric.diskFree.localizedName, "可用磁盘空间")
        XCTAssertEqual(MenuBarMetric.batteryTemperature.localizedName, "电池温度")
    }

    func testDiskKeepsExistingFormatting() {
        let bytes: UInt64 = 245_000_000_000
        XCTAssertEqual(
            MenuBarMetric.diskFree.formattedValue(
                diskFree: bytes,
                gpuUsage: nil,
                memoryUsage: 0,
                batteryTemperature: nil
            ),
            FileSizeFormatter.format(bytes)
        )
    }

    func testPercentagesRoundAndClamp() {
        XCTAssertEqual(
            MenuBarMetric.gpuUsage.formattedValue(
                diskFree: 0,
                gpuUsage: 0.424,
                memoryUsage: 0,
                batteryTemperature: nil
            ),
            "GPU 42%"
        )
        XCTAssertEqual(
            MenuBarMetric.gpuUsage.formattedValue(
                diskFree: 0,
                gpuUsage: -0.2,
                memoryUsage: 0,
                batteryTemperature: nil
            ),
            "GPU 0%"
        )
        XCTAssertEqual(
            MenuBarMetric.memoryUsage.formattedValue(
                diskFree: 0,
                gpuUsage: nil,
                memoryUsage: 1.2,
                batteryTemperature: nil
            ),
            "RAM 100%"
        )
    }

    func testUnavailableAndNonFiniteValuesUseDoubleHyphen() {
        XCTAssertEqual(
            MenuBarMetric.gpuUsage.formattedValue(
                diskFree: 0,
                gpuUsage: nil,
                memoryUsage: 0,
                batteryTemperature: nil
            ),
            "GPU --"
        )
        XCTAssertEqual(
            MenuBarMetric.memoryUsage.formattedValue(
                diskFree: 0,
                gpuUsage: nil,
                memoryUsage: .nan,
                batteryTemperature: nil
            ),
            "RAM --"
        )
        XCTAssertEqual(
            MenuBarMetric.batteryTemperature.formattedValue(
                diskFree: 0,
                gpuUsage: nil,
                memoryUsage: 0,
                batteryTemperature: nil
            ),
            "--"
        )
        XCTAssertEqual(
            MenuBarMetric.batteryTemperature.formattedValue(
                diskFree: 0,
                gpuUsage: nil,
                memoryUsage: 0,
                batteryTemperature: .infinity
            ),
            "--"
        )
    }

    func testBatteryTemperatureRoundsToWholeDegrees() {
        XCTAssertEqual(
            MenuBarMetric.batteryTemperature.formattedValue(
                diskFree: 0,
                gpuUsage: nil,
                memoryUsage: 0,
                batteryTemperature: 30.6
            ),
            "31°C"
        )
    }
}
