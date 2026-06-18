import SwiftUI
import MacCleanKit

public struct ScanButton: View {
    let title: String
    let subtitle: String?
    let theme: ModuleTheme
    let isScanning: Bool
    let progress: Double
    let action: () -> Void

    public init(
        title: String = L10n.tr("扫描", "Scan"),
        subtitle: String? = nil,
        theme: ModuleTheme = .smartScan,
        isScanning: Bool = false,
        progress: Double = 0,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.isScanning = isScanning
        self.progress = progress
        self.action = action
    }

    public var body: some View {
        if isScanning {
            scanningContent
        } else {
            Button(action: action) {
                idleContent
            }
            .buttonStyle(SuperEllipseButtonStyle(
                gradient: theme.buttonGradient,
                size: CGSize(width: 160, height: 160)
            ))
        }
    }

    private var idleContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .opacity(0.7)
            }
        }
    }

    private var scanningContent: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.15), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(width: 100, height: 100)
        }
    }
}

public struct ScanProgressRing: View {
    let progress: Double
    let phase: String
    let detail: String?
    let theme: ModuleTheme

    public init(progress: Double, phase: String, detail: String? = nil, theme: ModuleTheme = .smartScan) {
        self.progress = progress
        self.phase = phase
        self.detail = detail
        self.theme = theme
    }

    public var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.12), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: progress)

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(width: 110, height: 110)

            VStack(spacing: 6) {
                Text(phase)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.interpolate)
                    .animation(.easeInOut(duration: 0.2), value: phase)

                if let detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.6))
                }
            }
        }
    }
}
