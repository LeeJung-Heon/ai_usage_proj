import Foundation
import Testing
@testable import AgentMeterCore

private func temporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
private let event = #"{"type":"assistant","sessionId":"s","timestamp":"2026-09-07T01:00:00Z","message":{"id":"m","model":"claude-test","usage":{"input_tokens":10,"output_tokens":5}}}"#

@Test func scannerRefreshesModifiedFilesDeduplicatesAndRemovesDeletedFiles() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let sub = root.appendingPathComponent("project/subagents")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let file = sub.appendingPathComponent("one.jsonl"), copy = root.appendingPathComponent("copy.jsonl")
    try Data(event.utf8).write(to: file)
    try Data(event.utf8).write(to: copy)
    let scanner = UsageScanner()
    let first = await scanner.scan(roots: [.claude: root.path])
    #expect(first.events.count == 1)
    #expect(first.sources.first?.fileCount == 2)
    let updated = event.replacingOccurrences(of: #""output_tokens":5"#, with: #""output_tokens":500"#)
    try Data(updated.utf8).write(to: file)
    let second = await scanner.scan(roots: [.claude: root.path])
    #expect(second.events.first?.total == 510)
    try FileManager.default.removeItem(at: file)
    try FileManager.default.removeItem(at: copy)
    #expect(await scanner.scan(roots: [.claude: root.path]).events.isEmpty)
}

@Test func scannerRestrictsCodexDiscoveryAndReportsMissingSources() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    try Data("not json".utf8).write(to: root.appendingPathComponent("auth.jsonl"))
    let result = await UsageScanner().scan(roots: [.codex: root.path, .gemini: root.appendingPathComponent("missing").path])
    #expect(result.sources.first(where: { $0.provider == .codex })?.fileCount == 0)
    #expect(result.sources.first(where: { $0.provider == .gemini })?.exists == false)
    #expect(result.sources.count == 2)
}

@Test func bridgePersistsOnlyQuotaMetadataAndClearsMissingQuota() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("quota.json")
    let data = Data(#"{"secret":"must-not-persist","cwd":"private-project","rate_limits":{"five_hour":{"used_percentage":25,"resets_at":1900000000},"seven_day":{"used_percentage":60,"resets_at":1900100000}}}"#.utf8)
    try ClaudeBridge.capture(data: data, destination: destination, now: Date(timeIntervalSince1970: 1800000000))
    let saved = try Data(contentsOf: destination)
    #expect(!String(decoding: saved, as: UTF8.self).contains("must-not-persist"))
    let windows = try JSONDecoder().decode([QuotaWindow].self, from: saved)
    #expect(windows.map(\.usedPercent).sorted() == [25, 60])
    try ClaudeBridge.capture(data: Data("{}".utf8), destination: destination)
    #expect(try JSONDecoder().decode([QuotaWindow].self, from: Data(contentsOf: destination)).isEmpty)
}

@Test func bridgeInstallationPreservesOtherSettingsAndRefusesExistingStatusLine() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let settings = root.appendingPathComponent("settings.json")
    try Data(#"{"theme":"dark","permissions":{"allow":[]}}"#.utf8).write(to: settings)
    try ClaudeBridge.install(settings: settings, executable: URL(fileURLWithPath: "/tmp/a b/capture"), destination: root.appendingPathComponent("quota.json"))
    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    #expect(saved["theme"] as? String == "dark")
    #expect((saved["statusLine"] as? [String: Any])?["command"] as? String != nil)
    let before = try Data(contentsOf: settings)
    #expect(throws: (any Error).self) {
        try ClaudeBridge.install(settings: settings, executable: URL(fileURLWithPath: "/other"), destination: root.appendingPathComponent("quota.json"))
    }
    #expect(try Data(contentsOf: settings) == before)
}

@Test func aggregationUsesLocalDayFiltersFutureAndFillsEmptyDays() throws {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
    let now = ISO8601DateFormatter().date(from: "2026-09-07T03:00:00Z")!
    func item(_ id: String, _ provider: Provider, _ date: String, _ input: Int) -> UsageEvent {
        UsageEvent(id: id, provider: provider, session: "s", model: "m", date: ISO8601DateFormatter().date(from: date)!, input: input, output: 0)
    }
    let events = [item("a", .claude, "2026-09-06T14:59:59Z", 10), item("b", .codex, "2026-09-06T15:00:00Z", 20), item("c", .codex, "2026-09-08T15:00:00Z", 999)]
    #expect(UsageAggregation.filtered(events, provider: nil, days: 1, now: now, calendar: calendar).map(\.id) == ["b"])
    #expect(UsageAggregation.filtered(events, provider: .claude, days: 1, now: now, calendar: calendar).isEmpty)
    let buckets = UsageAggregation.daily(events, days: 2, now: now, calendar: calendar)
    #expect(buckets.count == 6)
    #expect(buckets.map(\.tokens).reduce(0, +) == 30)
    #expect(buckets.filter { $0.tokens == 0 }.count == 4)
}

@Test func scannerUsesWholeNewestQuotaSnapshotAcrossFiles() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let sessions = root.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    let older = #"{"type":"event_msg","timestamp":"2026-09-07T01:00:00Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":20,"window_minutes":300},"secondary":{"used_percent":60,"window_minutes":10080}}}}"#
    let newer = #"{"type":"event_msg","timestamp":"2026-09-07T02:00:00Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":30,"window_minutes":300},"secondary":null}}}"#
    try Data(older.utf8).write(to: sessions.appendingPathComponent("old.jsonl"))
    try Data(newer.utf8).write(to: sessions.appendingPathComponent("new.jsonl"))
    let result = await UsageScanner().scan(roots: [.codex: root.path])
    #expect(result.quotas.count == 1)
    #expect(result.quotas.first?.usedPercent == 30)
}
