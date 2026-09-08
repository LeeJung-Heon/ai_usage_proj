import Foundation
import Testing
@testable import AgentMeterCore

@Test func antigravityIsAddedToExistingSavedOrder() throws {
    let provider = try #require(Provider(rawValue: "antigravity"))
    let suite = "AgentMeterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["gemini", "codex", "claude"], forKey: "dashboardProviderOrder")
    let preferences = DashboardPreferences(defaults: defaults)
    #expect(preferences.providers.map(\.rawValue) == ["gemini", "codex", "claude", "antigravity"])
    preferences.firstProvider = provider
    #expect(DashboardPreferences(defaults: defaults).providers.map(\.rawValue) == ["antigravity", "gemini", "codex", "claude"])
}

private let agNow = Date(timeIntervalSince1970: 1_788_825_600)
private let summaryPayload = #"{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-weekly","displayName":"Weekly Limit Remaining","window":"weekly","remainingFraction":0.75,"resetTime":"2026-09-11T07:43:23Z"}]},{"displayName":"Claude and GPT models","buckets":[{"bucketId":"3p-weekly","window":"weekly","remainingFraction":1,"resetTime":"2026-09-15T00:19:19.123Z"}]}]}}"#

@Test func antigravityConvertsSharedQuotaRemainingToUsedWithoutInventingTokens() async throws {
    let quotas = try await AntigravityQuotaClient.fetch(port: 12345, csrfToken: "test-token", now: agNow) { request in
        #expect(request.url?.absoluteString == "http://127.0.0.1:12345/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Codeium-Csrf-Token") == "test-token")
        #expect(request.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        return (Data(summaryPayload.utf8), 200)
    }
    #expect(quotas.map(\.id) == ["antigravity:bucket:gemini-weekly", "antigravity:bucket:3p-weekly"])
    #expect(quotas.map(\.usedPercent) == [25, 0])
    #expect(quotas.map(\.label) == ["Gemini Models · 7일", "Claude and GPT models · 7일"])
    #expect(quotas.allSatisfy { $0.observedAt == agNow && $0.provider == .antigravity && $0.resetsAt != nil })
}

@Test func antigravityFallsBackToModelQuotasOnlyWhenSummaryIsUnsupported() async throws {
    let quotas = try await AntigravityQuotaClient.fetch(port: 12345, csrfToken: "test", now: agNow) { request in
        if request.url?.lastPathComponent == "RetrieveUserQuotaSummary" { return (Data(), 404) }
        #expect(request.url?.lastPathComponent == "GetUserStatus")
        return (Data(#"{"userStatus":{"cascadeModelConfigData":{"clientModelConfigs":[{"label":"Gemini Pro","modelId":"gemini-pro","quotaInfo":{"remainingFraction":0.5}},{"label":"Unavailable"}]}}}"#.utf8), 200)
    }
    #expect(quotas.count == 1)
    #expect(quotas.first?.id == "antigravity:model:gemini-pro")
    #expect(quotas.first?.usedPercent == 50)
    #expect(quotas.first?.resetsAt == nil)
}

@Test func antigravityRejectsMalformedQuotaInsteadOfClaimingFreshZeroUsage() async {
    for payload in ["{}", "not json", #"{"response":{"groups":[]}}"#,
                    #"{"response":{"groups":[{"displayName":"Group","buckets":[{"bucketId":"a","remainingFraction":true}]}]}}"#,
                    #"{"response":{"groups":[{"displayName":"Group","buckets":[{"bucketId":"a","remainingFraction":1.1}]}]}}"#,
                    #"{"response":{"groups":[{"displayName":"Group","buckets":[{"bucketId":"a","remainingFraction":-0.1}]}]}}"#,
                    #"{"response":{"groups":[{"displayName":"Group","buckets":[{"bucketId":"a","remainingFraction":0.5,"resetTime":"bad"}]}]}}"#] {
        await #expect(throws: (any Error).self) {
            _ = try await AntigravityQuotaClient.fetch(port: 12345, csrfToken: "test") { _ in (Data(payload.utf8), 200) }
        }
    }
}

@Test func antigravityAcceptsProtobufOmittedZeroOnlyWithResetEvidence() async throws {
    let quotas = try await AntigravityQuotaClient.fetch(port: 12345, csrfToken: "test") { _ in
        (Data(#"{"response":{"groups":[{"displayName":"Group","buckets":[{"bucketId":"empty","resetTime":"2026-09-11T07:43:23Z"}]}]}}"#.utf8), 200)
    }
    #expect(quotas.first?.usedPercent == 100)
    await #expect(throws: (any Error).self) {
        _ = try await AntigravityQuotaClient.fetch(port: 12345, csrfToken: "test") { _ in
            (Data(#"{"response":{"groups":[{"displayName":"Group","buckets":[{"bucketId":"empty"}]}]}}"#.utf8), 200)
        }
    }
}

@Test func antigravityRejectsInvalidConnectionAndHTTPFailure() async {
    for (port, token) in [(0, "test"), (65536, "test"), (12345, ""), (12345, "bad\r\nheader")] {
        await #expect(throws: (any Error).self) {
            _ = try await AntigravityQuotaClient.fetch(port: port, csrfToken: token) { _ in
                Issue.record("Invalid connections must not make requests")
                return (Data(summaryPayload.utf8), 200)
            }
        }
    }
    for status in [301, 401, 403, 429, 500] {
        await #expect(throws: (any Error).self) {
            _ = try await AntigravityQuotaClient.fetch(port: 12345, csrfToken: "test") { request in
                #expect(request.url?.lastPathComponent == "RetrieveUserQuotaSummary")
                return (Data(summaryPayload.utf8), status)
            }
        }
    }
}

@Test func antigravityDiscoveryIgnoresOtherProductsAndExtractsOnlyLoopbackListeners() {
    let processes = AntigravityDiscovery.processes(from: """
      12 /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone --csrf_token secret --app_data_dir antigravity
      13 /Applications/Antigravity.app/Contents/Resources/bin/language_server --csrf_token=second --app_data_dir=antigravity
      14 /Applications/Other.app/language_server --csrf_token other
      15 /bin/echo /Applications/Antigravity.app/Contents/Resources/bin/language_server --csrf_token fake
      16 /Applications/Antigravity.app/Contents/Resources/bin/language_server --app_data_dir antigravity
    """)
    #expect(processes.map(\.pid) == [12, 13])
    #expect(processes.map(\.csrfToken) == ["secret", "second"])
    #expect(AntigravityDiscovery.ports(from: "p12\nn127.0.0.1:12345\nn[::1]:12346\nn*:12347\nn192.168.1.10:12348\nn127.0.0.1:12345\nn127.0.0.1:0\n") == [12345, 12346])
}

@Test func antigravityScannerNeverReadsConversationFilesAsGeminiOrClaude() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("private conversation".utf8).write(to: root.appendingPathComponent("conversation.jsonl"))
    let result = await UsageScanner().scan(roots: [.antigravity: root.path])
    #expect(result.events.isEmpty)
    #expect(result.sources.isEmpty)
}

@Test func antigravityMenuBarShowsMostUsedGroupAndKeepsOriginalObservation() async throws {
    let quotas = try await AntigravityQuotaClient.fetch(port: 12345, csrfToken: "test", now: agNow) { _ in (Data(summaryPayload.utf8), 200) }
    let menu = MenuBarUsage(provider: .antigravity, quotas: quotas, now: agNow)
    #expect(menu.quota?.id == "antigravity:bucket:gemini-weekly")
    #expect(menu.title.hasPrefix("25%"))
    #expect(MenuBarUsage(provider: .antigravity, quotas: quotas, now: agNow.addingTimeInterval(901)).title.hasPrefix("25% · "))
}

@Test func antigravityLocalFetchFindsWorkingPortWithoutLoggingCredentials() async throws {
    let quotas = try await AntigravityDiscovery.fetchQuotas(runner: { executable, arguments in
        if executable == "/bin/ps" { return "12 /Applications/Antigravity.app/Contents/Resources/bin/language_server --csrf_token local-test" }
        #expect(executable == "/usr/sbin/lsof")
        #expect(arguments.contains("12"))
        return "p12\nn127.0.0.1:12345\nn127.0.0.1:12346\n"
    }, transport: { request in
        #expect(request.value(forHTTPHeaderField: "X-Codeium-Csrf-Token") == "local-test")
        if request.url?.port == 12345 { return (Data(), 400) }
        #expect(request.url?.port == 12346)
        return (Data(summaryPayload.utf8), 200)
    })
    #expect(quotas.map(\.usedPercent) == [25, 0])
    await #expect(throws: AntigravityQuotaError.notRunning) {
        _ = try await AntigravityDiscovery.fetchQuotas(runner: { _, _ in "" }, transport: { _ in
            Issue.record("No server should mean no network traffic")
            return (Data(), 200)
        })
    }
}

@Test func antigravityRefreshRetainsActualObservationOnFailureAndReplacesWholeSnapshot() async throws {
    let monitor = AntigravityQuotaMonitor()
    let initial = try await AntigravityQuotaClient.fetch(port: 12345, csrfToken: "test", now: agNow) { _ in (Data(summaryPayload.utf8), 200) }
    let first = await monitor.refresh { initial }
    #expect(first.quotas.count == 2)
    #expect(first.error == nil)
    let failed = await monitor.refresh { throw AntigravityQuotaError.notRunning }
    #expect(failed.quotas == initial)
    #expect(failed.error != nil)
    #expect(failed.quotas.allSatisfy { $0.observedAt == agNow })
    let recovered = await monitor.refresh { [initial[0]] }
    #expect(recovered.quotas.count == 1)
    #expect(recovered.error == nil)
}

@Test func antigravityQuotaOnlyProviderDoesNotInventZeroTokenChartSeries() {
    let daily = UsageAggregation.daily([], days: 1, now: agNow)
    #expect(!daily.contains { $0.provider == .antigravity })
}

@Test @MainActor func antigravityQuotaTriggersThresholdNotificationOnlyOnce() async throws {
    let suite = "AgentMeterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let monitor = QuotaAlertMonitor(defaults: defaults)
    let quota = QuotaWindow(id: "antigravity:bucket:gemini-weekly", provider: .antigravity, label: "Gemini Models · 7일", usedPercent: 95, resetsAt: agNow.addingTimeInterval(3600), observedAt: agNow, source: "Antigravity 로컬 서버")
    var sent: [QuotaWindow] = []
    _ = await monitor.check([quota], now: agNow) { sent.append($0) }
    _ = await monitor.check([quota], now: agNow) { sent.append($0) }
    #expect(sent == [quota])
}
