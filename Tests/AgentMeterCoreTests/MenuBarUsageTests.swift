import Foundation
import Testing
@testable import AgentMeterCore

private let menuNow = Date(timeIntervalSince1970: 1_800_000_000)

private func menuQuota(_ percent: Double, provider: Provider = .codex,
                       id: String = "codex:codex:primary", label: String = "5시간",
                       observed: Date = menuNow, reset: Date? = menuNow.addingTimeInterval(8100)) -> QuotaWindow {
    QuotaWindow(id: id, provider: provider, label: label, usedPercent: percent,
                resetsAt: reset, observedAt: observed, source: "test")
}

@Test func menuBarUsesSelectedProviderLatestPrimaryQuotaWithMatchingReset() {
    let quotas = [menuQuota(98, id: "codex:codex:secondary", label: "7일"),
                  menuQuota(10, observed: menuNow.addingTimeInterval(-60)),
                  menuQuota(42.9),
                  menuQuota(77, provider: .claude, id: "claude:five_hour")]
    let codex = MenuBarUsage(provider: .codex, quotas: quotas.reversed(), now: menuNow)
    #expect(codex.title == "42% · 2h 15m")
    #expect(codex.quota?.observedAt == menuNow)
    let claude = MenuBarUsage(provider: .claude, quotas: quotas, now: menuNow)
    #expect(claude.title == "77% · 2h 15m")
}

@Test func menuBarDoesNotBorrowAnotherProviderQuotaOrInventZeroUsage() {
    let missing = MenuBarUsage(provider: .claude, quotas: [menuQuota(50)], now: menuNow)
    #expect(missing.title == "— · 한도 대기")
    let unsupported = MenuBarUsage(provider: .gemini, quotas: [menuQuota(50)], now: menuNow)
    #expect(unsupported.title == "— · 한도 미지원")
    let zero = MenuBarUsage(provider: .codex, quotas: [menuQuota(0)], now: menuNow)
    #expect(zero.title == "0% · 2h 15m")
}

@Test func menuBarPreservesOldAndExpiredUsageWithoutAsterisk() {
    let old = MenuBarUsage(provider: .codex, quotas: [menuQuota(50, observed: menuNow.addingTimeInterval(-901))], now: menuNow)
    #expect(old.title == "50% · 2h 15m")
    let expired = MenuBarUsage(provider: .codex, quotas: [menuQuota(80, reset: menuNow)], now: menuNow)
    #expect(expired.title == "80% · 갱신 대기")
}

@Test func menuBarHandlesWeeklyFallbackMissingResetAndCountdownBoundaries() {
    let weekly = MenuBarUsage(provider: .claude, quotas: [
        menuQuota(63, provider: .claude, id: "claude:seven_day", label: "7일", reset: menuNow.addingTimeInterval(90000))
    ], now: menuNow)
    #expect(weekly.title == "63% · 1d 1h")
    #expect(weekly.quota?.label == "7일")
    let unknown = MenuBarUsage(provider: .codex, quotas: [menuQuota(20, reset: nil)], now: menuNow)
    #expect(unknown.title == "20% · 리셋 미정")
    for (seconds, expected) in [(1.0, "1m"), (60, "1m"), (61, "2m"), (3600, "1h 0m")] {
        let usage = MenuBarUsage(provider: .codex, quotas: [menuQuota(20, reset: menuNow.addingTimeInterval(seconds))], now: menuNow)
        #expect(usage.title == "20% · \(expected)")
    }
}

@Test func menuBarRejectsInvalidAndFuturePercentages() {
    for percent in [Double.nan, .infinity, -1] {
        let usage = MenuBarUsage(provider: .codex, quotas: [menuQuota(percent)], now: menuNow)
        #expect(usage.quota == nil)
    }
    let future = MenuBarUsage(provider: .codex, quotas: [menuQuota(70, observed: menuNow.addingTimeInterval(60))], now: menuNow)
    #expect(future.quota == nil)
}
