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

@Test func claudeQuotaFetchAddsModelScopedWeeklyWindowsAfterCoreWindows() async throws {
    let quotas = try await ClaudeQuotaClient.fetch(accessToken: "test-token", now: quotaNow) { _ in
        (Data(#"""
        {"five_hour":{"utilization":12,"resets_at":"2026-09-07T10:00:00Z"},
         "seven_day":{"utilization":18,"resets_at":"2026-09-08T02:00:00Z"},
         "limits":[
           {"kind":"session","group":"session","percent":12,"resets_at":"2026-09-07T10:00:00Z","scope":null},
           {"kind":"weekly_all","group":"weekly","percent":18,"resets_at":"2026-09-08T02:00:00Z","scope":null},
           {"kind":"weekly_scoped","group":"weekly","percent":74.5,"resets_at":"2026-09-09T00:00:00Z","scope":{"model":{"display_name":"Fable"}}},
           {"kind":"weekly_scoped","group":"weekly","percent":5,"resets_at":null,"scope":{"surface":{"display_name":"Cowork"}}}
         ]}
        """#.utf8), 200)
    }
    #expect(quotas.map(\.id) == ["claude:five_hour", "claude:seven_day", "claude:model:fable"])
    let fable = try #require(quotas.last)
    #expect(fable.label == "7일 · Fable")
    #expect(fable.usedPercent == 74.5)
    #expect(fable.resetsAt?.timeIntervalSince1970 == 1_788_912_000)
    #expect(fable.observedAt == quotaNow && fable.provider == .claude)
}

@Test func claudeQuotaFetchAllowsModelWindowWithoutResetAndSkipsInvalidRows() async throws {
    let quotas = try await ClaudeQuotaClient.fetch(accessToken: "test-token", now: quotaNow) { _ in
        (Data(#"""
        {"five_hour":{"utilization":1,"resets_at":null},
         "limits":[
           {"kind":"weekly_scoped","percent":-3,"resets_at":null,"scope":{"model":{"display_name":"Broken"}}},
           {"kind":"weekly_scoped","percent":40,"resets_at":"not-a-date","scope":{"model":{"display_name":"BadDate"}}},
           {"kind":"weekly_scoped","percent":"40","resets_at":null,"scope":{"model":{"display_name":"StringPercent"}}},
           {"kind":"weekly_scoped","percent":40,"resets_at":null,"scope":{"model":{"display_name":""}}},
           {"kind":"weekly_scoped","percent":66,"resets_at":null,"scope":{"model":{"display_name":"Fable"}}},
           "garbage"
         ]}
        """#.utf8), 200)
    }
    #expect(quotas.map(\.id) == ["claude:five_hour", "claude:model:fable"])
    #expect(quotas.last?.usedPercent == 66)
    #expect(quotas.last?.resetsAt == nil)
}

@Test func claudeQuotaFetchIgnoresAbsentOrNullLimitsArray() async throws {
    for payload in [#"{"five_hour":{"utilization":3,"resets_at":null}}"#, #"{"five_hour":{"utilization":3,"resets_at":null},"limits":null}"#, #"{"five_hour":{"utilization":3,"resets_at":null},"limits":[]}"#] {
        let quotas = try await ClaudeQuotaClient.fetch(accessToken: "test-token", now: quotaNow) { _ in (Data(payload.utf8), 200) }
        #expect(quotas.map(\.id) == ["claude:five_hour"])
    }
}
