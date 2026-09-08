import Foundation

public enum ClaudeQuotaError: LocalizedError {
    case credentialsUnavailable, authentication, rateLimited, invalidResponse, unavailable

    public var errorDescription: String? {
        switch self {
        case .credentialsUnavailable: "Claude 로그인 정보를 읽을 수 없습니다. Claude Code에서 로그인 상태를 확인하세요."
        case .authentication: "Claude 한도 조회 인증이 만료되었거나 허용되지 않았습니다. Claude Code에서 다시 로그인하세요."
        case .rateLimited: "Claude 한도 조회가 잠시 제한되었습니다. 잠시 후 다시 시도하세요."
        case .invalidResponse: "Claude 한도 응답을 읽지 못했습니다."
        case .unavailable: "Claude 한도를 조회하지 못했습니다. 네트워크 연결을 확인하세요."
        }
    }
}

public enum ClaudeQuotaClient {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    public static func fetch(accessToken: String, now: Date = Date(),
                             transport: Transport = request) async throws -> [QuotaWindow] {
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeQuotaError.credentialsUnavailable
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data, status: Int
        do { (data, status) = try await transport(request) }
        catch { throw ClaudeQuotaError.unavailable }
        switch status {
        case 200: break
        case 401, 403: throw ClaudeQuotaError.authentication
        case 429: throw ClaudeQuotaError.rateLimited
        default: throw ClaudeQuotaError.unavailable
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["five_hour"] != nil || object["seven_day"] != nil else {
            throw ClaudeQuotaError.invalidResponse
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        var windows: [QuotaWindow] = []
        for (key, label) in [("five_hour", "5시간"), ("seven_day", "7일")] {
            guard let raw = object[key], !(raw is NSNull) else { continue }
            guard let value = raw as? [String: Any], let used = value["utilization"] as? Double,
                  used.isFinite, used >= 0 else { throw ClaudeQuotaError.invalidResponse }
            var reset: Date?
            if let rawReset = value["resets_at"], !(rawReset is NSNull) {
                guard let string = rawReset as? String,
                      let date = fractional.date(from: string) ?? standard.date(from: string) else {
                    throw ClaudeQuotaError.invalidResponse
                }
                reset = date
            }
            windows.append(QuotaWindow(id: "claude:\(key)", provider: .claude, label: label,
                                       usedPercent: used, resetsAt: reset, observedAt: now, source: "Claude 계정 조회"))
        }
        return windows
    }

    public static func request(_ request: URLRequest) async throws -> (Data, Int) {
        // Never persist authorization headers or follow redirects with credentials.
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
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
