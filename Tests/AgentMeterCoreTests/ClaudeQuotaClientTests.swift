import Foundation
import Testing
@testable import AgentMeterCore

private let quotaNow = Date(timeIntervalSince1970: 1_788_770_000)

@Test func claudeQuotaFetchReplacesOldCaptureWithCurrentServerObservation() async throws {
    let quotas = try await ClaudeQuotaClient.fetch(accessToken: "test-token", now: quotaNow) { request in
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        return (Data(#"{"five_hour":{"utilization":12,"resets_at":"2026-09-07T10:00:00.123456+00:00"},"seven_day":{"utilization":18,"resets_at":"2026-09-08T02:00:00Z"}}"#.utf8), 200)
    }
    #expect(quotas.map(\.usedPercent) == [12, 18])
    #expect(quotas.map(\.id) == ["claude:five_hour", "claude:seven_day"])
    #expect(quotas.allSatisfy { $0.observedAt == quotaNow && $0.provider == .claude })
    let reset = try #require(quotas.first?.resetsAt?.timeIntervalSince1970)
    #expect(abs(reset - 1_788_775_200.123456) < 0.001)
}

@Test func claudeQuotaFetchAcceptsZeroAndAbsentResetWithoutInventingWindows() async throws {
    let quotas = try await ClaudeQuotaClient.fetch(accessToken: "test-token", now: quotaNow) { _ in
        (Data(#"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":null}"#.utf8), 200)
    }
    #expect(quotas.count == 1)
    #expect(quotas.first?.usedPercent == 0)
    #expect(quotas.first?.resetsAt == nil)
}

@Test func claudeQuotaFetchRejectsErrorsInsteadOfReportingFreshEmptyUsage() async {
    for status in [401, 403, 429, 500] {
        await #expect(throws: (any Error).self) {
            _ = try await ClaudeQuotaClient.fetch(accessToken: "test-token", now: quotaNow) { _ in
                (Data(#"{"error":"private diagnostic"}"#.utf8), status)
            }
        }
    }
    for payload in ["{}", "not json", #"{"five_hour":{"utilization":-1}}"#, #"{"five_hour":{"utilization":10,"resets_at":"bad-date"}}"#] {
        await #expect(throws: (any Error).self) {
            _ = try await ClaudeQuotaClient.fetch(accessToken: "test-token", now: quotaNow) { _ in
                (Data(payload.utf8), 200)
            }
        }
    }
}

@Test func claudeQuotaFetchRejectsMissingCredentialBeforeNetworkRequest() async {
    await #expect(throws: (any Error).self) {
        _ = try await ClaudeQuotaClient.fetch(accessToken: "", now: quotaNow) { _ in
            Issue.record("Missing credentials must not cause an HTTP request")
            return (Data(), 200)
        }
    }
}
