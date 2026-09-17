import Foundation
import Security
import os

/// Publishes this Mac's app-settings device id to a place the bundled
/// document-sync agent can read it (GitHub issue #104).
///
/// The agent keeps its configuration in per-machine app settings, which live at
/// `…/devices/{deviceId}/settings`. Addressing that document means the agent and
/// the app must agree on **one** device id per machine — two ids would produce
/// two rows in the registry for the same computer and split its settings in
/// half.
///
/// They cannot simply share `UserDefaults`: the agent is a separate process with
/// its own bundle identifier (`com.interlinedlist.macos.sync`) and therefore its
/// own defaults domain. The shared Keychain access group is the channel that
/// already exists and already works — the agent reads the bearer token through
/// it — so the device id travels the same way rather than adding an app-group
/// entitlement, which would mean re-provisioning both signed bundles.
///
/// The device id is **not a secret**; the Keychain is used here purely as the
/// cross-process store both sandboxes are entitled to. That is why this type is
/// separate from ``KeychainTokenStore`` despite the similar mechanics: the
/// handling rules for a bearer token and for an opaque machine id are not the
/// same, and sharing one type would invite treating them as if they were.
public protocol DeviceIDStoring: Sendable {
    /// The published id, or nil when none has been written yet.
    func read() -> String?
    /// Publishes `id`, replacing any previous value.
    func write(_ id: String)
}

// MARK: - Keychain

/// Shared-Keychain implementation. Deliberately non-throwing.
///
/// A device id that cannot be shared is a degraded-but-working state, not a
/// failure: the app keeps its own copy in `UserDefaults` and the agent falls
/// back to local settings. Propagating a Keychain `OSStatus` out of here would
/// give every caller an error it can do nothing about, on a path that must
/// never block launch.
public struct KeychainDeviceIDStore: DeviceIDStoring {

    private let service: String
    private let account: String
    private let accessGroup: String?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.interlinedlist.kit",
        category: "DeviceIDStore"
    )

    /// - Parameters:
    ///   - service: `kSecAttrService`. **Must match the agent's
    ///     `SyncConfiguration.deviceIDService`** — the two processes are
    ///     independent codebases agreeing on one wire contract.
    ///   - accessGroup: the shared group both bundles list in
    ///     `keychain-access-groups`.
    public init(
        service: String = "com.interlinedlist.macos.device-id",
        account: String = "default",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    /// `errSecMissingEntitlement` — returned when querying an access group the
    /// process is not entitled to, which is the normal state for an ad-hoc
    /// signed test host. Treated as a miss so tests and unsigned local builds
    /// degrade to "nothing published" instead of failing.
    private static let missingEntitlement: OSStatus = -34018

    private func baseQuery() -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        return query
    }

    public func read() -> String? {
        var query = baseQuery()
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let id = String(data: data, encoding: .utf8),
                  !id.isEmpty else { return nil }
            return id
        case errSecItemNotFound, Self.missingEntitlement:
            return nil
        default:
            logger.error("Device id read failed with OSStatus \(status, privacy: .public)")
            return nil
        }
    }

    public func write(_ id: String) {
        guard let data = id.data(using: .utf8) else { return }
        let query = baseQuery()

        // Update first, then add. `SecItemAdd` on an existing item answers
        // `errSecDuplicateItem` rather than replacing, so add-then-update would
        // leave a stale id in place on every machine that already has one.
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if update == errSecSuccess { return }

        var insert = query
        insert[kSecValueData] = data
        // The agent runs as a login item, so the item has to be readable before
        // the user unlocks the screen for the first time after a reboot.
        insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(insert as CFDictionary, nil)
        if status != errSecSuccess && status != Self.missingEntitlement {
            logger.error("Device id write failed with OSStatus \(status, privacy: .public)")
        }
    }
}

// MARK: - In-memory (tests + previews)

/// In-memory implementation for unit tests and previews, where touching the
/// real Keychain is both undesirable and (unsigned) impossible.
public final class InMemoryDeviceIDStore: DeviceIDStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var id: String?

    public init(initial: String? = nil) { self.id = initial }

    public func read() -> String? {
        lock.lock(); defer { lock.unlock() }
        return id
    }

    public func write(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        self.id = id
    }
}
