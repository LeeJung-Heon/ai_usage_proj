import Foundation
import AgentMeterCore

/// Reads the existing Codex CLI login from the configured Codex home; nothing is cached or written.
enum CodexCredentials {
    static func load(codexHome: String) throws -> CodexAuth {
        let file = URL(fileURLWithPath: (codexHome as NSString).expandingTildeInPath).appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: file) else { throw CodexQuotaError.credentialsUnavailable }
        return try CodexAuth.parse(data)
    }
}
