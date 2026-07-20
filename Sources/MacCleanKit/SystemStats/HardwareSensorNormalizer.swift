import Foundation

/// Converts registry sensor values into the units used by the menu-bar model.
///
/// Keeping this logic independent of IOKit makes the different hardware
/// encodings deterministic and testable.
public enum HardwareSensorNormalizer {
    public static let gpuUtilizationKeys = [
        "Device Utilization %",
        "GPU Activity(%)",
        "Renderer Utilization %",
    ]

    public static let batteryTemperatureKeys = [
        "Temperature",
        "VirtualTemperature",
    ]

    /// Returns the highest finite GPU utilization as a fraction in `0...1`.
    public static func gpuUsageFraction(from samples: [[String: NSNumber]]) -> Double? {
        var maximumPercent: Double?

        for sample in samples {
            for key in gpuUtilizationKeys {
                guard let number = sample[key] else { continue }
                let percent = number.doubleValue
                guard percent.isFinite else { continue }
                maximumPercent = max(maximumPercent ?? 0, min(max(percent, 0), 100))
            }
        }

        return maximumPercent.map { $0 / 100 }
    }

    /// Uses the first valid battery temperature exposed by the registry.
    public static func batteryTemperatureCelsius(
        from properties: [String: NSNumber]
    ) -> Double? {
        for key in batteryTemperatureKeys {
            guard let rawValue = properties[key],
                  let temperature = batteryTemperatureCelsius(fromRawValue: rawValue) else {
                continue
            }
            return temperature
        }
        return nil
    }

    /// Normalizes known AppleSmartBattery encodings and rejects invalid values.
    public static func batteryTemperatureCelsius(fromRawValue rawValue: NSNumber) -> Double? {
        let raw = rawValue.doubleValue
        guard raw.isFinite else { return nil }

        let celsius: Double
        if raw >= 1_000 {
            celsius = raw / 100
        } else if raw > 120 {
            celsius = raw / 10
        } else {
            celsius = raw
        }

        guard celsius > 0, celsius <= 120 else { return nil }
        return celsius
    }
}
