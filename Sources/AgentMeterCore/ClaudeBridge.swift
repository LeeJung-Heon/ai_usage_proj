import Foundation

public enum BridgeError: LocalizedError {
    case existingStatusLine, invalidSettings
    public var errorDescription: String? {
        switch self {
        case .existingStatusLine: "이미 statusLine 설정이 있습니다. 기존 명령을 유지하도록 자동 연결을 중단했습니다. README의 수동 연결 안내를 확인하세요."
        case .invalidSettings: "Claude 설정이 올바른 JSON 객체가 아닙니다. 파일을 수정하지 않았습니다."
        }
    }
}
public enum ClaudeBridge {
    public static var defaultDestination: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AgentMeter/claude-quota.json")
    }
    public static func capture(data: Data, destination: URL, now: Date = Date()) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BridgeError.invalidSettings }
        let limits = object["rate_limits"] as? [String: Any] ?? [:]
        var windows: [QuotaWindow] = []
        for (key, label) in [("five_hour", "5시간"), ("seven_day", "7일"), ("spend_limit", "지출 한도")] {
            guard let value = limits[key] as? [String: Any], let used = value["used_percentage"] as? Double, used.isFinite, used >= 0 else { continue }
            windows.append(QuotaWindow(id: "claude:\(key)", provider: .claude, label: label, usedPercent: used,
                                       resetsAt: (value["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:)), observedAt: now, source: "Claude 상태 표시줄"))
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(windows).write(to: destination, options: .atomic)
    }
    public static func install(settings: URL, executable: URL, destination: URL) throws {
        let manager = FileManager.default
        var object: [String: Any] = [:]
        if manager.fileExists(atPath: settings.path) {
            let data = try Data(contentsOf: settings)
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BridgeError.invalidSettings }
            object = existing
            guard object["statusLine"] == nil || object["statusLine"] is NSNull else { throw BridgeError.existingStatusLine }
            let backup = settings.deletingLastPathComponent().appendingPathComponent("settings.agentmeter-backup-\(UUID().uuidString).json")
            try data.write(to: backup, options: .withoutOverwriting)
        }
        object["statusLine"] = ["type": "command", "command": shellQuote(executable.path) + " --output " + shellQuote(destination.path)]
        try manager.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: settings, options: .atomic)
    }
    public static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
