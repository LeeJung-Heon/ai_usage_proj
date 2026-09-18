import SwiftUI

/// Shared surfaces keep the dashboard and the menu panel visually consistent.
/// Interactive tint follows the user's system accent colour; the teal mark is
/// reserved for the app identity only.
enum MeterStyle {
    static let brand = Color(red: 0.12, green: 0.53, blue: 0.47)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let radius: CGFloat = 10
    static let gutter: CGFloat = 20
    static let gap: CGFloat = 12
}

extension View {
    /// A flat, system-coloured group surface with a hairline separator border.
    func meterCard() -> some View {
        background(MeterStyle.surface, in: RoundedRectangle(cornerRadius: MeterStyle.radius))
            .overlay {
                RoundedRectangle(cornerRadius: MeterStyle.radius)
                    .strokeBorder(Color(nsColor: .separatorColor))
            }
    }
}

/// Section title with an optional trailing note, matching macOS content headers.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var trailing: Trailing

    init(_ title: String, note: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.note = note
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            if let note { Text(note).font(.subheadline).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            trailing
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct MeterMark: View {
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: "chart.bar.xaxis")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(MeterStyle.brand.gradient, in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityLabel("Agent Meter")
    }
}
