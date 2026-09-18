import Foundation
import Testing
@testable import AgentMeterCore

private let codexNow = Date(timeIntervalSince1970: 1_789_700_000)

@Test func codexQuotaFetchMapsPrimarySecondaryAndAdditionalWindowsWithLogCompatibleIDs() async throws {
    let quotas = try await CodexQuotaClient.fetch(accessToken: "codex-token", accountID: "acct-1", now: codexNow) { request in
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer codex-token")
        #expect(request.value(forHTTPHeaderField: "chatgpt-account-id") == "acct-1")
        #expect(request.httpBody == nil)
        return (Data(#"""
        {"email":"private@example.com","plan_type":"prolite",
         "rate_limit":{"allowed":true,"limit_reached":false,
           "primary_window":{"used_percent":79,"limit_window_seconds":604800,"reset_after_seconds":241305,"reset_at":1789951945},
           "secondary_window":{"used_percent":12.5,"limit_window_seconds":18000,"reset_after_seconds":100,"reset_at":1789700100}},
         "additional_rate_limits":[
           {"limit_name":"gpt-reserve","rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":604800,"reset_at":1790315441},"secondary_window":null}}
         ]}
        """#.utf8), 200)
    }
    #expect(quotas.map(\.id) == ["codex:codex:primary", "codex:codex:secondary", "codex:gpt-reserve:primary"])
    #expect(quotas.map(\.label) == ["7일", "5시간", "gpt-reserve · 7일"])
    #expect(quotas.map(\.usedPercent) == [79, 12.5, 0])
    #expect(quotas.map { $0.resetsAt?.timeIntervalSince1970 } == [1_789_951_945, 1_789_700_100, 1_790_315_441])
    #expect(quotas.allSatisfy { $0.provider == .codex && $0.observedAt == codexNow && $0.source == "Codex 계정 조회" })
}

@Test func codexQuotaFetchAcceptsNullSecondaryAndSkipsInvalidWindows() async throws {
    let quotas = try await CodexQuotaClient.fetch(accessToken: "t", accountID: "a", now: codexNow) { _ in
        (Data(#"""
        {"rate_limit":{"primary_window":{"used_percent":40,"limit_window_seconds":43200,"reset_at":null},"secondary_window":null},
         "additional_rate_limits":[
           {"limit_name":"broken","rate_limit":{"primary_window":{"used_percent":-1,"limit_window_seconds":604800}}},
           {"limit_name":"","rate_limit":{"primary_window":{"used_percent":5,"limit_window_seconds":604800}}},
           {"rate_limit":{"primary_window":{"used_percent":5,"limit_window_seconds":604800}}},
           "garbage"
         ]}
        """#.utf8), 200)
    }
    #expect(quotas.map(\.id) == ["codex:codex:primary"])
    #expect(quotas.first?.label == "12시간")
    #expect(quotas.first?.resetsAt == nil)
}

@Test func codexQuotaFetchRejectsErrorsAndBodiesWithoutRateLimit() async {
    for status in [401, 403, 429, 500] {
        await #expect(throws: (any Error).self) {
            _ = try await CodexQuotaClient.fetch(accessToken: "t", accountID: "a", now: codexNow) { _ in
                (Data(#"{"detail":"private"}"#.utf8), status)
            }
        }
    }
    for payload in ["{}", "not json", #"{"rate_limit":null}"#, #"{"rate_limit":{"primary_window":{"used_percent":"79"}}}"#] {
        await #expect(throws: (any Error).self) {
            _ = try await CodexQuotaClient.fetch(accessToken: "t", accountID: "a", now: codexNow) { _ in
                (Data(payload.utf8), 200)
            }
        }
    }
}

@Test func codexQuotaFetchRejectsMissingCredentialsBeforeNetworkRequest() async {
    for (token, account) in [("", "a"), ("t", ""), ("  ", "a")] {
        await #expect(throws: (any Error).self) {
            _ = try await CodexQuotaClient.fetch(accessToken: token, accountID: account, now: codexNow) { _ in
                Issue.record("Missing credentials must not cause an HTTP request")
                return (Data(), 200)
            }
        }
    }
}

@Test func codexAuthParsesChatGPTLoginOnly() throws {
    let auth = try CodexAuth.parse(Data(#"{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{"id_token":"x","access_token":"acc","refresh_token":"r","account_id":"acct"},"last_refresh":"2026-09-18T00:00:00Z"}"#.utf8))
    #expect(auth.accessToken == "acc")
    #expect(auth.accountID == "acct")
    for payload in [
        #"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-x","tokens":null}"#,
        #"{"auth_mode":"chatgpt","tokens":{"access_token":"","account_id":"acct"}}"#,
        #"{"auth_mode":"chatgpt","tokens":{"access_token":"acc"}}"#,
        "not json"
    ] {
        #expect(throws: (any Error).self) { _ = try CodexAuth.parse(Data(payload.utf8)) }
    }
}
