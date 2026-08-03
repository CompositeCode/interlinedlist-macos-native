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
    /// When set, items are stored in this shared Keychain access group so a
    /// separate helper process (the document-sync agent) can read the same
    /// token. Requires the `keychain-access-groups` entitlement to include it.
    private let accessGroup: String?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.interlinedlist.kit",
        category: "TokenStore"
    )

    public init(
        service: String = "com.interlinedlist.macos.bearer-token",
        account: String = "default",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    private func baseQuery(inGroup group: String?) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if let group { query[kSecAttrAccessGroup] = group }
        return query
    }

    /// `errSecMissingEntitlement` — returned when querying an access group the
    /// process isn't entitled to (e.g. ad-hoc-signed test hosts). Treated as a
    /// miss so callers degrade to the non-shared item instead of failing.
    private static let missingEntitlement: OSStatus = -34018

    private func readItem(inGroup group: String?) throws -> String? {
        var query = baseQuery(inGroup: group)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataCorrupted
            }
            return string
        case errSecItemNotFound, Self.missingEntitlement:
            return nil
        default:
            logger.error("Keychain read failed with OSStatus \(status, privacy: .public)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func read() throws -> String? {
        if let token = try readItem(inGroup: accessGroup) { return token }
        // Migration: a shared-group store with nothing yet in the group falls
        // back to the legacy (default access-group) item and moves it into the
        // shared group so the sync agent can read it going forward.
        if accessGroup != nil, let legacy = try readItem(inGroup: nil) {
            try? write(legacy)
            return legacy
        }
        return nil
    }

    public func write(_ token: String) throws {
        do {
            try writeItem(token, inGroup: accessGroup)
        } catch KeychainError.unexpectedStatus(Self.missingEntitlement) where accessGroup != nil {
            // Not entitled to the shared group (e.g. ad-hoc test host) — persist
            // to the non-shared item so the app still works; the sync agent just
            // can't read it until entitlements are wired.
            try writeItem(token, inGroup: nil)
        }
    }

    private func writeItem(_ token: String, inGroup group: String?) throws {
        let data = Data(token.utf8)
        let query = baseQuery(inGroup: group)
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
                logger.error("Keychain add failed with OSStatus \(addStatus, privacy: .public)")
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            logger.error("Keychain update failed with OSStatus \(status, privacy: .public)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func delete() throws {
        // Delete from both the legacy (default group) and the shared group so
        // sign-out is complete regardless of where the token currently lives.
        var groups: [String?] = [nil]
        if let accessGroup { groups.append(accessGroup) }
        for group in groups {
            let status = SecItemDelete(baseQuery(inGroup: group) as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound && status != Self.missingEntitlement {
                logger.error("Keychain delete failed with OSStatus \(status, privacy: .public)")
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }
}
