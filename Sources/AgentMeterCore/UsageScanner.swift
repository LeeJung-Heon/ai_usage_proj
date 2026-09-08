import Foundation

public struct SourceStatus: Sendable {
    public let provider: Provider
    public let path: String
    public var fileCount = 0
    public var eventCount = 0
    public var warnings: [String] = []
    public var exists = false
}
public struct ScanResult: Sendable {
    public var events: [UsageEvent] = []
    public var quotas: [QuotaWindow] = []
    public var sources: [SourceStatus] = []
    public init() {}
}
public actor UsageScanner {
    private struct Cached {
        let modified: Date
        let size: Int
        let parsed: ParsedUsage
    }
    private var cache: [String: Cached] = [:]
    public init() {}

    public func scan(roots: [Provider: String]) -> ScanResult {
        var result = ScanResult()
        var allEvents: [String: UsageEvent] = [:]
        var allQuotas: [String: QuotaWindow] = [:]
        var quotaObservations: [String: Date] = [:]
        var activeKeys = Set<String>()
        let manager = FileManager.default
        for provider in Provider.allCases where provider != .antigravity {
            guard let rawPath = roots[provider] else { continue }
            let root = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
            var status = SourceStatus(provider: provider, path: root.path)
            var isDirectory: ObjCBool = false
            status.exists = manager.fileExists(atPath: root.path, isDirectory: &isDirectory) && isDirectory.boolValue
            guard status.exists else { result.sources.append(status); continue }
            let directories = provider == .codex ? [root.appendingPathComponent("sessions"), root.appendingPathComponent("archived_sessions")] : [root]
            for directory in directories where manager.fileExists(atPath: directory.path) {
                var enumerationFailed = false
                guard let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in
                    enumerationFailed = true; return true
                }) else { status.warnings.append("폴더를 읽을 수 없습니다."); continue }
                for case let url as URL in enumerator {
                    let isGemini = url.lastPathComponent.hasPrefix("session-") && url.pathComponents.contains("chats") && ["json", "jsonl"].contains(url.pathExtension)
                    guard provider == .gemini ? isGemini : url.pathExtension == "jsonl" else { continue }
                    do {
                        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey])
                        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { continue }
                        status.fileCount += 1
                        let key = provider.rawValue + ":" + url.path
                        activeKeys.insert(key)
                        let modified = attributes.contentModificationDate ?? .distantPast, size = attributes.fileSize ?? 0
                        let parsed: ParsedUsage
                        if let cached = cache[key], cached.modified == modified, cached.size == size { parsed = cached.parsed }
                        else {
                            let data = try Data(contentsOf: url, options: .mappedIfSafe)
                            parsed = UsageParser.parse(data: data, provider: provider, source: url.deletingPathExtension().lastPathComponent)
                            cache[key] = Cached(modified: modified, size: size, parsed: parsed)
                        }
                        if parsed.malformedLines > 0 { status.warnings.append("\(url.lastPathComponent): 불완전한 기록 \(parsed.malformedLines)줄 제외") }
                        for event in parsed.events {
                            if let old = allEvents[event.id], old.total > event.total { continue }
                            allEvents[event.id] = event
                        }
                        for (scope, date) in parsed.quotaObservations { quotaObservations[scope] = max(quotaObservations[scope] ?? .distantPast, date) }
                        for quota in parsed.quotas where allQuotas[quota.id].map({ $0.observedAt <= quota.observedAt }) ?? true { allQuotas[quota.id] = quota }
                    } catch { status.warnings.append("\(url.lastPathComponent): 읽기 실패") }
                }
                if enumerationFailed { status.warnings.append("일부 하위 폴더에 접근할 수 없습니다.") }
            }
            status.eventCount = allEvents.values.filter { $0.provider == provider }.count
            result.sources.append(status)
        }
        cache = cache.filter { activeKeys.contains($0.key) }
        result.events = allEvents.values.sorted { $0.date < $1.date }
        result.quotas = allQuotas.values.filter { quota in
            let scope = quota.id.split(separator: ":").dropLast().joined(separator: ":")
            return quota.observedAt == quotaObservations[scope]
        }.sorted { $0.id < $1.id }
        return result
    }
}
