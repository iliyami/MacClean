import SwiftUI
import AppKit
import MacCleanKit

@main
struct MacCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("showMenuBarWidget") private var showMenuBarWidget = true
    @AppStorage("menuBarFirstLaunchDone") private var menuBarFirstLaunchDone = false
    @AppStorage(AppLanguage.defaultsKey, store: SharedAppState.defaults) private var appLanguageRaw = AppLanguage.system.rawValue
    @State private var showOnboarding = false

    init() {
        AppLanguage.registerDefault(.system)
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .fallback
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
                .id(appLanguage.rawValue)
                .frame(minWidth: 800, minHeight: 550)
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                        .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
                        .id(appLanguage.rawValue)
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
        // Keep the standard "Settings…" menu item + Cmd-comma, but route
        // them to the in-app page (the separate Settings window is gone).
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.tr("设置…", "Settings…")) {
                    appState.selectedSidebarItem = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
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
        // Async: the SMAppService XPC round-trip must not block app launch.
        Task { await MenuBarLauncher.shared.setEnabled(showMenuBarWidget) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceManager.applyStored()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
