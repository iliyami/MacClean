import Foundation

/// The compact value shown next to the Mac Sai menu-bar icon.
///
/// Raw values are persisted in the shared defaults suite, so they must remain
/// stable across releases.
public enum MenuBarMetric: String, CaseIterable, Identifiable, Sendable {
    case diskFree = "diskFree"
    case gpuUsage = "gpuUsage"
    case memoryUsage = "memoryUsage"
    case batteryTemperature = "temperature"

    public static let defaultsKey = "menuBarMetric"
    public static let fallback: MenuBarMetric = .diskFree

    public var id: String { rawValue }

    public static func resolve(_ rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? fallback
    }

    public var localizedName: String {
        switch self {
        case .diskFree:
            L10n.tr("可用磁盘空间", "Free disk space")
        case .gpuUsage:
            L10n.tr("GPU 使用率", "GPU usage")
        case .memoryUsage:
            L10n.tr("内存使用率", "Memory usage")
        case .batteryTemperature:
            L10n.tr("电池温度", "Battery temperature")
        }
    }

    /// Formats the selected value without silently substituting another metric.
    public func formattedValue(
        diskFree: UInt64,
        gpuUsage: Double?,
        memoryUsage: Double,
        batteryTemperature: Double?
    ) -> String {
        switch self {
        case .diskFree:
            FileSizeFormatter.format(diskFree)
        case .gpuUsage:
            Self.formattedPercent(prefix: "GPU", value: gpuUsage)
        case .memoryUsage:
            Self.formattedPercent(prefix: "RAM", value: memoryUsage)
        case .batteryTemperature:
            Self.formattedTemperature(batteryTemperature)
        }
    }

    private static func formattedPercent(prefix: String, value: Double?) -> String {
        guard let value, value.isFinite else { return "\(prefix) --" }
        let percent = Int((min(max(value, 0), 1) * 100).rounded())
        return "\(prefix) \(percent)%"
    }

    private static func formattedTemperature(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0, value <= 120 else { return "--" }
        return "\(Int(value.rounded()))°C"
    }
}
