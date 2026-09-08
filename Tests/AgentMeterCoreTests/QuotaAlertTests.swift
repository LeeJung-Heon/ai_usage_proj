import Foundation
import Testing
@testable import AgentMeterCore

private let alertNow = Date(timeIntervalSince1970: 1_800_000_000)

private func quota(_ percent: Double, provider: Provider = .codex, id: String = "primary",
                   observed: Date = alertNow, reset: Date? = alertNow.addingTimeInterval(3600)) -> QuotaWindow {
    QuotaWindow(id: id, provider: provider, label: "5시간", usedPercent: percent,
                resetsAt: reset, observedAt: observed, source: "test")
}

@MainActor
private func withAlertDefaults(_ body: (UserDefaults) async throws -> Void) async rethrows {
    let suite = "AgentMeterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try await body(defaults)
}

@Test @MainActor func quotaAlertTriggersAtNinetyAndSkipsRepeatedRefreshes() async {
    await withAlertDefaults { defaults in
        let monitor = QuotaAlertMonitor(defaults: defaults)
        var delivered: [Double] = []
        for percent in [89.9, 90, 95, 100] {
            _ = await monitor.check([quota(percent)], now: alertNow) { delivered.append($0.usedPercent) }
        }
        #expect(delivered == [90])
    }
}

@Test @MainActor func quotaAlertTracksEveryProviderAndWindowIndependently() async {
    await withAlertDefaults { defaults in
        let monitor = QuotaAlertMonitor(defaults: defaults)
        var delivered: [QuotaWindow] = []
        let windows = [quota(95, provider: .claude), quota(90), quota(100, provider: .gemini), quota(91, id: "weekly"), quota(95, provider: .antigravity)]
        _ = await monitor.check(windows, now: alertNow) { delivered.append($0) }
        _ = await monitor.check(windows, now: alertNow) { delivered.append($0) }
        #expect(delivered.count == 5)
        #expect(Set(delivered.map(\.provider)) == Set(Provider.allCases))
        #expect(delivered.filter { $0.provider == .codex }.count == 2)
    }
}

@Test @MainActor func quotaAlertRejectsStaleExpiredFutureAndInvalidRecords() async {
    await withAlertDefaults { defaults in
        let monitor = QuotaAlertMonitor(defaults: defaults)
        var delivered = 0
        let windows = [quota(95, id: "stale", observed: alertNow.addingTimeInterval(-901)),
                       quota(95, id: "expired", reset: alertNow),
                       quota(95, id: "future", observed: alertNow.addingTimeInterval(1)),
                       quota(.nan, id: "nan"), quota(.infinity, id: "infinite"), quota(-1, id: "negative")]
        _ = await monitor.check(windows, now: alertNow) { _ in delivered += 1 }
        #expect(delivered == 0)
        _ = await monitor.check([quota(90, observed: alertNow.addingTimeInterval(-900))], now: alertNow) { _ in delivered += 1 }
        #expect(delivered == 1)
    }
}

@Test @MainActor func quotaAlertPersistsAcrossRestartAndMissingSnapshots() async {
    await withAlertDefaults { defaults in
        var delivered = 0
        _ = await QuotaAlertMonitor(defaults: defaults).check([quota(90)], now: alertNow) { _ in delivered += 1 }
        let restarted = QuotaAlertMonitor(defaults: defaults)
        _ = await restarted.check([], now: alertNow) { _ in delivered += 1 }
        _ = await restarted.check([quota(95)], now: alertNow) { _ in delivered += 1 }
        #expect(delivered == 1)
    }
}

@Test @MainActor func quotaAlertRearmsAfterResetButNotFluctuationsWithinPeriod() async {
    await withAlertDefaults { defaults in
        let monitor = QuotaAlertMonitor(defaults: defaults)
        var delivered = 0
        for (offset, percent) in [(0.0, 90.0), (60, 80), (120, 95)] {
            let time = alertNow.addingTimeInterval(offset)
            _ = await monitor.check([quota(percent, observed: time)], now: time) { _ in delivered += 1 }
        }
        #expect(delivered == 1)
        let next = alertNow.addingTimeInterval(3601)
        _ = await monitor.check([quota(92, observed: next, reset: next.addingTimeInterval(3600))], now: next) { _ in delivered += 1 }
        #expect(delivered == 2)
    }
}

@Test @MainActor func quotaAlertWithoutResetRearmsOnlyAfterNewLowObservation() async {
    await withAlertDefaults { defaults in
        let monitor = QuotaAlertMonitor(defaults: defaults)
        var delivered = 0
        for (offset, percent) in [(0.0, 95.0), (-1, 20), (1, 95), (2, 20), (3, 90)] {
            _ = await monitor.check([quota(percent, observed: alertNow.addingTimeInterval(offset), reset: nil)],
                                    now: alertNow.addingTimeInterval(5)) { _ in delivered += 1 }
        }
        #expect(delivered == 2)
    }
}

@Test @MainActor func quotaAlertUsesNewestSnapshotInsteadOfOlderHighUsage() async {
    await withAlertDefaults { defaults in
        let monitor = QuotaAlertMonitor(defaults: defaults)
        var delivered = 0
        _ = await monitor.check([quota(95, observed: alertNow.addingTimeInterval(-1)), quota(10)], now: alertNow) { _ in delivered += 1 }
        #expect(delivered == 0)
    }
}

@Test @MainActor func quotaAlertRetriesFailedDeliveryWithoutRepeatingSuccessfulWindows() async {
    enum DeliveryError: Error { case unavailable }
    await withAlertDefaults { defaults in
        let monitor = QuotaAlertMonitor(defaults: defaults)
        var delivered: [String] = []
        let windows = [quota(90), quota(95, id: "weekly")]
        let first = await monitor.check(windows, now: alertNow) { window in
            if window.id == "primary" { throw DeliveryError.unavailable }
            delivered.append(window.id)
        }
        #expect(!first)
        let second = await QuotaAlertMonitor(defaults: defaults).check(windows, now: alertNow) { delivered.append($0.id) }
        #expect(second)
        #expect(delivered == ["weekly", "primary"])
    }
}

@Test @MainActor func quotaAlertDoesNotDuplicateWhileDeliveryIsInFlight() async {
    await withAlertDefaults { defaults in
        let monitor = QuotaAlertMonitor(defaults: defaults)
        var delivered = 0
        _ = await monitor.check([quota(90)], now: alertNow) { _ in
            delivered += 1
            _ = await monitor.check([quota(95)], now: alertNow) { _ in delivered += 1 }
        }
        #expect(delivered == 1)
    }
}
