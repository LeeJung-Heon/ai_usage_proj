import Foundation
import Testing
@testable import AgentMeterCore

@Test func dashboardFirstProviderPersistsAndMovesToFrontWithoutDuplicates() {
    let suite = "AgentMeterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = DashboardPreferences(defaults: defaults)

    #expect(preferences.providers == [.claude, .codex, .gemini, .antigravity])
    preferences.firstProvider = .codex
    let restored = DashboardPreferences(defaults: defaults)
    #expect(restored.firstProvider == .codex)
    #expect(restored.providers == [.codex, .claude, .gemini, .antigravity])

    restored.firstProvider = .gemini
    #expect(restored.providers == [.gemini, .codex, .claude, .antigravity])
}

@Test func dashboardInvalidSavedProviderFallsBackToDefaultOrder() {
    let suite = "AgentMeterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("unknown", forKey: "dashboardFirstProvider")
    #expect(DashboardPreferences(defaults: defaults).providers == [.claude, .codex, .gemini, .antigravity])
}

@Test func dashboardRestoresCompleteOrderAndPreservesLowerPositionsWhenPromoting() {
    let suite = "AgentMeterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["claude", "gemini", "codex"], forKey: "dashboardProviderOrder")
    defaults.set("codex", forKey: "dashboardFirstProvider")
    let preferences = DashboardPreferences(defaults: defaults)
    #expect(preferences.providers == [.claude, .gemini, .codex, .antigravity])
    #expect(preferences.firstProvider == .claude)
    preferences.firstProvider = .gemini
    #expect(DashboardPreferences(defaults: defaults).providers == [.gemini, .claude, .codex, .antigravity])
}

@Test func dashboardNormalizesDuplicateUnknownAndMissingSavedAgents() {
    let suite = "AgentMeterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["gemini", "unknown", "gemini"], forKey: "dashboardProviderOrder")
    #expect(DashboardPreferences(defaults: defaults).providers == [.gemini, .claude, .codex, .antigravity])
    defaults.set([], forKey: "dashboardProviderOrder")
    #expect(DashboardPreferences(defaults: defaults).providers == [.claude, .codex, .gemini, .antigravity])
}

@Test func dashboardMovesEveryAgentToEachPositionAndPersistsEntireOrder() {
    let suite = "AgentMeterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let cases: [(Provider, Int, [Provider])] = [
        (.claude, 0, [.claude, .codex, .gemini, .antigravity]),
        (.claude, 1, [.codex, .claude, .gemini, .antigravity]),
        (.claude, 2, [.codex, .gemini, .claude, .antigravity]),
        (.codex, 0, [.codex, .claude, .gemini, .antigravity]),
        (.codex, 1, [.claude, .codex, .gemini, .antigravity]),
        (.codex, 2, [.claude, .gemini, .codex, .antigravity]),
        (.gemini, 0, [.gemini, .claude, .codex, .antigravity]),
        (.gemini, 1, [.claude, .gemini, .codex, .antigravity]),
        (.gemini, 2, [.claude, .codex, .gemini, .antigravity])
    ]
    for (provider, index, expected) in cases {
        let preferences = DashboardPreferences(defaults: defaults)
        preferences.providers = [.claude, .codex, .gemini, .antigravity]
        preferences.moveProvider(provider, to: index)
        let restored = DashboardPreferences(defaults: defaults)
        #expect(restored.providers == expected)
        #expect(restored.firstProvider == expected.first)
    }
}

@Test func dashboardInvalidMovesLeaveOrderIntactAndWritesNormalizeDuplicates() {
    let suite = "AgentMeterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = DashboardPreferences(defaults: defaults)
    preferences.providers = [.codex, .codex, .gemini]
    #expect(preferences.providers == [.codex, .gemini, .claude, .antigravity])
    for index in [-1, 4, Int.max] { preferences.moveProvider(.codex, to: index) }
    #expect(DashboardPreferences(defaults: defaults).providers == [.codex, .gemini, .claude, .antigravity])
}

@Test func dashboardMigratesLegacyFirstProviderOnFirstReorder() {
    let suite = "AgentMeterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("gemini", forKey: "dashboardFirstProvider")
    let preferences = DashboardPreferences(defaults: defaults)
    #expect(preferences.providers == [.gemini, .claude, .codex, .antigravity])
    preferences.moveProvider(.codex, to: 1)
    #expect(DashboardPreferences(defaults: defaults).providers == [.gemini, .codex, .claude, .antigravity])
}
