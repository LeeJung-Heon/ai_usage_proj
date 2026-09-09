import Security
import Testing
@testable import AgentMeterCore

@Suite(.serialized) @MainActor
struct KeychainInteractionTests {
    private func interactionAllowed() throws -> Bool {
        var allowed: DarwinBoolean = false
        try #require(SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess)
        return allowed.boolValue
    }

    @Test func silentReadDisablesLegacyDialogsAndRestoresState() throws {
        let original = try interactionAllowed()
        defer { SecKeychainSetUserInteractionAllowed(original) }
        try #require(SecKeychainSetUserInteractionAllowed(true) == errSecSuccess)
        let value = try KeychainInteraction.perform {
            let allowed = try interactionAllowed()
            #expect(allowed == false)
            return 42
        }
        #expect(value == 42)
        let restored = try interactionAllowed()
        #expect(restored == true)
    }

    @Test func failedReadRestoresState() throws {
        enum ReadError: Error { case denied }
        let original = try interactionAllowed()
        defer { SecKeychainSetUserInteractionAllowed(original) }
        try #require(SecKeychainSetUserInteractionAllowed(true) == errSecSuccess)
        #expect(throws: ReadError.self) {
            try KeychainInteraction.perform {
                let allowed = try interactionAllowed()
                #expect(allowed == false)
                throw ReadError.denied
            }
        }
        let restored = try interactionAllowed()
        #expect(restored == true)
    }

    @Test func explicitAuthorizationIsScopedAndPreservesDisabledState() throws {
        let original = try interactionAllowed()
        defer { SecKeychainSetUserInteractionAllowed(original) }
        try #require(SecKeychainSetUserInteractionAllowed(false) == errSecSuccess)
        try KeychainInteraction.perform(allowInteraction: true) {
            let allowed = try interactionAllowed()
            #expect(allowed == true)
        }
        let afterAuthorization = try interactionAllowed()
        #expect(afterAuthorization == false)
        try KeychainInteraction.perform {
            let allowed = try interactionAllowed()
            #expect(allowed == false)
        }
        let restored = try interactionAllowed()
        #expect(restored == false)
    }
}
