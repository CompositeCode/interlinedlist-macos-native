import Foundation
import Security
import os

// MARK: - Credentials

/// Email/password pair used by `LiveSessionEstablisher` to establish the
/// cookie session required by the decision-0001 session-only allowlist.
public struct Credentials: Sendable, Equatable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

// MARK: - CredentialStore

/// Persists and retrieves the signed-in user's email and password for the
/// lazy session-login step (decision 0001 / `LiveSessionEstablisher`).
///
/// Credentials are more sensitive than the bearer token — they unlock the
/// whole account, not just a single session — so the same Keychain-only
/// rule applies: never `UserDefaults`, never files, never logs.
public protocol CredentialStore: Sendable {
    /// Returns the stored credentials, or `nil` if none have been saved yet.
    func read() throws -> Credentials?
    /// Persists `credentials`, replacing any previous value.
    func write(_ credentials: Credentials) throws
    /// Deletes the stored credentials (no-op if absent).
    func delete() throws
}

// MARK: - InMemoryCredentialStore (tests + previews)

public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Credentials?

    public init(initial: Credentials? = nil) {
        self.stored = initial
    }

    public func read() throws -> Credentials? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func write(_ credentials: Credentials) throws {
        lock.lock(); defer { lock.unlock() }
        self.stored = credentials
    }

    public func delete() throws {
        lock.lock(); defer { lock.unlock() }
        self.stored = nil
    }
}

// MARK: - KeychainCredentialStore

/// Keychain-backed credential storage. Stores email and password as a JSON
/// blob under `kSecClassGenericPassword` keyed by `service`.
public final class KeychainCredentialStore: CredentialStore {

    public enum Error: Swift.Error, Equatable, Sendable {
        case dataCorrupted
        case unexpectedStatus(OSStatus)
    }

    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.interlinedlist.kit",
        category: "CredentialStore"
    )

    public init(
        service: String = "com.interlinedlist.macos.credentials",
        account: String = "session"
    ) {
        self.service = service
        self.account = account
    }

    private struct Payload: Codable {
        let email: String
        let password: String
    }

    public func read() throws -> Credentials? {
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
                  let payload = try? decoder.decode(Payload.self, from: data) else {
                throw Error.dataCorrupted
            }
            return Credentials(email: payload.email, password: payload.password)
        case errSecItemNotFound:
            return nil
        default:
            logger.error("Credential read failed OSStatus \(status, privacy: .public)")
            throw Error.unexpectedStatus(status)
        }
    }

    public func write(_ credentials: Credentials) throws {
        let data = try encoder.encode(Payload(email: credentials.email, password: credentials.password))
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let update: [CFString: Any] = [kSecValueData: data]
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
                logger.error("Credential add failed OSStatus \(addStatus, privacy: .public)")
                throw Error.unexpectedStatus(addStatus)
            }
        default:
            logger.error("Credential update failed OSStatus \(status, privacy: .public)")
            throw Error.unexpectedStatus(status)
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
            logger.error("Credential delete failed OSStatus \(status, privacy: .public)")
            throw Error.unexpectedStatus(status)
        }
    }
}
