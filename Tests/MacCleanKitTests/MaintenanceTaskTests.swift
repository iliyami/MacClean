import XCTest
import Foundation
@testable import MacCleanKit

final class MaintenanceTaskTests: EnglishAppLanguageTestCase {

    func testTenTasksExist() {
        // "Repair Disk Permissions" was removed (issue #82). pruneDocker was
        // added with the Developer Junk feature, bringing the total to 10.
        XCTAssertEqual(MaintenanceTask.allCases.count, 10)
    }

    func testRepairDiskPermissionsRemoved() {
        XCTAssertFalse(
            MaintenanceTask.allCases.contains { $0.rawValue == "Repair Disk Permissions" },
            "Repair Disk Permissions must be gone — diskutil's repairPermissions verb no longer exists (issue #82)"
        )
    }

    func testNoTaskUsesRemovedDiskutilVerb() {
        for task in MaintenanceTask.allCases {
            guard let cmd = task.systemCommand else { continue }
            XCTAssertFalse(cmd.arguments.contains("repairPermissions"),
                           "\(task) still invokes the removed diskutil repairPermissions verb")
        }
    }

    func testFreeUpPurgeableSpaceActuallyReclaims() {
        // It used to run `diskutil apfs listSnapshots /`, which only LISTS
        // snapshots and frees nothing. It must now thin purgeable local
        // snapshots so it does what its name promises (issue #82).
        let cmd = MaintenanceTask.freeUpPurgeableSpace.systemCommand
        XCTAssertEqual(cmd?.executable, "/usr/bin/tmutil")
        XCTAssertEqual(cmd?.arguments.first, "thinlocalsnapshots")
        XCTAssertNotEqual(cmd?.arguments.first, "apfs",
                          "must not be the old list-only diskutil command")
    }

    func testAllTasksHaveDescriptionAndIcon() {
        for task in MaintenanceTask.allCases {
            XCTAssertFalse(task.description.isEmpty, "\(task) missing description")
            XCTAssertFalse(task.icon.isEmpty, "\(task) missing icon")
            XCTAssertFalse(task.rawValue.isEmpty, "\(task) missing display name")
        }
    }

    func testSystemCommandsResolveCorrectly() {
        XCTAssertEqual(MaintenanceTask.freeUpRAM.systemCommand?.executable, "/usr/sbin/purge")
        XCTAssertEqual(MaintenanceTask.flushDNSCache.systemCommand?.executable, "/usr/bin/dscacheutil")
        XCTAssertEqual(MaintenanceTask.flushDNSCache.systemCommand?.arguments, ["-flushcache"])
        XCTAssertEqual(MaintenanceTask.reindexSpotlight.systemCommand?.executable, "/usr/bin/mdutil")
    }

    func testSpeedUpMailHasNoSystemCommand() {
        XCTAssertNil(MaintenanceTask.speedUpMail.systemCommand,
                     "Mail reindex is custom logic, not a Process invocation")
    }

    func testAllSystemCommandsArePresentExceptCustomTasks() {
        // speedUpMail and pruneDocker are custom-executed (nil systemCommand).
        let customTasks: Set<MaintenanceTask> = [.speedUpMail, .pruneDocker]
        for task in MaintenanceTask.allCases {
            if customTasks.contains(task) {
                XCTAssertNil(task.systemCommand)
            } else {
                XCTAssertNotNil(task.systemCommand, "\(task) should have a system command")
            }
        }
    }

    func testIdentifiableConformance() {
        XCTAssertEqual(MaintenanceTask.freeUpRAM.id, "Free Up RAM")
    }

    // MARK: - Severity classification

    /// SPEC: the three tasks with multi-hour side effects on the user's
    /// daily experience MUST be classified .advanced so the View can
    /// gate them behind explicit consent. This test is a regression
    /// guard against a refactor accidentally re-classifying them as safe.
    func testAdvancedTasks_includeTheKnownDangerousOnes() {
        XCTAssertEqual(MaintenanceTask.rebuildLaunchServices.severity, .advanced,
                       "Rebuild Launch Services breaks file-type-to-app mapping for hours — must be .advanced")
        XCTAssertEqual(MaintenanceTask.reindexSpotlight.severity, .advanced,
                       "Reindex Spotlight kills search for hours — must be .advanced")
        XCTAssertEqual(MaintenanceTask.thinTimeMachineSnapshots.severity, .advanced,
                       "Thin Time Machine Snapshots deletes local snapshots — must be .advanced")
    }

    /// SPEC: every-day-safe tasks stay safe (no friction).
    func testSafeTasks_areNotGatedBehindFriction() {
        XCTAssertEqual(MaintenanceTask.freeUpRAM.severity, .safe)
        XCTAssertEqual(MaintenanceTask.flushDNSCache.severity, .safe)
        XCTAssertEqual(MaintenanceTask.verifyStartupDisk.severity,
                       .safe, "verify is read-only — no side effects")
    }

    func testEveryTaskHasNonEmptySideEffectsDescription() {
        for task in MaintenanceTask.allCases {
            XCTAssertFalse(
                task.sideEffects.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(task) is missing a sideEffects description — the confirmation modal needs something to show"
            )
        }
    }

    func testAdvancedTaskSideEffects_warnInPlainEnglish() {
        // The dangerous ones must explicitly call out the duration of impact,
        // not just the action. Users don't know what "rebuild Launch Services"
        // means; they need "your double-clicks will fail for hours".
        let lsCopy = MaintenanceTask.rebuildLaunchServices.sideEffects.lowercased()
        XCTAssertTrue(lsCopy.contains("hour"),
                      "Rebuild Launch Services side-effect text must mention time-to-recover")
        let spotlightCopy = MaintenanceTask.reindexSpotlight.sideEffects.lowercased()
        XCTAssertTrue(spotlightCopy.contains("hour") || spotlightCopy.contains("longer"),
                      "Reindex Spotlight side-effect text must mention time-to-recover")
    }

    func testAllExecutablePathsAreAbsolute() {
        for task in MaintenanceTask.allCases {
            if let cmd = task.systemCommand {
                XCTAssertTrue(cmd.executable.hasPrefix("/"),
                              "\(task) executable path must be absolute (got: \(cmd.executable))")
            }
        }
    }

    // MARK: - Docker prune

    func testPruneDockerMetadata() {
        let t = MaintenanceTask.pruneDocker
        XCTAssertEqual(t.severity, .advanced)
        XCTAssertNil(t.systemCommand)              // executor special-cases it
        XCTAssertFalse(t.sideEffects.isEmpty)
    }

    func testResolveDockerPathReturnsFirstExisting() {
        let only = "/opt/homebrew/bin/docker"
        let path = MaintenanceTask.resolveDockerPath { $0 == only }
        XCTAssertEqual(path, only)
    }

    func testResolveDockerPathNilWhenNoneExist() {
        XCTAssertNil(MaintenanceTask.resolveDockerPath { _ in false })
    }

    // MARK: - Missing system tools (issue #129)

    func testMaintenanceScriptsUnavailableWhenPeriodicIsMissing() {
        // Apple removed /usr/sbin/periodic in macOS 26. The task must report
        // the tool as unavailable rather than run and surface
        // `/bin/sh: /usr/sbin/periodic: No such file or directory`.
        let task = MaintenanceTask.runMaintenanceScripts
        XCTAssertEqual(task.systemCommand?.executable, "/usr/sbin/periodic")
        XCTAssertFalse(task.systemCommandIsAvailable { $0 != "/usr/sbin/periodic" })
    }

    func testSystemCommandIsAvailableWhenTheExecutableExists() {
        XCTAssertTrue(MaintenanceTask.runMaintenanceScripts.systemCommandIsAvailable { _ in true })
    }

    func testEveryTaskWithACommandIsGatedOnThatCommand() {
        // The check must consult each task's own executable, not a fixed path,
        // so a future removal of any hard-coded tool is reported the same way.
        for task in MaintenanceTask.allCases {
            guard let command = task.systemCommand else { continue }
            XCTAssertFalse(task.systemCommandIsAvailable { $0 != command.executable },
                           "\(task) is not gated on \(command.executable)")
            XCTAssertTrue(task.systemCommandIsAvailable { $0 == command.executable },
                          "\(task) reports unavailable when \(command.executable) exists")
        }
    }

    func testTasksWithoutASystemCommandAreNotGated() {
        // Mail reindex and Docker prune have their own executor paths; a
        // filesystem check must never block them.
        for task in MaintenanceTask.allCases where task.systemCommand == nil {
            XCTAssertTrue(task.systemCommandIsAvailable { _ in false },
                          "\(task) has no system command and must not be gated")
        }
    }
}
