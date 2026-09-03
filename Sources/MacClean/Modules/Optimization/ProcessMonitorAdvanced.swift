import Foundation
import AppKit
import Darwin

public actor ProcessStatsCollector {
    public struct ProcessStats: Identifiable, Sendable {
        public let id: Int32 // pid
        public let name: String
        public let cpuPercent: Double
        public let memoryBytes: UInt64
        public let isResponsive: Bool
        public let bundleIdentifier: String?
    }

    private var previousCPUTimes: [Int32: (user: UInt64, system: UInt64, timestamp: Date)] = [:]

    public init() {}

    public func getProcessStats() -> [ProcessStats] {
        let apps = NSWorkspace.shared.runningApplications
        var results: [ProcessStats] = []

        for app in apps {
            guard let name = app.localizedName else { continue }
            let pid = app.processIdentifier

            let cpu = cpuUsage(for: pid)
            let mem = memoryUsage(for: pid)

            results.append(ProcessStats(
                id: pid,
                name: name,
                cpuPercent: cpu,
                memoryBytes: mem,
                isResponsive: !app.isTerminated,
                bundleIdentifier: app.bundleIdentifier
            ))
        }

        return results.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    public func getHungApps() -> [ProcessStats] {
        getProcessStats().filter { !$0.isResponsive }
    }

    public func getHeavyConsumers(cpuThreshold: Double = 50.0) -> [ProcessStats] {
        getProcessStats().filter { $0.cpuPercent > cpuThreshold }
    }

    private func cpuUsage(for pid: Int32) -> Double {
        var taskInfo = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size

        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(size))
        guard result == size else { return 0 }

        let currentUser = taskInfo.pti_total_user
        let currentSystem = taskInfo.pti_total_system
        let now = Date()

        if let prev = previousCPUTimes[pid] {
            let elapsed = now.timeIntervalSince(prev.timestamp)
            guard elapsed > 0 else { return 0 }

            let userDiff = Double(currentUser - prev.user) / 1_000_000_000 // ns to s
            let sysDiff = Double(currentSystem - prev.system) / 1_000_000_000
            let cpuPercent = ((userDiff + sysDiff) / elapsed) * 100

            previousCPUTimes[pid] = (currentUser, currentSystem, now)
            return min(cpuPercent, 100.0 * Double(ProcessInfo.processInfo.activeProcessorCount))
        }

        previousCPUTimes[pid] = (currentUser, currentSystem, now)
        return 0
    }

    /// `task_for_pid` (the previous implementation here) requires the
    /// `com.apple.security.get-task-allow` entitlement — or root — to
    /// obtain another process's task port. Neither applies to a normal,
    /// hardened-runtime GUI app querying sibling apps, so it failed with
    /// KERN_FAILURE for essentially every process but our own, and every
    /// app in the "heavy consumers" / memory list silently showed 0 bytes.
    /// `proc_pid_rusage` goes through libproc instead (the same family of
    /// call already used for `cpuUsage` above via `proc_pidinfo`), which
    /// only needs to see the target process, not open its task port.
    private nonisolated func memoryUsage(for pid: Int32) -> UInt64 {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rawPtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V2, rawPtr)
            }
        }
        guard result == 0 else { return 0 }
        return info.ri_resident_size
    }
}
