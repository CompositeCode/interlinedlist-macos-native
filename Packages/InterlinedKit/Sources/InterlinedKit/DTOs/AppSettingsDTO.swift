import Foundation

// MARK: - Shared / per-device settings payloads

/// The stored settings blob for an app key or a device (work-consolidation.md
/// G17). The platform treats the payload as opaque, so it is carried as
/// `[String: AppSettingsValue]` and never narrowed to a fixed struct — see `AppSettingsValue`
/// for why that matters for forward compatibility.
///
/// ⚠️ **Wire shapes here are UNVERIFIED.** The gap definition names the routes
/// and the semantics (from `/help/app-settings`) but does not record response
/// bodies, and the test account has no registered `appKey` yet. Every envelope
/// below therefore decodes tolerantly: the payload is accepted either under a
/// `settings` key or as the bare top-level object, and every metadata field is
/// optional. Tighten these once a live probe confirms the real shapes.
public struct AppSettingsDTO: Decodable, Sendable, Equatable {
    public let settings: [String: AppSettingsValue]
    public let updatedAt: Date?

    public init(settings: [String: AppSettingsValue], updatedAt: Date? = nil) {
        self.settings = settings
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? c.decodeIfPresent([String: AppSettingsValue].self, forKey: .settings) {
            self.settings = nested
            self.updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
            return
        }
        // Bare object: the whole body *is* the settings payload. Strip the
        // metadata keys so they don't masquerade as settings.
        let bare = (try? decoder.singleValueContainer().decode([String: AppSettingsValue].self)) ?? [:]
        var stripped = bare
        stripped.removeValue(forKey: CodingKeys.updatedAt.rawValue)
        self.settings = stripped
        // The bare path decodes through `AppSettingsValue`, which bypasses the
        // shared date strategy, so parse the timestamp explicitly here.
        self.updatedAt = bare[CodingKeys.updatedAt.rawValue]?.stringValue.flatMap(JSONCoders.parseDate)
    }

    private enum CodingKeys: String, CodingKey { case settings, updatedAt }
}

/// `PUT` body for shared or per-device settings — the payload, wrapped.
public struct WriteAppSettingsRequest: Encodable, Sendable, Equatable {
    public let settings: [String: AppSettingsValue]

    public init(settings: [String: AppSettingsValue]) { self.settings = settings }
}

// MARK: - Device registry

/// One registered device (machine) under an app key.
///
/// `isMainWorkstation` is the flag behind the "main workstation seeds a
/// brand-new device on first sign-in" behaviour described in the gap definition.
public struct AppDeviceDTO: Decodable, Sendable, Equatable {
    public let deviceId: String
    public let name: String?
    public let isMainWorkstation: Bool?
    public let createdAt: Date?
    public let lastSeenAt: Date?

    public init(
        deviceId: String,
        name: String? = nil,
        isMainWorkstation: Bool? = nil,
        createdAt: Date? = nil,
        lastSeenAt: Date? = nil
    ) {
        self.deviceId = deviceId
        self.name = name
        self.isMainWorkstation = isMainWorkstation
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }

    /// Accepts `deviceId` or a plain `id`, and `name` or `deviceLabel` — the
    /// two naming conventions already seen elsewhere on this API (`SessionDTO`
    /// uses `deviceLabel`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decodeIfPresent(String.self, forKey: .deviceId)
            ?? c.decodeIfPresent(String.self, forKey: .id)
        guard let id else {
            throw DecodingError.keyNotFound(
                CodingKeys.deviceId,
                .init(codingPath: decoder.codingPath, debugDescription: "device has neither deviceId nor id")
            )
        }
        self.deviceId = id
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? c.decodeIfPresent(String.self, forKey: .deviceLabel)
        self.isMainWorkstation = try c.decodeIfPresent(Bool.self, forKey: .isMainWorkstation)
            ?? c.decodeIfPresent(Bool.self, forKey: .isMain)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        self.lastSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
    }

    private enum CodingKeys: String, CodingKey {
        case deviceId, id, name, deviceLabel, isMainWorkstation, isMain, createdAt, lastSeenAt
    }
}

/// `GET /api/user/app-settings/{appKey}/devices` response — named envelope or
/// bare array.
public struct AppDevicesResponse: Decodable, Sendable, Equatable {
    public let devices: [AppDeviceDTO]

    public init(devices: [AppDeviceDTO]) { self.devices = devices }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let bare = try? single.decode([AppDeviceDTO].self) {
            self.devices = bare
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.devices = try c.decodeIfPresent([AppDeviceDTO].self, forKey: .devices) ?? []
    }

    private enum CodingKeys: String, CodingKey { case devices }
}

/// `POST …/devices` body — register this machine.
public struct RegisterDeviceRequest: Encodable, Sendable, Equatable {
    public let deviceId: String
    public let name: String?

    public init(deviceId: String, name: String? = nil) {
        self.deviceId = deviceId
        self.name = name
    }
}

/// `PATCH …/devices/{deviceId}` body — rename, or promote to main workstation.
/// Both fields are optional so a caller sends only what it is changing.
public struct UpdateDeviceRequest: Encodable, Sendable, Equatable {
    public let name: String?
    public let isMainWorkstation: Bool?

    public init(name: String? = nil, isMainWorkstation: Bool? = nil) {
        self.name = name
        self.isMainWorkstation = isMainWorkstation
    }
}

// MARK: - Bootstrap

/// `GET …/bootstrap?deviceId=…` response — the one call a launching client makes.
///
/// Carries the account-wide shared settings plus this machine's own settings;
/// when the device is brand new the server seeds the per-device payload from the
/// main workstation (the gap definition's stated behaviour), which is what
/// `seededFromMainWorkstation` reports.
public struct AppSettingsBootstrapDTO: Decodable, Sendable, Equatable {
    public let shared: [String: AppSettingsValue]
    public let device: [String: AppSettingsValue]
    public let isNewDevice: Bool?
    public let seededFromMainWorkstation: Bool?

    public init(
        shared: [String: AppSettingsValue] = [:],
        device: [String: AppSettingsValue] = [:],
        isNewDevice: Bool? = nil,
        seededFromMainWorkstation: Bool? = nil
    ) {
        self.shared = shared
        self.device = device
        self.isNewDevice = isNewDevice
        self.seededFromMainWorkstation = seededFromMainWorkstation
    }

    /// Accepts `shared`/`sharedSettings` and `device`/`deviceSettings`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Split out of an inline `??` chain: the nested optionals from
        // `try? decodeIfPresent` made the expression too costly to type-check.
        func payload(_ primary: CodingKeys, _ alternate: CodingKeys) -> [String: AppSettingsValue] {
            let type = [String: AppSettingsValue].self
            if let found = try? c.decodeIfPresent(type, forKey: primary) {
                return found
            }
            if let found = try? c.decodeIfPresent(type, forKey: alternate) {
                return found
            }
            return [:]
        }
        self.shared = payload(.shared, .sharedSettings)
        self.device = payload(.device, .deviceSettings)
        self.isNewDevice = try? c.decodeIfPresent(Bool.self, forKey: .isNewDevice)
        self.seededFromMainWorkstation = try? c.decodeIfPresent(Bool.self, forKey: .seededFromMainWorkstation)
    }

    private enum CodingKeys: String, CodingKey {
        case shared, sharedSettings, device, deviceSettings, isNewDevice, seededFromMainWorkstation
    }
}
