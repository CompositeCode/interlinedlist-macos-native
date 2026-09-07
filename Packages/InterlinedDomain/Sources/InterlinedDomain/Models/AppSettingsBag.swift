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

    // MARK: - Kit boundary

    /// The payload as the wire type. Internal — only the services in this
    /// module cross this boundary.
    var payload: [String: AppSettingsValue] { storage }
}

// MARK: - Devices

/// A machine registered under the app key (work-consolidation.md G17).
public struct AppDevice: Sendable, Equatable, Identifiable {
    public let id: String
    /// Display name, falling back to the device id when unnamed.
    public let name: String
    /// The machine whose configuration seeds a brand-new device on first
    /// sign-in. Exactly one device should carry this.
    public let isMainWorkstation: Bool
    public let createdAt: Date?
    public let lastSeenAt: Date?

    public init(
        id: String,
        name: String,
        isMainWorkstation: Bool = false,
        createdAt: Date? = nil,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.isMainWorkstation = isMainWorkstation
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}

/// The result of the one-call launch bootstrap: account-wide settings plus this
/// machine's own, and whether the server had to seed a new device.
public struct AppSettingsSnapshot: Sendable, Equatable {
    public var shared: AppSettingsBag
    public var device: AppSettingsBag
    /// True when the server had not seen this `deviceId` before.
    public let isNewDevice: Bool
    /// True when the new device's settings were seeded from the main
    /// workstation — worth surfacing once, so the user knows why their new Mac
    /// arrived pre-configured.
    public let seededFromMainWorkstation: Bool

    public init(
        shared: AppSettingsBag = AppSettingsBag(),
        device: AppSettingsBag = AppSettingsBag(),
        isNewDevice: Bool = false,
        seededFromMainWorkstation: Bool = false
    ) {
        self.shared = shared
        self.device = device
        self.isNewDevice = isNewDevice
        self.seededFromMainWorkstation = seededFromMainWorkstation
    }
}

// MARK: - Mapping

extension AppSettingsBag {
    init(from dto: AppSettingsDTO) { self.init(storage: dto.settings) }
}

extension AppDevice {
    public init(from dto: AppDeviceDTO) {
        self.init(
            id: dto.deviceId,
            name: dto.name ?? dto.deviceId,
            isMainWorkstation: dto.isMainWorkstation ?? false,
            createdAt: dto.createdAt,
            lastSeenAt: dto.lastSeenAt
        )
    }
}

extension AppSettingsSnapshot {
    init(from dto: AppSettingsBootstrapDTO) {
        self.init(
            shared: AppSettingsBag(storage: dto.shared),
            device: AppSettingsBag(storage: dto.device),
            isNewDevice: dto.isNewDevice ?? false,
            seededFromMainWorkstation: dto.seededFromMainWorkstation ?? false
        )
    }
}
