import Foundation

public struct DailyUsage: Identifiable, Sendable {
    public var id: String { "\(provider.rawValue):\(date.timeIntervalSince1970)" }
    public let date: Date
    public let provider: Provider
    public let tokens: Int
}
public enum UsageAggregation {
    public static func filtered(_ events: [UsageEvent], provider: Provider?, days: Int, now: Date, calendar: Calendar = .current) -> [UsageEvent] {
        guard days > 0, let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else { return [] }
        return events.filter { (provider == nil || $0.provider == provider) && $0.date >= start && $0.date <= now }
    }
    public static func daily(_ events: [UsageEvent], days: Int, now: Date, calendar: Calendar = .current) -> [DailyUsage] {
        guard days > 0 else { return [] }
        let filtered = filtered(events, provider: nil, days: days, now: now, calendar: calendar)
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return (0..<days).reversed().flatMap { offset -> [DailyUsage] in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) else { return [] }
            return Provider.allCases.filter { $0 != .antigravity }.map { provider in
                DailyUsage(date: date, provider: provider, tokens: grouped[date, default: []].filter { $0.provider == provider }.reduce(0) { $0 + $1.total })
            }
        }
    }
}
