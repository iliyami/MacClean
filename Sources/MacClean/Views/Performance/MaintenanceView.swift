import SwiftUI
import MacCleanKit

struct MaintenanceView: View {
    @State private var taskStates: [MaintenanceTask: TaskState] = [:]
    @State private var executor = MaintenanceExecutor()
    /// When non-nil, the confirmation alert is presented for this task.
    @State private var taskAwaitingConfirmation: MaintenanceTask?

    enum TaskState {
        case idle
        case running
        case completed(String)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("维护", "Maintenance"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(L10n.tr("运行系统维护任务，让 Mac 保持健康", "Run system maintenance tasks to keep your Mac healthy"))
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.6))
                }
                Spacer()
                // Was "Run All" — but blanket-running every task in this
                // module hides hours-long Spotlight/Launch-Services
                // disruption behind a single click. Only fire-and-forget
                // safe tasks now; advanced ones require per-task consent.
                Button(L10n.tr("运行安全任务", "Run Safe Tasks")) { runSafeTasks() }
                    .buttonStyle(SuperEllipseButtonStyle(
                        gradient: ModuleTheme.performance.buttonGradient,
                        size: CGSize(width: 120, height: 34)
                    ))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(MaintenanceTask.allCases) { task in
                        taskRow(task)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .alert(
            L10n.tr("运行 \(taskAwaitingConfirmation?.title ?? "")？", "Run \(taskAwaitingConfirmation?.title ?? "")?"),
            isPresented: Binding(
                get: { taskAwaitingConfirmation != nil },
                set: { if !$0 { taskAwaitingConfirmation = nil } }
            ),
            presenting: taskAwaitingConfirmation
        ) { task in
            Button(L10n.tr("取消", "Cancel"), role: .cancel) {
                taskAwaitingConfirmation = nil
            }
            Button(L10n.tr("仍要运行", "Run Anyway"), role: .destructive) {
                let captured = task
                taskAwaitingConfirmation = nil
                runTask(captured)
            }
        } message: { task in
            Text(task.sideEffects)
        }
    }

    private func taskRow(_ task: MaintenanceTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: task.icon)
                .font(.system(size: 16))
                .foregroundStyle(.primary.opacity(0.75))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    if task.severity == .advanced {
                        Text(L10n.tr("高级", "ADVANCED"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                if case .failed(let message) = taskStates[task] {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.8))
                        .lineLimit(2)
                } else {
                    Text(task.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer()

            statusView(for: task)

            Button {
                didTapRun(task)
            } label: {
                Image(systemName: task.severity == .advanced
                      ? "exclamationmark.triangle.fill"
                      : "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(task.severity == .advanced
                                     ? Color.orange.opacity(0.85)
                                     : Color.primary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .disabled(isRunning(task))
            .help(task.severity == .advanced
                  ? L10n.tr("可能带来持续数小时的影响——将打开确认窗口", "Has multi-hour side effects — opens a confirmation")
                  : L10n.tr("运行此任务", "Run this task"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.primary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func statusView(for task: MaintenanceTask) -> some View {
        switch taskStates[task] {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(.primary)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(message)
        case .idle, .none:
            EmptyView()
        }
    }

    private func isRunning(_ task: MaintenanceTask) -> Bool {
        if case .running = taskStates[task] { return true }
        return false
    }

    /// Routes through the severity check: safe tasks run immediately,
    /// advanced tasks pop the confirmation alert first.
    private func didTapRun(_ task: MaintenanceTask) {
        switch task.severity {
        case .safe:
            runTask(task)
        case .advanced:
            taskAwaitingConfirmation = task
        }
    }

    private func executeAndStore(_ task: MaintenanceTask) async {
        taskStates[task] = .running
        let result = await executor.execute(task)
        if result.success {
            taskStates[task] = .completed(result.output)
        } else {
            taskStates[task] = .failed(result.error ?? L10n.tr("未知错误", "Unknown error"))
        }
    }

    private func runTask(_ task: MaintenanceTask) {
        Task { await executeAndStore(task) }
    }

    /// Bulk button runs ONLY safe tasks, and runs them SEQUENTIALLY. Several
    /// safe tasks need admin (purge, periodic); firing them in parallel popped
    /// multiple macOS password dialogs at once (issue #82). Awaiting each in
    /// turn means at most one auth prompt is on screen at a time.
    private func runSafeTasks() {
        let safeTasks = MaintenanceTask.allCases.filter { $0.severity == .safe }
        Task {
            for task in safeTasks {
                await executeAndStore(task)
            }
        }
    }
}
