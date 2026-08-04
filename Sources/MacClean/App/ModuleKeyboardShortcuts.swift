import SwiftUI

/// Marks whether this module view is the currently selected sidebar item.
/// Visited (kept-alive) views stay in the hierarchy at opacity 0 — they must
/// ignore global ⌘R / ⌘K unless selected.
private enum ModuleIsSelectedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var moduleIsSelected: Bool {
        get { self[ModuleIsSelectedKey.self] }
        set { self[ModuleIsSelectedKey.self] = newValue }
    }
}

/// Relays AppState shortcut nonces into scan/clean actions for the focused module.
struct RespondsToModuleShortcuts: ViewModifier {
    @Environment(AppState.self) private var appState
    @Environment(\.moduleIsSelected) private var isSelected
    let onScan: () -> Void
    let onClean: (() -> Void)?
    let canScan: Bool
    let canClean: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: appState.scanShortcutNonce) { _, _ in
                guard isSelected, canScan else { return }
                onScan()
            }
            .onChange(of: appState.cleanShortcutNonce) { _, _ in
                guard isSelected, canClean, let onClean else { return }
                onClean()
            }
    }
}

extension View {
    func respondsToModuleShortcuts(
        onScan: @escaping () -> Void,
        onClean: (() -> Void)? = nil,
        canScan: Bool = true,
        canClean: Bool = false
    ) -> some View {
        modifier(RespondsToModuleShortcuts(
            onScan: onScan,
            onClean: onClean,
            canScan: canScan,
            canClean: canClean
        ))
    }
}

/// Who handles ⌘K for Duplicates when both the outer view and ModuleContainerView
/// listen to `cleanShortcutNonce`. Outer always declines; the container owns clean
/// whenever results (or completion) are on screen.
enum DuplicatesShortcutOwnership {
    enum CleanOwner: Equatable {
        case none
        case container
    }

    /// Outer `DuplicatesView` must never accept ⌘K — ModuleContainerView already does.
    static let outerCanClean = false

    static func cleanOwner(showingContainerResults: Bool) -> CleanOwner {
        showingContainerResults ? .container : .none
    }
}
