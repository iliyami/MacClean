import Foundation
import XCTest

@testable import MacCleanKit

final class HardwareSensorNormalizerTests: XCTestCase {
    func testGPUUsageChoosesMaximumAcrossKnownKeysAndSamples() throws {
        let samples: [[String: NSNumber]] = [
            ["Device Utilization %": 24],
            ["GPU Activity(%)": 67, "Renderer Utilization %": 82],
        ]

        let usage = try XCTUnwrap(HardwareSensorNormalizer.gpuUsageFraction(from: samples))

        XCTAssertEqual(usage, 0.82, accuracy: 0.0001)
    }

    func testGPUUsageClampsFiniteValues() {
        XCTAssertEqual(
            HardwareSensorNormalizer.gpuUsageFraction(
                from: [["Device Utilization %": -15]]
            ),
            0
        )
        XCTAssertEqual(
            HardwareSensorNormalizer.gpuUsageFraction(
                from: [["Device Utilization %": 140]]
            ),
            1
        )
    }

    func testGPUUsageIgnoresUnknownAndNonFiniteValues() {
        XCTAssertNil(
            HardwareSensorNormalizer.gpuUsageFraction(
                from: [
                    ["Unknown": 50],
                    ["GPU Activity(%)": NSNumber(value: Double.nan)],
                ]
            )
        )
    }

    func testBatteryTemperatureNormalizesSupportedEncodings() throws {
        let hundredths = try XCTUnwrap(HardwareSensorNormalizer.batteryTemperatureCelsius(
            fromRawValue: 3_092
        ))
        let tenths = try XCTUnwrap(
            HardwareSensorNormalizer.batteryTemperatureCelsius(fromRawValue: 306)
        )
        let coldTenths = try XCTUnwrap(
            HardwareSensorNormalizer.batteryTemperatureCelsius(fromRawValue: 150)
        )
        let degrees = try XCTUnwrap(
            HardwareSensorNormalizer.batteryTemperatureCelsius(fromRawValue: 30.5)
        )

        XCTAssertEqual(hundredths, 30.92, accuracy: 0.0001)
        XCTAssertEqual(tenths, 30.6, accuracy: 0.0001)
        XCTAssertEqual(coldTenths, 15, accuracy: 0.0001)
        XCTAssertEqual(degrees, 30.5, accuracy: 0.0001)
    }

    func testBatteryTemperatureRejectsInvalidReadings() {
        XCTAssertNil(
            HardwareSensorNormalizer.batteryTemperatureCelsius(fromRawValue: 0)
        )
        XCTAssertNil(
            HardwareSensorNormalizer.batteryTemperatureCelsius(fromRawValue: 12_100)
        )
        XCTAssertNil(
            HardwareSensorNormalizer.batteryTemperatureCelsius(
                fromRawValue: NSNumber(value: Double.infinity)
            )
        )
    }

    func testBatteryTemperatureFallsBackToNextRegistryKey() throws {
        let temperature = try XCTUnwrap(HardwareSensorNormalizer.batteryTemperatureCelsius(
            from: [
                "Temperature": 0,
                "VirtualTemperature": 3_125,
            ]
        ))

        XCTAssertEqual(temperature, 31.25, accuracy: 0.0001)
    }
}
