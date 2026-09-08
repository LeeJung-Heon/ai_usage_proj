import SwiftUI
import AgentMeterCore

@main
struct AgentMeterApp: App {
    @StateObject private var store = UsageStore()
    var body: some Scene {
        Window("Agent Meter", id: "dashboard") {
            DashboardView().environmentObject(store)
                .frame(minWidth: 1040, minHeight: 730)
        }
        .defaultSize(width: 1200, height: 860)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .newItem) {
                Button("사용량 새로고침") { Task { await store.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        MenuBarExtra {
            MenuSummary().environmentObject(store)
        } label: {
            Image(nsImage: ProviderLogo.menuBarLabel(for: store.firstProvider, title: store.menuBarUsage.title))
            .help(menuBarHelp(store.menuBarUsage))
            .accessibilityLabel(menuBarHelp(store.menuBarUsage))
        }
        .menuBarExtraStyle(.window)
        Settings { ConnectionSettings().environmentObject(store) }
    }

    private func menuBarHelp(_ usage: MenuBarUsage) -> String {
        guard let quota = usage.quota else { return "Agent Meter · \(store.firstProvider.name) · \(usage.title)" }
        let reset = quota.resetsAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "미정"
        return "Agent Meter · \(quota.provider.name) \(quota.label) 한도\n\(usage.title) (사용률 · 리셋까지 남은 시간)\n리셋: \(reset)\n기록 확인: \(quota.observedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
