import SwiftUI
import MacCleanKit

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Spacer()

            // Step content
            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                fdaStep.tag(1)
                featuresStep.tag(2)
                readyStep.tag(3)
            }
            .tabViewStyle(.automatic)

            Spacer()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button(L10n.tr("返回", "Back")) { withAnimation { currentStep -= 1 } }
                        .buttonStyle(.bordered)
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentStep < 3 {
                    Button(L10n.tr("下一步", "Next")) { withAnimation { currentStep += 1 } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(L10n.tr("开始使用", "Get Started")) { isPresented = false }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        // Was 600x450; the FDA step's full content (icon + title + body
        // + 4 numbered steps + "Open System Settings" button) exceeded
        // that and clipped the Back/Next buttons at the bottom of the
        // sheet on real installs. 620 height gives every step room
        // without becoming an empty-looking sheet on shorter steps.
        .frame(width: 600, height: 620)
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text(L10n.tr("欢迎使用 \(MCConstants.appName)", "Welcome to \(MCConstants.appName)"))
                .font(.system(size: 28, weight: .bold))

            Text(L10n.tr("以开源方式让你的 Mac 保持干净、快速和安全。", "The open-source way to keep your Mac clean, fast, and secure."))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

    private var fdaStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 50))
                .foregroundStyle(.blue)

            Text(L10n.tr("完全磁盘访问权限", "Full Disk Access"))
                .font(.system(size: 24, weight: .bold))

            Text(L10n.tr("\(MCConstants.appName) 需要完全磁盘访问权限，才能扫描邮件、Safari 和其他受保护区域。未授予时，部分功能会受限。", "\(MCConstants.appName) needs Full Disk Access to scan Mail, Safari, and other protected areas. Without it, some features will be limited."))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 8) {
                step("1", L10n.tr("打开系统设置", "Open System Settings"))
                step("2", L10n.tr("前往“隐私与安全性 → 完全磁盘访问权限”", "Go to Privacy & Security → Full Disk Access"))
                step("3", L10n.tr("点击 + 按钮并添加 \(MCConstants.appName)", "Click the + button and add \(MCConstants.appName)"))
                step("4", L10n.tr("重新启动 \(MCConstants.appName)", "Restart \(MCConstants.appName)"))
            }
            .padding()
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button(L10n.tr("打开系统设置", "Open System Settings")) {
                PermissionManager.shared.openFullDiskAccessSettings()
            }
            .buttonStyle(.bordered)
        }
    }

    private var featuresStep: some View {
        VStack(spacing: 20) {
            Text(L10n.tr("\(MCConstants.appName) 可以做什么", "What \(MCConstants.appName) Can Do"))
                .font(.system(size: 24, weight: .bold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                featureCard("trash.circle", L10n.tr("系统垃圾", "System Junk"), L10n.tr("清理缓存、日志和临时文件", "Clean caches, logs, and temp files"))
                featureCard("shield.lefthalf.filled", L10n.tr("恶意软件扫描", "Malware Scan"), L10n.tr("检测并移除威胁", "Detect and remove threats"))
                featureCard("xmark.app", L10n.tr("卸载器", "Uninstaller"), L10n.tr("彻底移除应用", "Completely remove apps"))
                featureCard("chart.pie", L10n.tr("空间透视", "Space Lens"), L10n.tr("可视化磁盘使用情况", "Visualize disk usage"))
                featureCard("plus.square.on.square", L10n.tr("重复文件", "Duplicates"), L10n.tr("查找重复文件", "Find duplicate files"))
                featureCard("gauge.with.dots.needle.67percent", L10n.tr("性能", "Performance"), L10n.tr("优化你的 Mac", "Optimize your Mac"))
            }
            .frame(maxWidth: 450)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text(L10n.tr("一切就绪！", "You're All Set!"))
                .font(.system(size: 28, weight: .bold))

            Text(L10n.tr("点击“智能扫描”即可一键清理 Mac，也可以在侧边栏探索各个模块。", "Click Smart Scan to clean your Mac with one click, or explore individual modules in the sidebar."))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor)
                .foregroundStyle(.primary)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
        }
    }

    private func featureCard(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(desc).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
