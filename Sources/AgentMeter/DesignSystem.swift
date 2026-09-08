import SwiftUI

/// Shared surfaces keep the dashboard and the menu panel visually consistent.
enum MeterStyle {
    static let accent = Color(red: 0.12, green: 0.53, blue: 0.47)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let radius: CGFloat = 16
}

extension View {
    func meterCard(tint: Color? = nil) -> some View {
        background(MeterStyle.surface, in: RoundedRectangle(cornerRadius: MeterStyle.radius))
            .background {
                RoundedRectangle(cornerRadius: MeterStyle.radius)
                    .fill(.black.opacity(0.03))
                    .blur(radius: 8).offset(y: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: MeterStyle.radius)
                    .strokeBorder(tint?.opacity(0.22) ?? Color.primary.opacity(0.07))
            }
    }
}

struct MeterMark: View {
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: "chart.bar.xaxis")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(MeterStyle.accent.gradient, in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityLabel("Agent Meter")
    }
}
