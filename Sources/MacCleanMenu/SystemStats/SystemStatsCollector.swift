import Foundation
import IOKit
import IOKit.ps
import MacCleanKit

public actor SystemStatsCollector {
    public struct SystemStats: Sendable {
        public let cpuUsage: Double
        public let cpuTemperature: Double?
        public let gpuUsage: Double?
        public let memoryTotal: UInt64
        public let memoryUsed: UInt64
        public let memoryPressure: Double
        public let swapUsed: UInt64
        public let diskTotal: UInt64
        public let diskFree: UInt64
        public let batteryLevel: Double?
        public let batteryHealth: Double?
        public let batteryIsCharging: Bool
        public let batteryCycleCount: Int?
        public let batteryTemperature: Double?
        public let uptime: TimeInterval
    }

    private var previousCPUTicks = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)

    public init() {}

    public func collect() -> SystemStats {
        let cpu = getCPUUsage()
        let gpu = getGPUUsage()
        let memory = getMemoryInfo()
        let disk = getDiskInfo()
        let battery = getBatteryInfo()

        return SystemStats(
            cpuUsage: cpu,
            cpuTemperature: nil, // Requires SMC access
            gpuUsage: gpu,
            memoryTotal: memory.total,
            memoryUsed: memory.used,
            memoryPressure: memory.pressure,
            swapUsed: memory.swapUsed,
            diskTotal: disk.total,
            diskFree: disk.free,
            batteryLevel: battery.level,
            batteryHealth: battery.health,
            batteryIsCharging: battery.isCharging,
            batteryCycleCount: battery.cycleCount,
            batteryTemperature: battery.temperature,
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    // MARK: - GPU

    /// Reads public IOAccelerator utilization counters. These fields are not
    /// available on every GPU or macOS version, so the absence of a supported
    /// counter is represented as `nil`.
    private func getGPUUsage() -> Double? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var samples: [[String: NSNumber]] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let statistics = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {
                samples.append(statistics.compactMapValues { $0 as? NSNumber })
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return HardwareSensorNormalizer.gpuUsageFraction(from: samples)
    }

    // MARK: - CPU

    private func getCPUUsage() -> Double {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else { return 0 }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<Int32>.size)
            )
        }

        // Hand off the raw mach data to the MacCleanKit parser — same
        // tests run against synthetic fixtures cover this code path now.
        let raw = Array(UnsafeBufferPointer(start: info, count: Int(numCPUInfo)))
        let current = CPUTicks.summed(rawLoadInfo: raw, cpuCount: Int(numCPUs))
        let usage = CPUUsage(previous: previousCPUTicks, current: current)
        previousCPUTicks = current
        return usage?.totalActiveFraction ?? 0
    }

    // MARK: - Memory

    private struct MemoryInfo {
        let total: UInt64
        let used: UInt64
        let pressure: Double
        let swapUsed: UInt64
    }

    private func getMemoryInfo() -> MemoryInfo {
        let total = UInt64(ProcessInfo.processInfo.physicalMemory)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemoryInfo(total: total, used: 0, pressure: 0, swapUsed: 0)
        }

        var swapStats = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swapStats, &swapSize, nil, 0)

        // Hand off to MacCleanKit pure types — same code paths tested in
        // MemoryStatsTests against fixture VMStatistics.
        let vm = VMStatistics(
            activeCount: UInt64(stats.active_count),
            inactiveCount: UInt64(stats.inactive_count),
            wireCount: UInt64(stats.wire_count),
            freeCount: UInt64(stats.free_count),
            compressorPageCount: UInt64(stats.compressor_page_count)
        )
        let usage = MemoryUsage(
            physicalTotal: total,
            vmStats: vm,
            pageSize: UInt64(getpagesize()),
            swapUsed: UInt64(swapStats.xsu_used)
        )
        return MemoryInfo(
            total: usage.total,
            used: usage.used,
            pressure: usage.pressure,
            swapUsed: usage.swapUsed
        )
    }

    // MARK: - Disk

    private struct DiskInfo {
        let total: UInt64
        let free: UInt64
    }

    private func getDiskInfo() -> DiskInfo {
        // Use statfs, not URLResourceValues' .volumeAvailableCapacityForImportant-
        // UsageKey. That key computes purgeable/reclaimable space and can route
        // through the storage + Spotlight metadata machinery, which is a known
        // source of indefinite hangs on machines with heavy APFS snapshots or
        // Time Machine backups. Because this collector runs serially on a
        // background actor and gates the whole menu-bar panel, one such hang
        // pins the UI on its loading spinner forever (issue #78). statfs is a
        // fast, purely in-kernel call with no such dependency.
        var fs = statfs()
        guard statfs("/", &fs) == 0 else {
            return DiskInfo(total: 0, free: 0)
        }
        // Route through MacCleanKit's DiskUsage so the free-clamping +
        // used/usedFraction math is exercised by DiskStatsTests fixtures.
        let usage = DiskUsage.fromStatfs(
            blocks: UInt64(fs.f_blocks),
            availableBlocks: UInt64(fs.f_bavail),
            blockSize: UInt64(fs.f_bsize)
        )
        return DiskInfo(total: usage.total, free: usage.free)
    }

    // MARK: - Battery

    private struct BatteryInfo {
        let level: Double?
        let health: Double?
        let isCharging: Bool
        let cycleCount: Int?
        let temperature: Double?
    }

    private func getBatteryInfo() -> BatteryInfo {
        let sensorTemperature = getBatterySensorTemperature()
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any]
        else {
            return BatteryInfo(
                level: nil,
                health: nil,
                isCharging: false,
                cycleCount: nil,
                temperature: sensorTemperature
            )
        }

        let currentCapacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false

        let level = maxCapacity > 0 ? Double(currentCapacity) / Double(maxCapacity) : nil

        // Design capacity and cycle count require IOKit SMC access
        // For now, use the basic power source info
        return BatteryInfo(
            level: level,
            health: nil,
            isCharging: isCharging,
            cycleCount: nil,
            temperature: sensorTemperature
        )
    }

    private func getBatterySensorTemperature() -> Double? {
        guard let matching = IOServiceMatching("AppleSmartBattery") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: [String: NSNumber] = [:]
        for key in HardwareSensorNormalizer.batteryTemperatureKeys {
            if let value = IORegistryEntryCreateCFProperty(
                service,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? NSNumber {
                properties[key] = value
            }
        }
        return HardwareSensorNormalizer.batteryTemperatureCelsius(from: properties)
    }
}
