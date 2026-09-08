import Foundation

@MainActor
public final class QuotaAlertMonitor {
    private struct State: Codable {
        var observedAt: Date
        var resetsAt: Date?
        var notified = false
    }
    private let defaults: UserDefaults
    private let storageKey = "quotaAlertHistory.v1"
    private var states: [String: State]
    private var isChecking = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        states = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: State].self, from: $0) } ?? [:]
    }

    /// Returns false when a delivery fails; unsuccessful windows remain eligible for retry.
    public func check(_ quotas: [QuotaWindow], now: Date = Date(),
                      send: (QuotaWindow) async throws -> Void) async -> Bool {
        guard !isChecking else { return true }
        isChecking = true
        defer { isChecking = false }
        var newest: [String: QuotaWindow] = [:]
        for quota in quotas {
            let key = quota.provider.rawValue + ":" + quota.id
            if newest[key].map({ $0.observedAt > quota.observedAt }) == true { continue }
            newest[key] = quota
        }
        var succeeded = true
        for key in newest.keys.sorted() {
            guard let quota = newest[key], quota.usedPercent.isFinite, quota.usedPercent >= 0,
                  quota.observedAt <= now, !quota.isStale(at: now) else { continue }
            var state = states[key] ?? State(observedAt: quota.observedAt, resetsAt: quota.resetsAt)
            guard quota.observedAt >= state.observedAt else { continue }

            if let reset = state.resetsAt, quota.observedAt >= reset {
                state = State(observedAt: quota.observedAt, resetsAt: quota.resetsAt)
            } else if state.resetsAt == nil, quota.observedAt > state.observedAt, quota.usedPercent < 90 {
                // Without a reset timestamp, a new low observation rearms the threshold.
                state.notified = false
            }
            state.observedAt = quota.observedAt
            // Missing reset metadata must not erase a known period and cause duplicates.
            if state.resetsAt == nil { state.resetsAt = quota.resetsAt }
            states[key] = state

            if quota.usedPercent >= 90, !state.notified {
                do {
                    try await send(quota)
                    state.notified = true
                    states[key] = state
                } catch { succeeded = false }
            }
            if let data = try? JSONEncoder().encode(states) { defaults.set(data, forKey: storageKey) }
        }
        return succeeded
    }
}
