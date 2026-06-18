import SwiftUI
import AppKit

extension Color {
    /// A color that resolves to `light` or `dark` based on the active
    /// appearance, so the same value renders correctly in both Light and Dark
    /// without threading `colorScheme` through every view.
    init(light: Color, dark: Color) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}

/// Neutral background used when "Remove background colors" is enabled in
/// Settings, replacing per-module themed gradients. Light-grey in Light mode,
/// near-black in Dark.
private let neutralGradient = LinearGradient(
    colors: [
        Color(light: Color(red: 0.95, green: 0.95, blue: 0.96), dark: Color(red: 0.12, green: 0.12, blue: 0.14)),
        Color(light: Color(red: 0.92, green: 0.92, blue: 0.94), dark: Color(red: 0.16, green: 0.16, blue: 0.18)),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

public enum ModuleTheme {
    case smartScan
    case cleanup
    case protection
    case performance
    case applications
    case files
    case settings

    public var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public var buttonGradient: LinearGradient {
        LinearGradient(colors: buttonColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Full-screen background gradient. Vivid in Dark, soft pastel in Light
    /// (so the adaptive `.primary`/`.secondary` text stays readable on it).
    public var colors: [Color] {
        switch self {
        case .smartScan:
            [Color(light: Color(red: 0.94, green: 0.91, blue: 0.99), dark: Color(red: 0.22, green: 0.12, blue: 0.55)),
             Color(light: Color(red: 0.90, green: 0.85, blue: 0.98), dark: Color(red: 0.42, green: 0.25, blue: 0.82)),
             Color(light: Color(red: 0.86, green: 0.80, blue: 0.97), dark: Color(red: 0.55, green: 0.38, blue: 0.92))]
        case .cleanup:
            [Color(light: Color(red: 0.90, green: 0.97, blue: 0.93), dark: Color(red: 0.06, green: 0.38, blue: 0.25)),
             Color(light: Color(red: 0.85, green: 0.95, blue: 0.89), dark: Color(red: 0.12, green: 0.55, blue: 0.35)),
             Color(light: Color(red: 0.80, green: 0.93, blue: 0.85), dark: Color(red: 0.22, green: 0.70, blue: 0.45))]
        case .protection:
            [Color(light: Color(red: 0.99, green: 0.92, blue: 0.91), dark: Color(red: 0.60, green: 0.10, blue: 0.10)),
             Color(light: Color(red: 0.99, green: 0.88, blue: 0.86), dark: Color(red: 0.78, green: 0.22, blue: 0.18)),
             Color(light: Color(red: 0.98, green: 0.84, blue: 0.82), dark: Color(red: 0.90, green: 0.35, blue: 0.25))]
        case .performance:
            [Color(light: Color(red: 0.99, green: 0.96, blue: 0.88), dark: Color(red: 0.72, green: 0.48, blue: 0.08)),
             Color(light: Color(red: 0.99, green: 0.94, blue: 0.82), dark: Color(red: 0.85, green: 0.60, blue: 0.12)),
             Color(light: Color(red: 0.99, green: 0.91, blue: 0.77), dark: Color(red: 0.92, green: 0.72, blue: 0.22))]
        case .applications:
            [Color(light: Color(red: 0.95, green: 0.91, blue: 0.99), dark: Color(red: 0.38, green: 0.12, blue: 0.62)),
             Color(light: Color(red: 0.92, green: 0.86, blue: 0.98), dark: Color(red: 0.55, green: 0.25, blue: 0.78)),
             Color(light: Color(red: 0.88, green: 0.82, blue: 0.97), dark: Color(red: 0.68, green: 0.35, blue: 0.88))]
        case .files:
            [Color(light: Color(red: 0.90, green: 0.96, blue: 0.98), dark: Color(red: 0.06, green: 0.38, blue: 0.52)),
             Color(light: Color(red: 0.85, green: 0.94, blue: 0.97), dark: Color(red: 0.10, green: 0.52, blue: 0.65)),
             Color(light: Color(red: 0.80, green: 0.92, blue: 0.96), dark: Color(red: 0.18, green: 0.65, blue: 0.78))]
        case .settings:
            [Color(light: Color(red: 0.96, green: 0.97, blue: 0.98), dark: Color(red: 0.16, green: 0.17, blue: 0.21)),
             Color(light: Color(red: 0.93, green: 0.94, blue: 0.96), dark: Color(red: 0.26, green: 0.28, blue: 0.33)),
             Color(light: Color(red: 0.90, green: 0.91, blue: 0.94), dark: Color(red: 0.37, green: 0.39, blue: 0.45))]
        }
    }

    /// Buttons stay vivid in both modes so their white labels remain legible.
    public var buttonColors: [Color] {
        switch self {
        case .smartScan:
            [Color(red: 0.35, green: 0.22, blue: 0.72), Color(red: 0.52, green: 0.35, blue: 0.88)]
        case .cleanup:
            [Color(red: 0.15, green: 0.52, blue: 0.35), Color(red: 0.28, green: 0.68, blue: 0.45)]
        case .protection:
            [Color(red: 0.75, green: 0.20, blue: 0.18), Color(red: 0.88, green: 0.35, blue: 0.25)]
        case .performance:
            [Color(red: 0.82, green: 0.58, blue: 0.12), Color(red: 0.92, green: 0.70, blue: 0.22)]
        case .applications:
            [Color(red: 0.52, green: 0.22, blue: 0.72), Color(red: 0.68, green: 0.35, blue: 0.85)]
        case .files:
            [Color(red: 0.12, green: 0.50, blue: 0.62), Color(red: 0.22, green: 0.62, blue: 0.75)]
        case .settings:
            [Color(red: 0.30, green: 0.32, blue: 0.38), Color(red: 0.42, green: 0.44, blue: 0.51)]
        }
    }

    /// Accent for icons/highlights. Kept vivid (independent of the now-adaptive
    /// background) so it has contrast on both the light sidebar and dark panels.
    public var accentColor: Color {
        switch self {
        case .smartScan: Color(red: 0.42, green: 0.25, blue: 0.82)
        case .cleanup: Color(red: 0.12, green: 0.55, blue: 0.35)
        case .protection: Color(red: 0.78, green: 0.22, blue: 0.18)
        case .performance: Color(red: 0.78, green: 0.52, blue: 0.10)
        case .applications: Color(red: 0.55, green: 0.25, blue: 0.78)
        case .files: Color(red: 0.10, green: 0.52, blue: 0.65)
        case .settings: Color(red: 0.40, green: 0.42, blue: 0.49)
        }
    }
}

public struct GradientBackgroundView: View {
    let theme: ModuleTheme
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false

    public init(theme: ModuleTheme) {
        self.theme = theme
    }

    public var body: some View {
        if removeBackgroundColors {
            neutralGradient
        } else {
            theme.gradient
        }
    }
}
