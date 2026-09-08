import Foundation
import Testing
@testable import AgentMeterCore

private func parse(_ text: String, _ provider: Provider) -> ParsedUsage {
    UsageParser.parse(data: Data(text.utf8), provider: provider, source: "fixture")
}

@Test func claudeDeduplicatesStreamingBlocksAndKeepsFinalUsage() {
    let result = parse("""
    {"type":"assistant","sessionId":"s1","timestamp":"2026-09-07T01:00:00Z","requestId":"r1","message":{"id":"m1","model":"claude-test","usage":{"input_tokens":10,"output_tokens":1,"cache_read_input_tokens":100,"cache_creation_input_tokens":20}}}
    {"type":"assistant","sessionId":"s1","timestamp":"2026-09-07T01:00:01Z","requestId":"r1","message":{"id":"m1","model":"claude-test","usage":{"input_tokens":10,"output_tokens":15,"cache_read_input_tokens":100,"cache_creation_input_tokens":20}}}
    {"type":"assistant","sessionId":"s1","timestamp":"bad-date","message":{"id":"m2","usage":{"input_tokens":999}}}
    {"partial":
    """, .claude)
    #expect(result.events.count == 1)
    #expect(result.events.first?.total == 145)
    #expect(result.events.first?.output == 15)
    #expect(result.malformedLines == 1)
}

@Test func codexUsesCumulativeDeltasAndDoesNotAddCachedOrReasoningTwice() {
    let result = parse("""
    {"type":"session_meta","payload":{"id":"s1"}}
    {"type":"turn_context","payload":{"model":"gpt-test"}}
    {"timestamp":"2026-09-07T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":10,"total_tokens":120}}}}
    {"timestamp":"2026-09-07T01:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":60,"output_tokens":30,"reasoning_output_tokens":15,"total_tokens":180}}}}
    {"timestamp":"2026-09-07T01:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":60,"output_tokens":30,"total_tokens":180}},"rate_limits":{"primary":{"used_percent":42,"window_minutes":10080,"resets_at":1900000000}}}}
    """, .codex)
    #expect(result.events.count == 2)
    #expect(result.events.map(\.total).reduce(0, +) == 180)
    #expect(result.events.map(\.cacheRead).reduce(0, +) == 60)
    #expect(result.events.map(\.input).reduce(0, +) == 90)
    #expect(result.events.last?.model == "gpt-test")
    #expect(result.quotas.first?.label == "7일")
    #expect(result.quotas.first?.usedPercent == 42)
}

@Test func geminiLegacyTokensIncludeThoughtsAndToolButCacheIsSubset() {
    let result = parse("""
    {"sessionId":"s1","messages":[{"id":"m1","type":"gemini","model":"gemini-test","timestamp":"2026-09-07T01:00:00Z","tokens":{"input":100,"output":20,"cached":40,"thoughts":10,"tool":5,"total":135}}]}
    """, .gemini)
    #expect(result.events.first?.total == 135)
    #expect(result.events.first?.input == 65)
    #expect(result.events.first?.output == 30)
    #expect(result.events.first?.cacheRead == 40)
}

@Test func geminiJSONLUpdatesDeduplicateAndRetainSpentTokensAfterRewind() {
    let result = parse("""
    {"sessionId":"s1","projectHash":"p1"}
    {"id":"m1","type":"gemini","timestamp":"2026-09-07T01:00:00Z","tokens":{"input":100,"output":10,"total":110}}
    {"id":"m1","type":"gemini","timestamp":"2026-09-07T01:00:00Z","tokens":{"input":100,"output":20,"total":120}}
    {"$rewindTo":"m1"}
    {"$set":{"messages":[{"id":"m2","type":"gemini","timestamp":"2026-09-07T01:01:00Z","tokens":{"input":50,"output":5,"total":55}}]}}
    """, .gemini)
    #expect(result.events.count == 2)
    #expect(result.events.map(\.total).reduce(0, +) == 175)
}

@Test func quotaUnknownFieldsAndMalformedInputDoNotInventUsage() {
    #expect(parse("{}\nnull\n[]", .codex).events.isEmpty)
    let result = parse("""
    {"type":"event_msg","timestamp":"2026-09-07T01:00:00Z","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":0,"window_minutes":300,"resets_at":1788746400},"secondary":null}}}
    """, .codex)
    #expect(result.quotas.count == 1)
    #expect(result.quotas.first?.usedPercent == 0)
    #expect(result.quotas.first?.isStale(at: Date(timeIntervalSince1970: 1900000000)) == true)
}

@Test func codexNullWindowClearsPreviousQuotaSnapshot() {
    let result = parse("""
    {"type":"event_msg","timestamp":"2026-09-07T01:00:00Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":50,"window_minutes":300},"secondary":{"used_percent":60,"window_minutes":10080}}}}
    {"type":"event_msg","timestamp":"2026-09-07T02:00:00Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":10,"window_minutes":300},"secondary":null}}}
    """, .codex)
    #expect(result.quotas.count == 1)
    #expect(result.quotas.first?.usedPercent == 10)
}

@Test func zeroTokenSyntheticResponsesDoNotBecomeActiveSessions() {
    let result = parse("""
    {"type":"assistant","sessionId":"s","timestamp":"2026-09-07T01:00:00Z","message":{"id":"m","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}}}
    """, .claude)
    #expect(result.events.isEmpty)
}
