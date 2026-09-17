import Foundation
import InterlinedKit

/// A typed façade over an app-settings payload (work-consolidation.md G17).
///
/// The platform stores our settings as an opaque blob and hands it back
/// verbatim, so the payload must survive a round trip **including keys this
/// build has never heard of** — otherwise an older client silently deletes a
/// newer client's settings the first time it saves. `AppSettingsBag` therefore
/// keeps the whole decoded payload and mutates it key-by-key.
///
/// The raw storage is a Kit type and is deliberately `private`: per Decision
/// 0003 nothing in `App/Features/**` may import `InterlinedKit`, so the App
/// layer must be able to read and write settings without ever naming
/// `AppSettingsValue`. The typed subscripts below are that surface.
public struct AppSettingsBag: Sendable, Equatable {

    private var storage: [String: AppSettingsValue]

    public init() { self.storage = [:] }

    init(storage: [String: AppSettingsValue]) { self.storage = storage }

    /// Every key currently present, including ones this build does not
    /// understand. Useful for diagnostics; not needed for normal reads.
    public var keys: [String] { storage.keys.sorted() }

    public var isEmpty: Bool { storage.isEmpty }

    public var count: Int { storage.count }

    // MARK: - Typed access
    //
    // Each subscript reads through to the underlying value and returns nil when
    // the key is absent *or* holds a different type — never traps, so a server
    // that changes a field's type degrades to "unset" rather than crashing.

    public subscript(bool key: String) -> Bool? {
        get { storage[key]?.boolValue }
        set { write(key, newValue.map(AppSettingsValue.bool)) }
    }

    public subscript(string key: String) -> String? {
        get { storage[key]?.stringValue }
        set { write(key, newValue.map(AppSettingsValue.string)) }
    }

    public subscript(int key: String) -> Int? {
        get { storage[key]?.intValue }
        set { write(key, newValue.map { AppSettingsValue.number(Double($0)) }) }
    }

    public subscript(double key: String) -> Double? {
        get { storage[key]?.doubleValue }
        set { write(key, newValue.map(AppSettingsValue.number)) }
    }

    /// Removes a key entirely (distinct from setting it to `false` / `""`).
    public mutating func remove(_ key: String) { storage.removeValue(forKey: key) }

    /// Setting a subscript to nil removes the key rather than storing a JSON
    /// null, so "unset" round-trips as absence.
    private mutating func write(_ key: String, _ value: AppSettingsValue?) {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    /// The payload's size on the wire, in bytes.
    ///
    /// Settings ▸ Applications shows this because the stored blob is opaque and
    /// capped server-side (`413 PayloadTooLarge` is a documented response), so
    /// "how big is this" is the only meaningful thing the UI can say about a
    /// payload it cannot interpret. Encoding failure reports 0 rather than
    /// throwing: a size readout must never be the thing that breaks the pane.
    public var byteSize: Int {
        (try? JSONCoders.makeEncoder().encode(storage))?.count ?? 0
    }

    // MARK: - Kit boundary

    /// The payload as the wire type. Internal — only the services in this
    /// module cross this boundary.
    var payload: [String: AppSettingsValue] { storage }
}

// MARK: - Settings documents

/// A stored settings document: a payload plus the metadata the compare-and-set
/// write protocol and the Applications pane both need (GitHub issue #56).
///
/// `version` is carried through to the App layer deliberately. A caller that
/// wants to write must hand back the version it read, so hiding it would make
/// every write either impossible or unsafe.
public struct AppSettingsDocument: Sendable, Equatable {

    /// Which document this is.
    public enum Scope: Sendable, Equatable {
        /// The account-wide document, shared by every machine.
        case account
        /// One machine's pinned document.
        case device(id: String)
    }

    public var bag: AppSettingsBag
    /// Monotonic version, to be sent back as `baseVersion` on write.
    public let version: Int
    public let updatedAt: Date?
    public let scope: Scope
    public let schemaVersion: Int?

    public init(
        bag: AppSettingsBag = AppSettingsBag(),
        version: Int = 0,
        updatedAt: Date? = nil,
        scope: Scope = .account,
        schemaVersion: Int? = nil
    ) {
        self.bag = bag
        self.version = version
        self.updatedAt = updatedAt
        self.scope = scope
        self.schemaVersion = schemaVersion
    }

    public var byteSize: Int { bag.byteSize }
    public var isEmpty: Bool { bag.isEmpty }
}

/// Where a launch bootstrap's settings came from.
///
/// This mirrors the server's seeding precedence exactly: the machine's own
/// document, else the main workstation's, else the account-wide one, else
/// nothing. Worth surfacing because "your new Mac arrived pre-configured" is
/// only explicable if the app can say which machine it copied.
public enum AppSettingsOrigin: Sendable, Equatable {
    case own
    case mainWorkstation(deviceID: String?, deviceName: String?)
    case account
    case none
}

/// The result of the one-call launch bootstrap.
public struct AppSettingsSeed: Sendable, Equatable {
    public let origin: AppSettingsOrigin
    /// Absent only when `origin == .none` — nothing is stored anywhere yet.
    public let document: AppSettingsDocument?

    public init(origin: AppSettingsOrigin = .none, document: AppSettingsDocument? = nil) {
        self.origin = origin
        self.document = document
    }

    /// True when the server had nothing to hand this machine — a genuine
    /// first run for the whole account, not just this Mac.
    public var isFirstRun: Bool { origin == .none }

    /// The settings to start from, empty when there are none.
    public var bag: AppSettingsBag { document?.bag ?? AppSettingsBag() }
}

// MARK: - Devices

/// A machine registered under the app key (work-consolidation.md G17).
public struct AppDevice: Sendable, Equatable, Identifiable {
    public let id: String
    /// Display name, falling back to the device id when the server sends a
    /// blank one.
    public let name: String
    /// The machine whose configuration seeds a brand-new device on first
    /// sign-in. Exactly one device carries this, enforced server-side: promoting
    /// one demotes the previous holder.
    ///
    /// Named for what it means rather than its wire spelling (`isDefault`),
    /// which does not say what it is the default *for*.
    public let isMainWorkstation: Bool
    public let platform: String?
    public let lastSeenAt: Date?
    public let appVersion: String?
    public let osVersion: String?
    /// Whether this machine has a per-device settings document of its own.
    /// `nil` when the server did not say — the single-device responses from
    /// register and rename omit it, so it must not be read as "no".
    public let hasDeviceSettings: Bool?

    public init(
        id: String,
        name: String,
        isMainWorkstation: Bool = false,
        platform: String? = nil,
        lastSeenAt: Date? = nil,
        appVersion: String? = nil,
        osVersion: String? = nil,
        hasDeviceSettings: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.isMainWorkstation = isMainWorkstation
        self.platform = platform
        self.lastSeenAt = lastSeenAt
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.hasDeviceSettings = hasDeviceSettings
    }

    /// A copy with the main-workstation flag flipped, so the promote/demote
    /// pair can be reflected locally without rebuilding every field by hand at
    /// the call site (and silently dropping one when a field is added).
    public func settingMainWorkstation(_ isMain: Bool) -> AppDevice {
        AppDevice(
            id: id,
            name: name,
            isMainWorkstation: isMain,
            platform: platform,
            lastSeenAt: lastSeenAt,
            appVersion: appVersion,
            osVersion: osVersion,
            hasDeviceSettings: hasDeviceSettings
        )
    }
}

/// What the server did in response to a deregistration.
///
/// `promotedDeviceID` exists because removing the main workstation makes the
/// server pick a successor, and it reports which one. Without this the client
/// would have to guess or refetch blind — and a failed refetch would leave a
/// stale badge pointing at a machine that no longer exists.
public struct DeviceRemovalOutcome: Sendable, Equatable {
    /// False when there was nothing to delete.
    public let deleted: Bool
    /// The machine promoted to main workstation to replace the removed one, or
    /// nil when the removed device was not the main workstation (or was the
    /// last one registered).
    public let promotedDeviceID: String?

    public init(deleted: Bool, promotedDeviceID: String? = nil) {
        self.deleted = deleted
        self.promotedDeviceID = promotedDeviceID
    }
}

// MARK: - Errors

/// Failures specific to the app-settings surface that callers must be able to
/// tell apart from generic transport errors, because each needs a different
/// response from the user.
public enum AppSettingsError: LocalizedError, Equatable {

    /// A compare-and-set write lost: the stored document moved on since it was
    /// read, and **nothing was written**.
    case versionConflict

    /// A per-device settings write was addressed to a machine that is not in
    /// the registry. Retrying cannot fix this; registering the device can.
    case deviceNotRegistered

    /// A copy-to-shared was asked for from a machine that has stored no
    /// settings of its own. Refused rather than treated as an empty payload,
    /// because copying "nothing" would wipe the shared settings — the write
    /// replaces wholesale.
    case noSettingsToCopy

    public var errorDescription: String? {
        switch self {
        case .versionConflict:
            return "These settings changed on another machine. Reload and try again."
        case .deviceNotRegistered:
            return "That machine is no longer registered, so its settings could not be saved."
        case .noSettingsToCopy:
            return "That machine has no settings of its own to copy."
        }
    }
}
