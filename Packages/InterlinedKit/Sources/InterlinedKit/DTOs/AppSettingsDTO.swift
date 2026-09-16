import Foundation

// MARK: - Settings documents

/// A stored settings document — the `SettingsDoc` schema (work-consolidation.md
/// G17, GitHub issue #56).
///
/// **Verified live 2026-09-16** against the test account by storing real
/// settings and re-reading them (the shapes were guesses until then; see the
/// issue's "store real settings, then re-probe and tighten" step):
///
/// ```
/// GET /api/user/app-settings/interlinedlist-macos
/// -> 200 {"appKey":"interlinedlist-macos","scope":"account","deviceId":null,
///         "version":1,"updatedAt":"2026-09-16T19:39:07.135Z","schemaVersion":1,
///         "settings":{"theme":"dark","sidebarWidth":280}}
/// ```
///
/// The document is returned **bare** — there is no `{settings: …}` envelope and
/// no `{document: …}` wrapper. The earlier tolerant decoder accepted both a
/// nested `settings` key and a bare payload-as-body; the bare-body branch is
/// gone because it is now actively wrong: a real bare document has `appKey`,
/// `scope` and `version` at the top level, and treating those as settings keys
/// would write API metadata back into the user's payload on the next PUT.
///
/// `version` is the one field that cannot be optional. It drives the
/// compare-and-set write protocol — a client that cannot read the version
/// cannot legally write at all (see `WriteAppSettingsRequest`).
public struct AppSettingsDocumentDTO: Decodable, Sendable, Equatable {

    public let appKey: String
    /// Observed values: `"account"` for the user-wide document, `"device"` for a
    /// per-machine one. Note the OpenAPI *example* says `"user"`; the live API
    /// answers `"account"`, and live wins.
    public let scope: String
    /// `null` on the account-wide document, the owning machine on a device one.
    public let deviceId: String?
    /// Monotonic version for compare-and-set. Send it back as `baseVersion`.
    public let version: Int
    public let updatedAt: Date?
    /// Client-declared schema version of `settings`; the server stores whatever
    /// we send and defaults it to 1.
    public let schemaVersion: Int?
    /// Opaque, client-owned JSON — stored and returned verbatim, never
    /// interpreted by the server. See `AppSettingsValue` for why this is not a
    /// concrete struct.
    public let settings: [String: AppSettingsValue]

    public init(
        appKey: String,
        scope: String,
        deviceId: String? = nil,
        version: Int,
        updatedAt: Date? = nil,
        schemaVersion: Int? = nil,
        settings: [String: AppSettingsValue] = [:]
    ) {
        self.appKey = appKey
        self.scope = scope
        self.deviceId = deviceId
        self.version = version
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
        self.settings = settings
    }
}

/// `PUT` body for a shared or per-device settings document.
///
/// **`baseVersion` is mandatory.** Verified live 2026-09-16: omitting it —
/// exactly what this type used to do — fails every write outright with
/// `400 {"error":"baseVersion must be an integer >= 0","code":"bad_request"}`.
/// It is therefore a non-optional initialiser parameter: there is no valid way
/// to construct a write that the server would accept without one.
///
/// Send `0` to create a document that does not exist yet; send the `version`
/// you last read to update one. A stale value answers `409 version_conflict`
/// and writes nothing.
public struct WriteAppSettingsRequest: Encodable, Sendable, Equatable {
    public let settings: [String: AppSettingsValue]
    public let baseVersion: Int
    public let schemaVersion: Int?

    public init(
        settings: [String: AppSettingsValue],
        baseVersion: Int,
        schemaVersion: Int? = nil
    ) {
        self.settings = settings
        self.baseVersion = baseVersion
        self.schemaVersion = schemaVersion
    }
}

/// `DELETE /api/user/app-settings/{appKey}` response.
///
/// Verified live 2026-09-16: the delete is **idempotent and never 404s** —
/// `{"deleted":true}` when a document was removed, `{"deleted":false}` when
/// there was nothing to remove. That is why the delete path needs none of the
/// 404-means-empty mapping the read paths do.
public struct DeleteAppSettingsResponse: Decodable, Sendable, Equatable {
    public let deleted: Bool

    public init(deleted: Bool) { self.deleted = deleted }
}

// MARK: - Bootstrap

/// Where a bootstrap answer came from — the server's seeding precedence chain.
///
/// Verified live 2026-09-16 by driving every branch on the test account.
public enum AppSettingsSource: String, Decodable, Sendable, Equatable {
    /// This device's own stored document.
    case own = "self"
    /// Seeded from the main workstation's document, because this device has
    /// none of its own.
    case defaultDevice = "default-device"
    /// Seeded from the account-wide document, because the main workstation has
    /// no document either.
    case account
    /// Nothing stored anywhere yet. Arrives as `404 {"source":"none"}`.
    case none
}

/// `GET …/bootstrap?deviceId=…` — the single launch call.
///
/// ⚠️ **This shape is nothing like what the type previously modelled.** The old
/// decoder expected `{shared: …, device: …, isNewDevice, seededFromMainWorkstation}`;
/// none of those keys exist. Every field decoded to empty on every launch, and
/// silently, because the decoder tolerated absence. Verified live 2026-09-16:
///
/// ```
/// GET …/bootstrap?deviceId=<a device with its own settings>
/// -> 200 {"source":"self", …SettingsDoc…}
///
/// GET …/bootstrap?deviceId=<a device with none, main workstation has some>
/// -> 200 {"source":"default-device", …the MAIN WORKSTATION's SettingsDoc…,
///         "defaultDeviceId":"probe-mac-alpha","defaultDeviceName":"Probe Alpha"}
///
/// GET …/bootstrap?deviceId=<unseen, main workstation has none either>
/// -> 200 {"source":"account", …the ACCOUNT SettingsDoc…}
///
/// GET …/bootstrap?deviceId=<nothing stored anywhere>
/// -> 404 {"source":"none"}
/// ```
///
/// The real contract is **one document plus a provenance tag**, not a pair of
/// payloads. Note that `deviceId` on the returned document is the *source*
/// device, not the device asked about — a `default-device` answer carries the
/// main workstation's id.
public struct AppSettingsBootstrapDTO: Decodable, Sendable, Equatable {

    public let source: AppSettingsSource
    /// Absent only when `source == .none`.
    public let document: AppSettingsDocumentDTO?
    /// Which machine the settings were seeded from, on a `default-device` answer.
    public let defaultDeviceId: String?
    public let defaultDeviceName: String?

    public init(
        source: AppSettingsSource,
        document: AppSettingsDocumentDTO? = nil,
        defaultDeviceId: String? = nil,
        defaultDeviceName: String? = nil
    ) {
        self.source = source
        self.document = document
        self.defaultDeviceId = defaultDeviceId
        self.defaultDeviceName = defaultDeviceName
    }

    /// The document fields are inlined alongside `source`, so the document is
    /// decoded from the *same* container rather than a nested one.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.source = try c.decodeIfPresent(AppSettingsSource.self, forKey: .source) ?? .none
        self.defaultDeviceId = try c.decodeIfPresent(String.self, forKey: .defaultDeviceId)
        self.defaultDeviceName = try c.decodeIfPresent(String.self, forKey: .defaultDeviceName)
        // `source: "none"` carries no document at all; anything else must.
        self.document = source == .none ? nil : try? AppSettingsDocumentDTO(from: decoder)
    }

    private enum CodingKeys: String, CodingKey {
        case source, defaultDeviceId, defaultDeviceName
    }
}

// MARK: - Device registry

/// One machine registered under an app key.
///
/// **Verified live 2026-09-16** — and the field names are not the ones this
/// type used to decode. The live row is:
///
/// ```
/// {"deviceId":"probe-mac-alpha","deviceName":"Probe Alpha","platform":"macos",
///  "isDefault":true,"lastSeenAt":"2026-09-16T19:38:42.214Z",
///  "appVersion":null,"osVersion":null,"hasDeviceSettings":true}
/// ```
///
/// The previous decoder looked for `name`/`deviceLabel` and
/// `isMainWorkstation`/`isMain`. **None of those keys exist**, so every row
/// rendered with its raw device id as the display name and the main-workstation
/// badge never appeared for anyone. Both were silent — the fields were optional,
/// so nothing threw. The speculative aliases are gone: they never matched
/// anything, and keeping them would hide the next such mismatch just as
/// effectively.
///
/// `isDefault` is the wire spelling of "main workstation"; the domain layer
/// renames it, because `isDefault` says nothing about what it defaults *to*.
public struct AppDeviceDTO: Decodable, Sendable, Equatable {

    public let deviceId: String
    public let deviceName: String
    /// The main-workstation flag. Exactly one device per app key carries it.
    public let isDefault: Bool
    public let platform: String?
    public let lastSeenAt: Date?
    public let appVersion: String?
    public let osVersion: String?
    /// Whether this machine has a per-device settings document of its own.
    /// **Only present on the list route** — the single-device envelope returned
    /// by POST and PATCH omits it, which is why it is optional.
    public let hasDeviceSettings: Bool?

    public init(
        deviceId: String,
        deviceName: String,
        isDefault: Bool = false,
        platform: String? = nil,
        lastSeenAt: Date? = nil,
        appVersion: String? = nil,
        osVersion: String? = nil,
        hasDeviceSettings: Bool? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.isDefault = isDefault
        self.platform = platform
        self.lastSeenAt = lastSeenAt
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.hasDeviceSettings = hasDeviceSettings
    }
}

/// `GET …/devices` — verified live to answer `{"devices":[…]}`.
public struct AppDevicesResponse: Decodable, Sendable, Equatable {
    public let devices: [AppDeviceDTO]

    public init(devices: [AppDeviceDTO]) { self.devices = devices }
}

/// `POST …/devices` and `PATCH …/devices/{deviceId}` — both answer the device
/// wrapped in a `device` key, not bare.
///
/// Verified live 2026-09-16. The endpoints previously decoded `AppDeviceDTO`
/// directly, so register and rename both threw a decoding error on a perfectly
/// successful `200` — the id is one level down from where the decoder looked.
/// (POST answers `200`, incidentally, not the `201` the OpenAPI spec advertises.)
public struct AppDeviceEnvelope: Decodable, Sendable, Equatable {
    public let device: AppDeviceDTO

    public init(device: AppDeviceDTO) { self.device = device }
}

/// `POST …/devices` body — register this machine.
///
/// `deviceName` and `platform` are the live field names; `platform` is required
/// by the schema and was absent from the old request type entirely.
public struct RegisterDeviceRequest: Encodable, Sendable, Equatable {
    public let deviceId: String
    public let deviceName: String
    public let platform: String
    public let appVersion: String?
    public let osVersion: String?

    public init(
        deviceId: String,
        deviceName: String,
        platform: String = "macos",
        appVersion: String? = nil,
        osVersion: String? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.platform = platform
        self.appVersion = appVersion
        self.osVersion = osVersion
    }
}

/// `PATCH …/devices/{deviceId}` body — rename, or promote to main workstation.
///
/// The field names are `deviceName` and `isDefault`. Verified live 2026-09-16 —
/// and the server states the contract itself when you get it wrong, which is how
/// the previous spelling was caught:
///
/// ```
/// PATCH …/devices/probe-mac-beta  {"name":"…"}               -> 400
/// PATCH …/devices/probe-mac-beta  {"isMainWorkstation":true} -> 400
/// {"error":"at least one of deviceName or isDefault is required","code":"bad_request"}
/// ```
///
/// So **both** shipped mutations — rename and promote — failed on every call.
/// Both fields stay optional so a caller sends only what it is changing: a PATCH
/// that also carried `deviceName` would clobber a rename made on another machine
/// between this client's read and its write.
public struct UpdateDeviceRequest: Encodable, Sendable, Equatable {
    public let deviceName: String?
    public let isDefault: Bool?

    public init(deviceName: String? = nil, isDefault: Bool? = nil) {
        self.deviceName = deviceName
        self.isDefault = isDefault
    }
}

/// `DELETE …/devices/{deviceId}` response.
///
/// Verified live 2026-09-16 — and this is the useful part: **the server names
/// the machine it promoted**, so removing the main workstation does not require
/// guessing which machine inherited the role.
///
/// ```
/// DELETE …/devices/probe-mac-beta   (beta was main, alpha also registered)
/// -> 200 {"deleted":true,"promotedDeviceId":"probe-mac-alpha"}
///
/// DELETE …/devices/probe-mac-alpha  (alpha was main and the only device left)
/// -> 200 {"deleted":true,"promotedDeviceId":null}
/// ```
///
/// `promotedDeviceId` is null both when the removed device was not the main
/// workstation and when no device remains to promote.
public struct DeleteDeviceResponse: Decodable, Sendable, Equatable {
    public let deleted: Bool
    public let promotedDeviceId: String?

    public init(deleted: Bool, promotedDeviceId: String? = nil) {
        self.deleted = deleted
        self.promotedDeviceId = promotedDeviceId
    }
}
