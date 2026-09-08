import Foundation

public enum Provider: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude, codex, gemini, antigravity
    public var id: String { rawValue }
    public var name: String {
        switch self { case .claude: "Claude"; case .codex: "Codex"; case .gemini: "Gemini"; case .antigravity: "Antigravity" }
    }
    public var subtitle: String {
        switch self { case .claude: "Claude Code"; case .codex: "OpenAI · GPT"; case .gemini: "Gemini CLI"; case .antigravity: "Google · 모델 그룹 한도" }
    }
    public var defaultPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .claude: return (ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? home + "/.claude") + "/projects"
        case .codex: return ProcessInfo.processInfo.environment["CODEX_HOME"] ?? home + "/.codex"
        case .gemini: return home + "/.gemini/tmp"
        case .antigravity: return home + "/.gemini/antigravity"
        }
    }
}

public struct UsageEvent: Identifiable, Sendable, Equatable {
    public let id: String
    public let provider: Provider
    public let session: String
    public let model: String
    public let date: Date
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheWrite: Int
    public var total: Int { input + output + cacheRead + cacheWrite }
    public init(id: String, provider: Provider, session: String, model: String, date: Date, input: Int, output: Int, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.id = id; self.provider = provider; self.session = session; self.model = model; self.date = date
        self.input = input; self.output = output; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite
    }
}

public struct QuotaWindow: Identifiable, Sendable, Equatable, Codable {
    public let id: String
    public let provider: Provider
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let observedAt: Date
    public let source: String
    public func isStale(at now: Date) -> Bool { now.timeIntervalSince(observedAt) > 900 || (resetsAt.map { $0 <= now } ?? false) }
}

public struct ParsedUsage: Sendable {
    public var events: [UsageEvent] = []
    public var quotas: [QuotaWindow] = []
    public var malformedLines: Int = 0
    public var quotaObservations: [String: Date] = [:]
    public init() {}
}
