import Foundation

public struct MenuBarUsage {
    public let quota: QuotaWindow?
    public let title: String

    public init(provider: Provider, quotas: [QuotaWindow], now: Date) {
        let latest = Dictionary(grouping: quotas.filter { $0.provider == provider && $0.observedAt <= now }, by: \.id)
            .compactMap { $0.value.max { $0.observedAt < $1.observedAt } }
            .filter { $0.usedPercent.isFinite && $0.usedPercent >= 0 }
        quota = latest.sorted {
            if provider == .antigravity, $0.usedPercent != $1.usedPercent { return $0.usedPercent > $1.usedPercent }
            let left = Self.priority($0), right = Self.priority($1)
            return left == right ? $0.id < $1.id : left < right
        }.first
        guard let quota else {
            title = "— · \(provider == .gemini ? "한도 미지원" : "한도 대기")"
            return
        }
        let usage = String(format: "%.0f%%", quota.usedPercent.rounded(.towardZero))
        guard let reset = quota.resetsAt, reset.timeIntervalSince1970.isFinite else {
            title = "\(usage) · 리셋 미정"
            return
        }
        guard reset > now else {
            title = "\(usage) · 갱신 대기"
            return
        }
        let minutes = ceil(reset.timeIntervalSince(now) / 60)
        // Avoid integer conversion overflow for malformed timestamps.
        guard minutes < Double(Int.max) else {
            title = "\(usage) · 리셋 미정"
            return
        }
        let remaining = Int(minutes)
        let countdown: String
        if remaining >= 1440 { countdown = "\(remaining / 1440)d \(remaining % 1440 / 60)h" }
        else if remaining >= 60 { countdown = "\(remaining / 60)h \(remaining % 60)m" }
        else { countdown = "\(remaining)m" }
        title = "\(usage) · \(countdown)"
    }

    private static func priority(_ quota: QuotaWindow) -> Int {
        switch quota.id {
        case "claude:five_hour", "codex:codex:primary": 0
        case "claude:seven_day", "codex:codex:secondary": 1
        default: quota.id.hasSuffix(":primary") ? 2 : quota.id.hasSuffix(":secondary") ? 3 : 4
        }
    }
}
