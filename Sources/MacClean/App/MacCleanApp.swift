import SwiftUI
import AppKit

@main
struct MacCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("showMenuBarWidget") private var showMenuBarWidget = true
    @AppStorage("menuBarFirstLaunchDone") private var menuBarFirstLaunchDone = false
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 800, minHeight: 550)
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                }
                .onAppear {
                    if !hasCompletedOnboarding {
                        showOnboarding = true
                        hasCompletedOnboarding = true
                    }
                    syncMenuBarOnLaunch()
                }
                .onOpenURL { url in
                    // Expect exactly macclean://module/<slug> — one path
                    // segment (pathComponents is ["/", "<slug>"]). Reject
                    // malformed multi-segment URLs rather than guessing.
                    guard url.scheme == "macclean", url.host == "module",
                          url.pathComponents.count == 2,
                          let id = url.pathComponents.last,
                          let item = SidebarItem(deepLinkID: id) else { return }
                    appState.selectedSidebarItem = item
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 960, height: 620)

        Settings {
            SettingsView()
        }
    }

    /// First-launch default: ON (per product decision). On every launch
    /// we re-sync the SMAppService state with the preference so the
    /// truth of "is the helper actually running" matches the toggle —
    /// macOS occasionally drops registrations after updates, especially
    /// when the helper bundle path changes (which it doesn't here, but
    /// re-registering is cheap and idempotent).
    private func syncMenuBarOnLaunch() {
        if !menuBarFirstLaunchDone {
            menuBarFirstLaunchDone = true
            // showMenuBarWidget already defaults to true; setEnabled is
            // idempotent if already registered.
        }
        MenuBarLauncher.shared.setEnabled(showMenuBarWidget)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
