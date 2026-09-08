import Foundation

public enum AntigravityDiscovery {
    public struct ServerProcess: Sendable {
        public let pid: Int
        public let csrfToken: String
    }

    public static func processes(from output: String) -> [ServerProcess] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard fields.count == 2, let pid = Int(fields[0]), pid > 0 else { return nil }
            let command = String(fields[1])
            // Anchor at the executable, so an argument mentioning Antigravity cannot match.
            guard command.range(of: #"^/(?:[^/\s]+/)*Antigravity\.app/Contents/(?:[^/\s]+/)*language_server(?:_macos(?:_arm|_x64)?)?\s"#, options: .regularExpression) != nil,
                  let tokenRange = command.range(of: #"(?:^|\s)--csrf_token(?:=|\s+)[^\s]+"#, options: .regularExpression) else { return nil }
            let flag = String(command[tokenRange]).trimmingCharacters(in: .whitespaces)
            let token = String(flag.dropFirst("--csrf_token".count)).trimmingCharacters(in: CharacterSet(charactersIn: "= "))
            guard !token.isEmpty else { return nil }
            return ServerProcess(pid: pid, csrfToken: token)
        }
    }

    public static func ports(from output: String) -> [Int] {
        var seen = Set<Int>()
        return output.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("n127.0.0.1:") || line.hasPrefix("n[::1]:"),
                  let suffix = line.split(separator: ":").last, let port = Int(suffix),
                  (1...65535).contains(port), seen.insert(port).inserted else { return nil }
            return port
        }
    }
}

extension AntigravityDiscovery {
    public typealias Runner = @Sendable (String, [String]) throws -> String
    public static func fetchQuotas(runner: @escaping Runner = run,
                                   transport: @escaping AntigravityQuotaClient.Transport = AntigravityQuotaClient.request) async throws -> [QuotaWindow] {
        try await Task.detached(priority: .utility) {
            let output = try runner("/bin/ps", ["-ww", "-U", NSUserName(), "-o", "pid=,command="])
            let servers = processes(from: output)
            guard !servers.isEmpty else { throw AntigravityQuotaError.notRunning }
            var lastError: any Error = AntigravityQuotaError.invalidConnection
            for server in servers.prefix(4) {
                let listeners = try runner("/usr/sbin/lsof", ["-nP", "-a", "-p", String(server.pid), "-iTCP", "-sTCP:LISTEN", "-Fn"])
                for port in ports(from: listeners).prefix(4) {
                    do { return try await AntigravityQuotaClient.fetch(port: port, csrfToken: server.csrfToken, transport: transport) }
                    catch { lastError = error }
                }
            }
            throw lastError
        }.value
    }

    public static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { throw AntigravityQuotaError.invalidConnection }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
