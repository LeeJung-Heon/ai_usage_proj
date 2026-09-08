import CoreFoundation
import Foundation

public enum AntigravityQuotaError: LocalizedError {
    case notRunning, invalidConnection, authentication, unavailable, invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notRunning: "Antigravity를 실행하고 로그인한 뒤 새로고침하세요."
        case .invalidConnection: "Antigravity의 로컬 연결 정보를 확인하지 못했습니다. 앱을 다시 실행하세요."
        case .authentication: "Antigravity 로그인 상태를 확인한 뒤 새로고침하세요."
        case .unavailable: "Antigravity 한도를 조회하지 못했습니다. 앱 실행 및 네트워크 연결을 확인하세요."
        case .invalidResponse: "Antigravity 한도 응답을 읽지 못했습니다. 현재 버전이나 계정에서 한도를 제공하지 않을 수 있습니다."
        }
    }
}

public enum AntigravityQuotaClient {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    public static func fetch(port: Int, csrfToken: String, now: Date = Date(),
                             transport: Transport = request) async throws -> [QuotaWindow] {
        guard (1...65535).contains(port), !csrfToken.isEmpty,
              csrfToken.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
            throw AntigravityQuotaError.invalidConnection
        }
        // The installed app exposes an HTTP listener on loopback as well as HTTPS.
        // Keep the destination fixed; never forward the CSRF token to a remote host.
        for method in ["RetrieveUserQuotaSummary", "GetUserStatus", "GetCommandModelConfigs"] {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/\(method)")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 3
            request.httpBody = Data(#"{"metadata":{"ideName":"antigravity","extensionName":"antigravity","locale":"en"}}"#.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
            let data: Data, status: Int
            do { (data, status) = try await transport(request) }
            catch { throw AntigravityQuotaError.unavailable }
            if status == 404 || status == 501 { continue }
            if status == 401 || status == 403 { throw AntigravityQuotaError.authentication }
            guard status == 200 else { throw AntigravityQuotaError.unavailable }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AntigravityQuotaError.invalidResponse
            }
            if method == "RetrieveUserQuotaSummary" { return try summary(object, now: now) }
            let statusObject = object["userStatus"] as? [String: Any]
            let config = statusObject?["cascadeModelConfigData"] as? [String: Any]
            guard let models = (config ?? object)["clientModelConfigs"] as? [[String: Any]] else {
                if method == "GetUserStatus", statusObject != nil { continue }
                throw AntigravityQuotaError.invalidResponse
            }
            var windows: [QuotaWindow] = []
            var seen = Set<String>()
            for model in models {
                guard let info = model["quotaInfo"] as? [String: Any] else { continue }
                guard let label = nonempty(model["label"]) else { throw AntigravityQuotaError.invalidResponse }
                let alias = model["modelOrAlias"] as? [String: Any]
                let id = nonempty(model["modelId"]) ?? nonempty(alias?["model"]) ?? label
                guard seen.insert(id).inserted else { continue }
                windows.append(try window(info, id: "antigravity:model:\(id)", label: label, now: now))
            }
            guard !windows.isEmpty else { throw AntigravityQuotaError.invalidResponse }
            return windows
        }
        throw AntigravityQuotaError.unavailable
    }

    private static func summary(_ object: [String: Any], now: Date) throws -> [QuotaWindow] {
        guard let response = object["response"] as? [String: Any],
              let groups = response["groups"] as? [[String: Any]] else { throw AntigravityQuotaError.invalidResponse }
        var windows: [QuotaWindow] = []
        var seen = Set<String>()
        for group in groups {
            guard let name = nonempty(group["displayName"]), let buckets = group["buckets"] as? [[String: Any]] else {
                throw AntigravityQuotaError.invalidResponse
            }
            for bucket in buckets {
                guard let id = nonempty(bucket["bucketId"]) else { throw AntigravityQuotaError.invalidResponse }
                guard seen.insert(id).inserted else { continue }
                let period: String
                switch bucket["window"] as? String {
                case "weekly": period = "7일"
                case "daily": period = "1일"
                default: period = nonempty(bucket["displayName"]) ?? "사용 한도"
                }
                windows.append(try window(bucket, id: "antigravity:bucket:\(id)", label: "\(name) · \(period)", now: now))
            }
        }
        guard !windows.isEmpty else { throw AntigravityQuotaError.invalidResponse }
        return windows
    }

    private static func window(_ value: [String: Any], id: String, label: String, now: Date) throws -> QuotaWindow {
        var reset: Date?
        if let raw = value["resetTime"], !(raw is NSNull) {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let string = raw as? String,
                  let date = fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string) else {
                throw AntigravityQuotaError.invalidResponse
            }
            reset = date
        }
        let remaining: Double
        if let raw = value["remainingFraction"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, (0...1).contains(number.doubleValue) else {
                throw AntigravityQuotaError.invalidResponse
            }
            remaining = number.doubleValue
        } else {
            // Proto3 omits numeric zero. A reset timestamp distinguishes exhausted
            // quota metadata from an absent/empty quota object.
            guard reset != nil else { throw AntigravityQuotaError.invalidResponse }
            remaining = 0
        }
        return QuotaWindow(id: id, provider: .antigravity, label: label,
                           usedPercent: (1 - remaining) * 100, resetsAt: reset,
                           observedAt: now, source: "Antigravity 로컬 서버")
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return string
    }

    public static func request(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
