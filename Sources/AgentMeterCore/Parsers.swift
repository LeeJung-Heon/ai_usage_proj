import Foundation

public enum UsageParser {
    public static func parse(data: Data, provider: Provider, source: String) -> ParsedUsage {
        var result = ParsedUsage()
        var records: [[String: Any]] = []
        if provider == .gemini, let whole = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            records = [whole]
        } else {
            for line in data.split(separator: 10) where !line.allSatisfy({ $0 == 32 || $0 == 13 || $0 == 9 }) {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) else {
                    result.malformedLines += 1; continue
                }
                if let record = object as? [String: Any] { records.append(record) }
            }
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        func date(_ raw: Any?) -> Date? {
            guard let string = raw as? String else { return nil }
            return fractional.date(from: string) ?? standard.date(from: string)
        }
        var events: [String: UsageEvent] = [:]
        var quotas: [String: QuotaWindow] = [:]
        var session = source
        var model = "알 수 없음"
        var previous = ["input_tokens": 0, "cached_input_tokens": 0, "output_tokens": 0]
        var epoch = 0
        func keep(_ event: UsageEvent) {
            guard event.total > 0 else { return }
            // A final streaming snapshot replaces earlier blocks of the same response.
            if let old = events[event.id], old.total > event.total { return }
            events[event.id] = event
        }
        func geminiMessage(_ message: [String: Any]) {
            guard message["type"] as? String == "gemini",
                  let usage = message["tokens"] as? [String: Any],
                  let id = message["id"] as? String, let time = date(message["timestamp"]) else { return }
            let input = number(usage, "input"), cache = min(input, number(usage, "cached"))
            keep(UsageEvent(id: "gemini:\(session):\(id)", provider: .gemini, session: session,
                            model: message["model"] as? String ?? "Gemini", date: time,
                            input: input - cache + number(usage, "tool"),
                            output: number(usage, "output") + number(usage, "thoughts"), cacheRead: cache))
        }
        for record in records {
            switch provider {
            case .antigravity: continue
            case .claude:
                guard record["type"] as? String == "assistant",
                      let message = record["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let id = message["id"] as? String,
                      let time = date(record["timestamp"]) else { continue }
                let sessionID = record["sessionId"] as? String ?? source
                keep(UsageEvent(id: "claude:\(id):\(record["requestId"] as? String ?? "")", provider: .claude,
                                session: sessionID, model: message["model"] as? String ?? "Claude", date: time,
                                input: number(usage, "input_tokens"), output: number(usage, "output_tokens"),
                                cacheRead: number(usage, "cache_read_input_tokens"), cacheWrite: number(usage, "cache_creation_input_tokens")))
            case .codex:
                guard let payload = record["payload"] as? [String: Any] else { continue }
                if record["type"] as? String == "session_meta" { session = payload["id"] as? String ?? session }
                if record["type"] as? String == "turn_context" { model = payload["model"] as? String ?? model }
                guard payload["type"] as? String == "token_count", let time = date(record["timestamp"]) else { continue }
                if let limits = payload["rate_limits"] as? [String: Any] {
                    let limitID = limits["limit_id"] as? String ?? "codex"
                    let scope = "codex:\(limitID)"
                    if let observed = result.quotaObservations[scope], observed > time { continue }
                    result.quotaObservations[scope] = time
                    quotas = quotas.filter { !$0.key.hasPrefix(scope + ":") }
                    for key in ["primary", "secondary"] {
                        guard let window = limits[key] as? [String: Any], let percent = window["used_percent"] as? Double, percent.isFinite, percent >= 0 else { continue }
                        let minutes = number(window, "window_minutes")
                        let duration = QuotaDuration.label(minutes: minutes)
                        let id = "codex:\(limitID):\(key)"
                        let label = limitID == "codex" ? duration : "\(limits["limit_name"] as? String ?? limitID) · \(duration)"
                        quotas[id] = QuotaWindow(id: id, provider: .codex, label: label, usedPercent: percent,
                                                  resetsAt: (window["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:)), observedAt: time, source: "Codex 로컬 기록")
                    }
                }
                guard let info = payload["info"] as? [String: Any], let usage = info["total_token_usage"] as? [String: Any] else { continue }
                let cumulativeInput = number(usage, "input_tokens"), cumulativeOutput = number(usage, "output_tokens")
                if cumulativeInput < previous["input_tokens", default: 0] || cumulativeOutput < previous["output_tokens", default: 0] {
                    previous = [:]; epoch += 1
                }
                let input = max(0, cumulativeInput - previous["input_tokens", default: 0])
                let output = max(0, cumulativeOutput - previous["output_tokens", default: 0])
                let cache = min(input, max(0, number(usage, "cached_input_tokens") - previous["cached_input_tokens", default: 0]))
                previous = ["input_tokens": cumulativeInput, "output_tokens": cumulativeOutput, "cached_input_tokens": number(usage, "cached_input_tokens")]
                if input + output > 0 {
                    keep(UsageEvent(id: "codex:\(session):\(epoch):\(cumulativeInput):\(cumulativeOutput)", provider: .codex,
                                    session: session, model: model, date: time, input: input - cache, output: output, cacheRead: cache))
                }
            case .gemini:
                if let id = record["sessionId"] as? String { session = id }
                if let messages = record["messages"] as? [[String: Any]] { messages.forEach(geminiMessage) }
                if let update = record["$set"] as? [String: Any], let messages = update["messages"] as? [[String: Any]] { messages.forEach(geminiMessage) }
                // Rewind removes context, but cannot refund tokens already spent.
                geminiMessage(record)
            }
        }
        result.events = events.values.sorted { $0.date < $1.date }
        result.quotas = quotas.values.sorted { $0.id < $1.id }
        return result
    }

    private static func number(_ values: [String: Any], _ key: String) -> Int {
        guard let value = values[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue >= 0, value.doubleValue < Double(Int.max / 16) else { return 0 }
        return value.intValue
    }
}

import CoreFoundation
