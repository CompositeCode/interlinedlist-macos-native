import Foundation
import Security
import os

/// Persists the bearer token issued by `POST /api/auth/sync-token`.
///
/// The token (`il_tok_…`) has no documented expiry, so it is treated as a
/// long-lived secret: Keychain only, never `UserDefaults`, never the file
/// system, never logged. The protocol exists so unit tests can substitute
/// an in-memory implementation without touching the real Keychain.
public protocol TokenStore: Sendable {
    /// Reads the persisted token, or `nil` if none has been stored.
    func read() throws -> String?
    /// Persists `token`, replacing any previous value.
    func write(_ token: String) throws
    /// Deletes the persisted token (no-op if there is none).
    func delete() throws
}

// MARK: - InMemoryTokenStore (tests + previews)

/// In-memory implementation. Safe to use in unit tests and SwiftUI previews
/// where touching the real Keychain is undesirable.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(initial: String? = nil) {
        self.token = initial
    }

    public func read() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    public func write(_ token: String) throws {
        lock.lock(); defer { lock.unlock() }
        self.token = token
    }

    public func delete() throws {
        lock.lock(); defer { lock.unlock() }
        self.token = nil
    }
}

// MARK: - KeychainTokenStore

/// Keychain-backed token storage. Uses `kSecClassGenericPassword` keyed by a
/// service string the host app supplies (defaults to the kit's identifier).
public final class KeychainTokenStore: TokenStore {

    public enum KeychainError: Error, Equatable, Sendable {
        case unexpectedStatus(OSStatus)
        case dataCorrupted
    }

    private let service: String
    private let account: String
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.interlinedlist.kit",
        category: "TokenStore"
    )

    public init(
        service: String = "com.interlinedlist.macos.bearer-token",
        account: String = "default"
    ) {
        self.service = service
        self.account = account
    }

    public func read() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataCorrupted
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            logger.error("Keychain read failed with OSStatus \(status, privacy: .public)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func write(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let update: [CFString: Any] = [
            kSecValueData: data
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = query
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("Keychain add failed with OSStatus \(addStatus, privacy: .public)")
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            logger.error("Keychain update failed with OSStatus \(status, privacy: .public)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func delete() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain delete failed with OSStatus \(status, privacy: .public)")
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
