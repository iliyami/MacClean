import Foundation
import MacCleanKit

public struct MaintenanceModule: ScanModule {
    public let id = "maintenance"
    public var name: String { L10n.tr("维护", "Maintenance") }
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

        guard let (command, args) = task.systemCommand else {
            return TaskResult(task: task, success: false, output: "",
                              error: L10n.tr("该任务没有可执行的系统命令", "Task has no system command"))
        }

        if task.requiresAdmin {
            return await runAdminProcess(task: task, command: command, args: args)
        }
        return await runProcess(task: task, command: command, args: args)
    }

    /// Run a root-requiring command via the standard macOS admin-auth prompt
    /// (`do shell script … with administrator privileges`). macOS shows its
    /// native password dialog and runs the command as root — no persistent
    /// privileged helper needed. The command strings come from the fixed
    /// `MaintenanceTask` enum (never user input); we still escape the
    /// AppleScript string literal defensively.
    private func runAdminProcess(task: MaintenanceTask, command: String, args: [String]) async -> TaskResult {
        // Each argv element is single-quoted (MaintenanceShell.quote) so sh
        // can't re-split or interpret it; the assembled command is then
        // escaped as an AppleScript string literal for `do shell script`.
        let shell = MaintenanceShell.commandLine(command, args)
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let result = await runProcess(task: task, command: "/usr/bin/osascript", args: ["-e", script])

        // osascript returns -128 / "User canceled." when the user dismisses
        // the auth dialog — surface that as a friendly note, not an error.
        if !result.success, let err = result.error {
            if err.contains("User canceled") || err.contains("-128") {
                return TaskResult(task: task, success: false, output: "",
                                  error: L10n.tr("已取消——未授予管理员权限。", "Cancelled — administrator access was not granted."))
            }
            // Otherwise strip osascript's "1:92: execution error: … (1)" wrapper
            // so the user sees the real underlying message (issue #82).
            return TaskResult(task: task, success: false, output: "",
                              error: MaintenanceShell.humanReadableError(err))
        }
        return result
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
                    output: L10n.tr("邮件索引已移除。邮件将在下次启动时重建。", "Mail envelope index removed. Mail will rebuild it on next launch."),
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
            output: L10n.tr("未找到邮件索引——邮件可能使用了不同的版本目录。", "Mail envelope index not found — Mail may use a different version directory."),
            error: nil
        )
    }
}
