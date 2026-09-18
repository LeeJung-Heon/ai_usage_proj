import Foundation

public enum CodexQuotaError: LocalizedError {
    case credentialsUnavailable, authentication, rateLimited, invalidResponse, unavailable

    public var errorDescription: String? {
        switch self {
        case .credentialsUnavailable: "Codex 로그인 정보를 읽을 수 없습니다. Codex CLI에서 ChatGPT 계정으로 로그인했는지 확인하세요."
        case .authentication: "Codex 한도 조회 인증이 만료되었거나 허용되지 않았습니다. Codex CLI에서 다시 로그인하세요."
        case .rateLimited: "Codex 한도 조회가 잠시 제한되었습니다. 잠시 후 다시 시도하세요."
        case .invalidResponse: "Codex 한도 응답을 읽지 못했습니다."
        case .unavailable: "Codex 한도를 조회하지 못했습니다. 네트워크 연결을 확인하세요."
        }
    }
}

/// Existing Codex CLI login from `auth.json`; only ChatGPT logins carry plan limits.
public struct CodexAuth: Sendable, Equatable {
    public let accessToken: String
    public let accountID: String

    public static func parse(_ data: Data) throws -> CodexAuth {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["auth_mode"] as? String == "chatgpt",
              let tokens = object["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty,
              let account = tokens["account_id"] as? String, !account.isEmpty else {
            throw CodexQuotaError.credentialsUnavailable
        }
        return CodexAuth(accessToken: token, accountID: account)
    }
}

public enum QuotaDuration {
    /// Shared label rule for Codex windows so server and local-log windows read alike.
    public static func label(minutes: Int) -> String {
        minutes >= 1440 && minutes % 1440 == 0 ? "\(minutes / 1440)일"
            : minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60)시간"
            : minutes > 0 ? "\(minutes)분" : "사용 한도"
    }
}

public enum CodexQuotaClient {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    public static func fetch(accessToken: String, accountID: String, now: Date = Date(),
                             transport: Transport = request) async throws -> [QuotaWindow] {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !account.isEmpty else { throw CodexQuotaError.credentialsUnavailable }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(account, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data, status: Int
        do { (data, status) = try await transport(request) }
        catch { throw CodexQuotaError.unavailable }
        switch status {
        case 200: break
        case 401, 403: throw CodexQuotaError.authentication
        case 429: throw CodexQuotaError.rateLimited
        default: throw CodexQuotaError.unavailable
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let main = object["rate_limit"] as? [String: Any] else {
            throw CodexQuotaError.invalidResponse
        }
        // The account's own limit must parse; extra per-model limits are additive and skippable.
        guard let primary = main["primary_window"] as? [String: Any],
              let mainWindows = windows(primary: primary, secondary: main["secondary_window"], limitID: "codex", name: nil, now: now),
              !mainWindows.isEmpty else {
            throw CodexQuotaError.invalidResponse
        }
        var result = mainWindows
        for row in object["additional_rate_limits"] as? [Any] ?? [] {
            guard let row = row as? [String: Any], let name = row["limit_name"] as? String, !name.isEmpty,
                  let limit = row["rate_limit"] as? [String: Any], let primary = limit["primary_window"] as? [String: Any],
                  let extra = windows(primary: primary, secondary: limit["secondary_window"], limitID: name, name: name, now: now) else { continue }
            result += extra
        }
        return result
    }

    /// Returns nil when the primary window is malformed; a malformed secondary window is dropped.
    private static func windows(primary: [String: Any], secondary: Any?, limitID: String, name: String?, now: Date) -> [QuotaWindow]? {
        guard let first = window(primary, key: "primary", limitID: limitID, name: name, now: now) else { return nil }
        var result = [first]
        if let secondary = secondary as? [String: Any],
           let second = window(secondary, key: "secondary", limitID: limitID, name: name, now: now) {
            result.append(second)
        }
        return result
    }

    private static func window(_ value: [String: Any], key: String, limitID: String, name: String?, now: Date) -> QuotaWindow? {
        guard let used = value["used_percent"] as? Double, used.isFinite, used >= 0 else { return nil }
        let seconds = value["limit_window_seconds"] as? Double ?? 0
        let duration = QuotaDuration.label(minutes: seconds.isFinite && seconds > 0 ? Int(seconds / 60) : 0)
        var reset: Date?
        if let epoch = value["reset_at"] as? Double, epoch.isFinite { reset = Date(timeIntervalSince1970: epoch) }
        return QuotaWindow(id: "codex:\(limitID):\(key)", provider: .codex, label: name.map { "\($0) · \(duration)" } ?? duration,
                           usedPercent: used, resetsAt: reset, observedAt: now, source: "Codex 계정 조회")
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
