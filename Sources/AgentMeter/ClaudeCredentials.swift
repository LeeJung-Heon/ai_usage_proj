import Foundation
import Security
import LocalAuthentication
import AgentMeterCore

/// Automatic reads never prompt; only an explicit settings action can authorize.
@MainActor
enum ClaudeCredentials {
    static func accessToken(allowInteraction: Bool = false) throws -> String {
        try KeychainInteraction.perform(allowInteraction: allowInteraction) {
            try readAccessToken(allowInteraction: allowInteraction)
        }
    }

    private static func readAccessToken(allowInteraction: Bool) throws -> String {
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(status) {
            throw ClaudeQuotaError.credentialsNeedApproval
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw ClaudeQuotaError.credentialsUnavailable
        }
        return token
    }
}
