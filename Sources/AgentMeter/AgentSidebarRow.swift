import SwiftUI
import AgentMeterCore

/// A local gesture keeps reordering independent of macOS pasteboard drag sessions.
struct AgentSidebarList: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var drag: AgentListDrag?
    private let rowHeight: CGFloat = 44
    private let spacing: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: spacing) {
                ForEach(store.orderedProviders) { provider in
                    AgentSidebarRow(provider: provider, isTargeted: drag?.target == provider)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 5, coordinateSpace: .named("agent-list"))
                                .updating($drag) { value, state, _ in
                                    let index = destination(at: value.location, width: geometry.size.width)
                                    state = AgentListDrag(provider: provider, translation: value.translation,
                                                          target: index.map { store.orderedProviders[$0] })
                                }
                                .onEnded { value in
                                    guard let index = destination(at: value.location, width: geometry.size.width) else { return }
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                        store.moveProvider(provider, to: index)
                                    }
                                }
                        )
                        .offset(y: drag?.provider == provider ? drag?.translation.height ?? 0 : 0)
                        .zIndex(drag?.provider == provider ? 1 : 0)
                        .opacity(drag?.provider == provider ? 0.85 : 1)
                }
            }.coordinateSpace(name: "agent-list")
        }
        .frame(height: CGFloat(store.orderedProviders.count) * (rowHeight + spacing) - spacing)
    }

    private func destination(at location: CGPoint, width: CGFloat) -> Int? {
        let height = CGFloat(store.orderedProviders.count) * (rowHeight + spacing) - spacing
        guard location.x >= 0, location.x <= width, location.y >= 0, location.y < height else { return nil }
        return Int(location.y / (rowHeight + spacing))
    }
}

private struct AgentListDrag {
    let provider: Provider
    let translation: CGSize
    let target: Provider?
}

struct AgentSidebarRow: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let provider: Provider
    @State private var isHovered = false
    var isTargeted = false

    private var index: Int { store.orderedProviders.firstIndex(of: provider) ?? 0 }
    private var isSelected: Bool { store.selection == provider }

    var body: some View {
        rowContent
        .onTapGesture { store.selection = provider }
        .focusable()
        .onKeyPress(.return) { store.selection = provider; return .handled }
        .onKeyPress(.space) { store.selection = provider; return .handled }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.selection = provider }
        .help("드래그하여 순서 변경 · 첫 번째 에이전트를 메뉴 막대에 표시")
        .accessibilityLabel(provider.name)
        .accessibilityValue(positionDescription)
        .accessibilityHint("드래그하거나 위로 이동, 아래로 이동 동작으로 순서를 바꿀 수 있습니다.")
        .accessibilityAction(named: "위로 이동") { move(provider, to: index - 1) }
        .accessibilityAction(named: "아래로 이동") { move(provider, to: index + 1) }
        .contextMenu {
            Button("위로 이동", systemImage: "arrow.up") { move(provider, to: index - 1) }.disabled(index == 0)
            Button("아래로 이동", systemImage: "arrow.down") { move(provider, to: index + 1) }.disabled(index == store.orderedProviders.count - 1)
            Divider()
            Button("메뉴 막대에 표시", systemImage: "menubar.rectangle") { move(provider, to: 0) }.disabled(index == 0)
        }
    }

    private var positionDescription: String {
        var value = "\(index + 1)번째"
        if index == 0 { value += ", 메뉴 막대에 표시 중" }
        if isSelected { value += ", 선택됨" }
        return value
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
                ProviderLogo(provider: provider, size: 20)
                Text(provider.name).font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 2)
                if index == 0 {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 10)).foregroundStyle(MeterStyle.accent)
                        .help("메뉴 막대에 표시 중")
                }
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isHovered || isTargeted ? Color.secondary : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 12).frame(height: 44)
            .contentShape(RoundedRectangle(cornerRadius: 11))
            .background(isTargeted ? MeterStyle.accent.opacity(0.18) : isSelected ? MeterStyle.accent.opacity(0.11) : Color.primary.opacity(isHovered ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(isTargeted ? MeterStyle.accent : .clear, lineWidth: 1.5)
            }
    }

    private func move(_ provider: Provider, to index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            store.moveProvider(provider, to: index)
        }
    }
}
