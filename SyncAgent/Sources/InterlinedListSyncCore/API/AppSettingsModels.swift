import Foundation

// Wire models for the **per-machine app-settings** routes the agent stores its
// configuration in (GitHub issue #104):
//
//   GET /api/user/app-settings/{appKey}/devices/{deviceId}/settings
//   PUT /api/user/app-settings/{appKey}/devices/{deviceId}/settings
//
// Independent of the main app's `InterlinedKit` DTOs, like every other model in
// this package — the agent is a clean-room implementation. Both sides were
// verified live against the same routes on 2026-09-16 (PR #102), so they agree
// because the wire says so, not because they share code.

// MARK: - Opaque settings values

/// A losslessly round-trippable JSON value.
///
/// The server stores the settings payload **verbatim and uninterpreted**, which
/// means this agent shares one document with the main app. Decoding into a
/// concrete struct would drop every key this build does not know about — and
/// since the PUT *replaces* the document rather than merging it, the next write
/// would then delete the main app's per-machine settings outright.
///
/// Keeping values opaque is what makes the overlay in
/// ``SyncAgentConfiguration/apply(to:)`` safe.
public enum SettingsValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SettingsValue])
    case object([String: SettingsValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([SettingsValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: SettingsValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognised JSON value")
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:          try c.encodeNil()
        case .bool(let v):   try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    // Readers that answer nil rather than trapping when the stored value turns
    // out to be another type — a settings blob is client-owned and a future
    // build may legitimately change a field's shape.
    public var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    public var doubleValue: Double? { if case .number(let v) = self { return v }; return nil }
}

// MARK: - Documents

/// A stored settings document.
///
/// Shape verified live 2026-09-16 (PR #102): the document comes back **bare**,
/// with no envelope.
///
/// ```
/// {"appKey":"interlinedlist-macos","scope":"device","deviceId":"…",
///  "version":3,"updatedAt":"2026-09-16T19:39:07.135Z","schemaVersion":1,
///  "settings":{…}}
/// ```
///
/// `version` cannot be optional: it is the `baseVersion` of the next write, and
/// a client that cannot read it cannot legally write at all.
public struct DeviceSettingsDocument: Decodable, Sendable, Equatable {
    public let version: Int
    public let updatedAt: Date?
    /// The machine this document belongs to. Present on device-scoped
    /// documents; nil on the account-wide one.
    public let deviceId: String?
    public let schemaVersion: Int?
    /// Opaque, client-owned payload — see ``SettingsValue``.
    public let settings: [String: SettingsValue]

    public init(
        version: Int,
        updatedAt: Date? = nil,
        deviceId: String? = nil,
        schemaVersion: Int? = nil,
        settings: [String: SettingsValue] = [:]
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.deviceId = deviceId
        self.schemaVersion = schemaVersion
        self.settings = settings
    }
}

/// `PUT …/devices/{deviceId}/settings` body.
///
/// **`baseVersion` is mandatory**, verified live: omitting it fails every write
/// with `400 {"error":"baseVersion must be an integer >= 0"}`. Send `0` to
/// create, or the `version` last read to update. A stale value answers `409` and
/// writes nothing — see ``APIError/versionConflict(current:)``.
public struct WriteDeviceSettingsBody: Encodable, Sendable, Equatable {
    public let settings: [String: SettingsValue]
    public let baseVersion: Int
    public let schemaVersion: Int?

    public init(settings: [String: SettingsValue], baseVersion: Int, schemaVersion: Int? = nil) {
        self.settings = settings
        self.baseVersion = baseVersion
        self.schemaVersion = schemaVersion
    }
}

/// `POST …/devices` body — register this machine.
///
/// The agent sends this on exactly one path: a settings write that answered 404
/// because the device is absent from the registry. See
/// ``DeviceSettingsAPI/registerDevice(deviceId:deviceName:)``.
public struct RegisterDeviceBody: Encodable, Sendable, Equatable {
    public let deviceId: String
    public let deviceName: String
    public let platform: String

    public init(deviceId: String, deviceName: String, platform: String = "macos") {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.platform = platform
    }
}

// MARK: - API surface

/// The per-machine settings operations the agent needs.
///
/// Separate from ``DocumentSyncAPI`` rather than bolted onto it: the sync engine
/// has no business with settings, and widening its protocol would force every
/// engine test double to implement routes it never calls.
public protocol DeviceSettingsAPI: Sendable {
    /// This machine's stored document, or nil when it has never written one
    /// (`404`, the ordinary first-run state).
    func fetchDeviceSettings(deviceId: String) async throws -> DeviceSettingsDocument?

    /// Compare-and-set write. Throws ``APIError/versionConflict(current:)`` when
    /// `baseVersion` is stale, and ``APIError/deviceNotRegistered`` when the
    /// machine is absent from the registry.
    func writeDeviceSettings(
        deviceId: String,
        settings: [String: SettingsValue],
        baseVersion: Int
    ) async throws -> DeviceSettingsDocument

    /// Adds this machine to the registry.
    ///
    /// Verified live 2026-09-16: `POST …/devices` is an **upsert keyed on
    /// `deviceId`** — re-posting an existing id overwrites its `deviceName`
    /// rather than duplicating the row. Calling it unconditionally would reset a
    /// machine the user had renamed back to its hostname. The agent therefore
    /// calls it only after a write proved the device absent.
    func registerDevice(deviceId: String, deviceName: String) async throws
}
