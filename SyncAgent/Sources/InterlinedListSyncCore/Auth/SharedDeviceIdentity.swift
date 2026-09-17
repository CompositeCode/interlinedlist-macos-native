import Foundation
import Security
import os

/// Supplies this machine's app-settings device id — the address of the
/// per-machine settings document the agent stores its configuration in
/// (GitHub issue #104).
public protocol DeviceIdentifying: Sendable {
    /// The id for this machine, or nil when the main app has not published one.
    func currentDeviceID() -> String?
}

/// Reads the app-settings device id the **main app** publishes into the shared
/// Keychain access group.
///
/// **Read-only, and that is the whole point.** The id keys a row in the server's
/// device registry; if this process minted its own when it found none, one Mac
/// would appear twice and its settings would split across two documents. The
/// app owns minting (`DeviceIdentity.current()`); the agent only ever consumes.
///
/// No published id therefore means "per-machine settings are not addressable
/// yet", which the configuration store treats as
/// ``RemoteConfigurationState/unavailable`` — the agent keeps running off local
/// `UserDefaults` exactly as it did before this feature existed.
///
/// Sharing contract (must match the main app's `KeychainDeviceIDStore`):
/// `kSecClassGenericPassword`, service ``SyncConfiguration/deviceIDService``,
/// account ``SyncConfiguration/deviceIDAccount``, access group
/// ``SyncConfiguration/sharedAccessGroup``.
public struct SharedDeviceIdentity: DeviceIdentifying {

    private let service: String
    private let account: String
    private let accessGroup: String?
    private let logger = Logger(subsystem: SyncConfiguration.logSubsystem, category: "DeviceIdentity")

    public init(
        service: String = SyncConfiguration.deviceIDService,
        account: String = SyncConfiguration.deviceIDAccount,
        accessGroup: String? = SyncConfiguration.sharedAccessGroup
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    public func currentDeviceID() -> String? {
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
                  let id = String(data: data, encoding: .utf8),
                  !id.isEmpty else {
                logger.error("Device id item present but not decodable")
                return nil
            }
            return id
        case errSecItemNotFound:
            return nil
        default:
            logger.error("Device id read failed: OSStatus \(status, privacy: .public)")
            return nil
        }
    }
}

/// A fixed in-memory device id, for tests and previews.
public struct StaticDeviceIdentity: DeviceIdentifying {
    private let id: String?
    public init(_ id: String?) { self.id = id }
    public func currentDeviceID() -> String? { id }
}

/// How this machine names itself when it has to add its own registry row.
///
/// Mirrors the main app's `DeviceIdentity.suggestedName` so a machine registered
/// by either process gets the same label, and the user sees one name rather than
/// two spellings of the same Mac.
public enum DeviceNaming {
    public static var suggestedName: String {
        let host = ProcessInfo.processInfo.hostName
        // `hostName` usually comes back as "studio-mac.local"; trim the suffix.
        return host.hasSuffix(".local") ? String(host.dropLast(6)) : host
    }
}
