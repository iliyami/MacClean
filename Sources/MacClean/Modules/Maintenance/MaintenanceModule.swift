import Foundation
import MacCleanKit

public struct MaintenanceModule: ScanModule {
    public let id = "maintenance"
    public let name = "Maintenance"
    public let category = ModuleCategory.performance

    public init() {}

    public func scan() async -> [ScanResult] { [] }
}

// MARK: - Maintenance Executor
//
// `MaintenanceTask` (the enum + descriptions + system commands) lives in
// MacCleanKit. This actor wraps `Process` to actually run the commands.

public actor MaintenanceExecutor {
    public struct TaskResult: Sendable {
        public let task: MaintenanceTask
        public let success: Bool
        public let output: String
        public let error: String?
    }

    public init() {}

    public func execute(_ task: MaintenanceTask) async -> TaskResult {
        if case .speedUpMail = task { return await reindexMail() }

        if task.requiresPrivilegedHelper {
            return TaskResult(
                task: task,
                success: false,
                output: "",
                error: "Needs administrator access — this task isn't available yet without the privileged helper."
            )
        }

        guard let (command, args) = task.systemCommand else {
            return TaskResult(task: task, success: false, output: "",
                              error: "Task has no system command")
        }
        return await runProcess(task: task, command: command, args: args)
    }

    private func runProcess(task: MaintenanceTask, command: String, args: [String]) async -> TaskResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(filePath: command)
        process.arguments = args
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8)

            return TaskResult(
                task: task,
                success: process.terminationStatus == 0,
                output: output,
                error: error?.isEmpty == true ? nil : error
            )
        } catch {
            return TaskResult(
                task: task,
                success: false,
                output: "",
                error: error.localizedDescription
            )
        }
    }

    private func reindexMail() async -> TaskResult {
        let mailEnvelopeIndex = MCConstants.mailData
            .appending(path: "V10/MailData/Envelope Index")

        let fm = FileManager.default
        if fm.fileExists(atPath: mailEnvelopeIndex.path(percentEncoded: false)) {
            do {
                try fm.removeItem(at: mailEnvelopeIndex)
                return TaskResult(
                    task: .speedUpMail,
                    success: true,
                    output: "Mail envelope index removed. Mail will rebuild it on next launch.",
                    error: nil
                )
            } catch {
                return TaskResult(
                    task: .speedUpMail,
                    success: false,
                    output: "",
                    error: error.localizedDescription
                )
            }
        }

        return TaskResult(
            task: .speedUpMail,
            success: true,
            output: "Mail envelope index not found — Mail may use a different version directory.",
            error: nil
        )
    }
}
