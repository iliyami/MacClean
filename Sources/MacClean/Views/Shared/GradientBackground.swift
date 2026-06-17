import SwiftUI

/// Neutral dark gradient used when "Remove background colors" is enabled
/// in Settings, replacing per-module themed gradients.
private let neutralGradient = LinearGradient(
    colors: [
        Color(red: 0.12, green: 0.12, blue: 0.14),
        Color(red: 0.16, green: 0.16, blue: 0.18),
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
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var buttonGradient: LinearGradient {
        LinearGradient(
            colors: buttonColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var colors: [Color] {
        switch self {
        case .smartScan:
            [Color(red: 0.22, green: 0.12, blue: 0.55), Color(red: 0.42, green: 0.25, blue: 0.82), Color(red: 0.55, green: 0.38, blue: 0.92)]
        case .cleanup:
            [Color(red: 0.06, green: 0.38, blue: 0.25), Color(red: 0.12, green: 0.55, blue: 0.35), Color(red: 0.22, green: 0.70, blue: 0.45)]
        case .protection:
            [Color(red: 0.60, green: 0.10, blue: 0.10), Color(red: 0.78, green: 0.22, blue: 0.18), Color(red: 0.90, green: 0.35, blue: 0.25)]
        case .performance:
            [Color(red: 0.72, green: 0.48, blue: 0.08), Color(red: 0.85, green: 0.60, blue: 0.12), Color(red: 0.92, green: 0.72, blue: 0.22)]
        case .applications:
            [Color(red: 0.38, green: 0.12, blue: 0.62), Color(red: 0.55, green: 0.25, blue: 0.78), Color(red: 0.68, green: 0.35, blue: 0.88)]
        case .files:
            [Color(red: 0.06, green: 0.38, blue: 0.52), Color(red: 0.10, green: 0.52, blue: 0.65), Color(red: 0.18, green: 0.65, blue: 0.78)]
        case .settings:
            [Color(red: 0.16, green: 0.17, blue: 0.21), Color(red: 0.26, green: 0.28, blue: 0.33), Color(red: 0.37, green: 0.39, blue: 0.45)]
        }
    }

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

    public var accentColor: Color {
        colors[1]
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
