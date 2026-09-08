import Foundation

public actor AntigravityQuotaMonitor {
    public struct Snapshot: Sendable {
        public var quotas: [QuotaWindow] = []
        public var error: String?
    }
    private var snapshot = Snapshot()
    public init() {}
    public func refresh(fetch: @Sendable () async throws -> [QuotaWindow] = { try await AntigravityDiscovery.fetchQuotas() }) async -> Snapshot {
        do {
            snapshot.quotas = try await fetch()
            snapshot.error = nil
        } catch {
            // A failed refresh must not advance the observation time of cached quotas.
            snapshot.error = (error as? AntigravityQuotaError ?? .unavailable).localizedDescription
        }
        return snapshot
    }
}
