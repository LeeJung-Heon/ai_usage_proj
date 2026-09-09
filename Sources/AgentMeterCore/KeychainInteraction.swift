import Foundation
import Security

// The login Keychain's legacy ACL dialogs are not reliably suppressed by
// LAContext. This process-wide switch is scoped to one synchronous main-actor
// operation so an interactive request cannot overlap an automatic lookup.
@MainActor
public enum KeychainInteraction {
    public static func perform<T>(allowInteraction: Bool = false, _ operation: () throws -> T) throws -> T {
        var previous: DarwinBoolean = false
        let readStatus = SecKeychainGetUserInteractionAllowed(&previous)
        guard readStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(readStatus))
        }
        let setStatus = SecKeychainSetUserInteractionAllowed(allowInteraction)
        guard setStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(setStatus))
        }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return try operation()
    }
}
