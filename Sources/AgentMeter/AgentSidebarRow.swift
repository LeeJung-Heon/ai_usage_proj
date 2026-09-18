import SwiftUI
import AgentMeterCore

/// Sidebar destinations. `nil` provider means the overview.
enum SidebarItem: Hashable {
    case overview
    case provider(Provider)

    var provider: Provider? {
        if case .provider(let provider) = self { return provider }
        return nil
    }
}

/// System sidebar: a `List` with selection, reordering via `onMove`, and the
/// accessible move actions the custom drag list used to provide.
struct DashboardSidebar: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { store.selection.map(SidebarItem.provider) ?? .overview },
            set: { store.selection = $0?.provider }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section("개요") {
                Label("전체 개요", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.overview)
            }
            Section {
                ForEach(store.orderedProviders) { provider in
                    AgentSidebarRow(provider: provider)
                        .tag(SidebarItem.provider(provider))
                }
                .onMove { source, destination in
                    guard let first = source.first else { return }
                    let target = destination > first ? destination - 1 : destination
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        store.moveProvider(store.orderedProviders[first], to: target)
                    }
                }
            } header: {
                Text("에이전트")
            } footer: {
                Text("드래그해 순서를 바꿉니다. 맨 위 에이전트를 메뉴 막대에 표시합니다.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }
}

struct AgentSidebarRow: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let provider: Provider

    private var index: Int { store.orderedProviders.firstIndex(of: provider) ?? 0 }
    private var quota: QuotaWindow? { MenuBarUsage(provider: provider, quotas: store.result.quotas, now: store.menuBarNow).quota }
    private var isConnected: Bool {
        if provider == .antigravity { return store.antigravityRefreshError == nil && quota != nil }
        return (store.result.sources.first { $0.provider == provider }?.eventCount ?? 0) > 0
    }

    var body: some View {
        HStack(spacing: 8) {
            ProviderLogo(provider: provider, size: 18)
            Text(provider.name)
            Spacer(minLength: 4)
            if index == 0 {
                Image(systemName: "menubar.rectangle")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("메뉴 막대에 표시 중")
                    .accessibilityHidden(true)
            }
            if let quota {
                Text("\(Int(quota.usedPercent))%")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(quota.usedPercent >= 90 ? Color.orange : Color.secondary)
                    .help("\(quota.label) 한도 \(Int(quota.usedPercent))% 사용")
                    .accessibilityHidden(true)
            }
        }
        .help("드래그하여 순서 변경 · 첫 번째 에이전트를 메뉴 막대에 표시")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.name)
        .accessibilityValue(positionDescription)
        .accessibilityHint("위로 이동, 아래로 이동 동작으로 순서를 바꿀 수 있습니다.")
        .accessibilityAction(named: "위로 이동") { move(to: index - 1) }
        .accessibilityAction(named: "아래로 이동") { move(to: index + 1) }
        .contextMenu {
            Button("위로 이동", systemImage: "arrow.up") { move(to: index - 1) }.disabled(index == 0)
            Button("아래로 이동", systemImage: "arrow.down") { move(to: index + 1) }.disabled(index == store.orderedProviders.count - 1)
            Divider()
            Button("메뉴 막대에 표시", systemImage: "menubar.rectangle") { move(to: 0) }.disabled(index == 0)
        }
    }

    private var positionDescription: String {
        var value = "\(index + 1)번째"
        if index == 0 { value += ", 메뉴 막대에 표시 중" }
        if let quota { value += ", \(quota.label) 한도 \(Int(quota.usedPercent))% 사용" }
        if !isConnected { value += ", 연결 대기" }
        return value
    }

    private func move(to index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            store.moveProvider(provider, to: index)
        }
    }
}
