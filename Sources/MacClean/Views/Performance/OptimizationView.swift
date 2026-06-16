import SwiftUI
import MacCleanKit

struct OptimizationView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var loginItems: [LoginItemsManager.LoginItem] = []
    @State private var launchAgents: [LaunchAgentsManager.LaunchAgent] = []
    @State private var selectedTab = 0
    @State private var isLoading = true

    private let loginManager = LoginItemsManager()
    private let agentManager = LaunchAgentsManager()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Optimization")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Manage startup items and background processes")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Loading items...")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
            } else {
                Picker("Section", selection: $selectedTab) {
                    Text("Login Items").tag(0)
                    Text("Launch Agents").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                Group {
                    if selectedTab == 0 {
                        loginItemsList
                    } else {
                        launchAgentsList
                    }
                }
                .background {
                    if removeBackgroundColors { Color.clear }
                    else { Rectangle().fill(.ultraThinMaterial) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .task { refresh() }
    }

    private var loginItemsList: some View {
        List {
            ForEach(loginItems, id: \.id) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 13, weight: .medium))
                        if let bid = item.bundleIdentifier {
                            Text(bid)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { item.isEnabled },
                        set: { newVal in
                            try? loginManager.toggleItem(item, enabled: newVal)
                            refresh()
                        }
                    ))
                    .toggleStyle(.switch)
                }
            }
        }
        .listStyle(.inset)
    }

    private var launchAgentsList: some View {
        List {
            ForEach(launchAgents, id: \.id) { agent in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.label)
                            .font(.system(size: 13, weight: .medium))
                        if let program = agent.program {
                            Text(program)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if agent.isSystem {
                        Text("System")
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .clipShape(Capsule())
                    } else {
                        Toggle("", isOn: Binding(
                            get: { agent.isEnabled },
                            set: { newVal in
                                try? agentManager.toggleAgent(agent, enabled: newVal)
                                refresh()
                            }
                        ))
                        .toggleStyle(.switch)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func refresh() {
        loginItems = loginManager.getLoginItems()
        launchAgents = agentManager.getLaunchAgents()
        isLoading = false
    }
}
