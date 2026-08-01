import Foundation
import Security
import os

/// Anything that can supply the current bearer token to the API client.
public protocol TokenProviding: Sendable {
    func currentToken() -> String?
}

/// Reads the InterlinedList bearer token (`il_tok_…`) that the **main app**
/// writes into a shared Keychain access group. Read-only: the agent never
/// mints or stores tokens on the primary path — sign-in happens in the app.
///
/// Sharing contract (must match the main app's `KeychainTokenStore`):
/// `kSecClassGenericPassword`, service ``SyncConfiguration/tokenService``,
/// account ``SyncConfiguration/tokenAccount``, access group
/// ``SyncConfiguration/sharedAccessGroup``.
public struct SharedTokenStore: TokenProviding {

    private let service: String
    private let account: String
    private let accessGroup: String?
    private let logger = Logger(subsystem: SyncConfiguration.logSubsystem, category: "SharedTokenStore")

    public init(
        service: String = SyncConfiguration.tokenService,
        account: String = SyncConfiguration.tokenAccount,
        accessGroup: String? = SyncConfiguration.sharedAccessGroup
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    public func currentToken() -> String? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let token = String(data: data, encoding: .utf8),
                  !token.isEmpty else {
                logger.error("Token item present but not decodable")
                return nil
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            logger.error("Keychain read failed: OSStatus \(status, privacy: .public)")
            return nil
        }
    }

    /// Whether a usable token is currently available in the shared group.
    public var hasToken: Bool { currentToken() != nil }
}

/// A fixed in-memory token, for tests and previews.
public struct StaticTokenProvider: TokenProviding {
    private let token: String?
    public init(_ token: String?) { self.token = token }
    public func currentToken() -> String? { token }
}
