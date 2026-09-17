import Foundation
import InterlinedKit

/// The synced-settings + device-registry surface the App layer codes against
/// (work-consolidation.md G17, GitHub issue #56).
///
/// This is the sanctioned home for the app's preferences *and* the Document
/// Sync Agent's per-machine configuration, replacing purely local
/// `UserDefaults` state: **account** settings follow the account to every
/// machine, **device** settings stay pinned to one computer.
///
/// Reads answer an optional document: `nil` means "nothing stored yet", which
/// is the ordinary first-run state rather than a failure. Writes are
/// compare-and-set and therefore take the `baseVersion` the caller last read.
public protocol AppSettingsServicing: Sendable {

    /// The one launch call: the best settings this machine can start from, plus
    /// where they came from.
    func bootstrap(deviceID: String) async throws -> AppSettingsSeed

    // MARK: Account-wide settings

    /// The account-wide document, or nil when none is stored.
    func sharedDocument() async throws -> AppSettingsDocument?
    /// Replaces the account-wide document. `baseVersion` is the version last
    /// read, or 0 to create.
    func writeSharedSettings(_ bag: AppSettingsBag, baseVersion: Int) async throws -> AppSettingsDocument
    /// Deletes the account-wide document. Returns false when there was nothing
    /// to delete. Per-device documents are unaffected.
    @discardableResult
    func deleteSharedSettings() async throws -> Bool

    // MARK: Per-device settings

    /// One machine's document, or nil when that machine has stored none.
    func deviceDocument(deviceID: String) async throws -> AppSettingsDocument?
    func writeDeviceSettings(
        _ bag: AppSettingsBag,
        deviceID: String,
        baseVersion: Int
    ) async throws -> AppSettingsDocument

    /// Copies one machine's settings over the account-wide document,
    /// **replacing** it wholesale.
    func copyDeviceSettingsToShared(deviceID: String) async throws -> AppSettingsDocument

    // MARK: Device registry

    func devices() async throws -> [AppDevice]
    func registerDevice(deviceID: String, name: String, platform: String) async throws -> AppDevice
    func renameDevice(deviceID: String, to name: String) async throws -> AppDevice
    func makeMainWorkstation(deviceID: String) async throws -> AppDevice
    @discardableResult
    func deregisterDevice(deviceID: String) async throws -> DeviceRemovalOutcome
}

public extension AppSettingsServicing {
    /// macOS is the only platform this client runs on, so callers rarely care.
    func registerDevice(deviceID: String, name: String) async throws -> AppDevice {
        try await registerDevice(deviceID: deviceID, name: name, platform: "macos")
    }
}

/// Talks to `/api/user/app-settings/{appKey}/…`.
///
/// The `appKey` is injected at the composition root rather than hard-coded, so
/// tests can use their own. The production value
/// (`AppEnvironment.appSettingsKey`) **must not change**: the key is the
/// namespace every stored setting lives under, and a new one orphans all of it.
public final class AppSettingsService: AppSettingsServicing {

    private let api: APIClientProtocol
    private let appKey: String

    public init(api: APIClientProtocol, appKey: String) {
        self.api = api
        self.appKey = appKey
    }

    // MARK: - Bootstrap

    public func bootstrap(deviceID: String) async throws -> AppSettingsSeed {
        do {
            let dto = try await api.send(AppSettings.bootstrap(appKey: appKey, deviceId: deviceID))
            return AppSettingsSeed(from: dto)
        } catch let error as APIError {
            // Verified live 2026-09-16: with nothing stored anywhere the route
            // answers `404 {"source":"none"}`. That is the ordinary first-run
            // state for the whole account — not a failure — so it maps to an
            // empty seed and the caller just starts from defaults.
            guard case .notFound = error else { throw error }
            return AppSettingsSeed(origin: .none)
        }
    }

    // MARK: - Account-wide settings

    public func sharedDocument() async throws -> AppSettingsDocument? {
        // Verified live 2026-09-16: an app key with nothing stored answers 404,
        // while `OPTIONS` on the same path reports
        // `allow: DELETE, GET, HEAD, OPTIONS, PUT` — the route exists, the
        // bucket is simply empty. Treating that as an error would make every
        // fresh account show a failure instead of empty settings.
        try await documentOrNil { AppSettings.shared(appKey: self.appKey) }
    }

    public func writeSharedSettings(
        _ bag: AppSettingsBag,
        baseVersion: Int
    ) async throws -> AppSettingsDocument {
        try await write {
            AppSettings.writeShared(
                appKey: self.appKey,
                WriteAppSettingsRequest(settings: bag.payload, baseVersion: baseVersion)
            )
        }
    }

    @discardableResult
    public func deleteSharedSettings() async throws -> Bool {
        // No 404 mapping here on purpose: verified live, this delete is
        // idempotent and answers `{"deleted":false}` rather than 404 when there
        // was nothing stored. A 404 from this route would be a real fault.
        try await api.send(AppSettings.deleteShared(appKey: appKey)).deleted
    }

    // MARK: - Per-device settings

    public func deviceDocument(deviceID: String) async throws -> AppSettingsDocument? {
        try await documentOrNil {
            AppSettings.deviceSettings(appKey: self.appKey, deviceId: deviceID)
        }
    }

    public func writeDeviceSettings(
        _ bag: AppSettingsBag,
        deviceID: String,
        baseVersion: Int
    ) async throws -> AppSettingsDocument {
        do {
            return try await write {
                AppSettings.writeDeviceSettings(
                    appKey: self.appKey,
                    deviceId: deviceID,
                    WriteAppSettingsRequest(settings: bag.payload, baseVersion: baseVersion)
                )
            }
        } catch let error as APIError {
            // A 404 from the *write* route is not "no document yet" —
            // `baseVersion: 0` creates one happily. It means the device is not
            // registered (`{"error":"device not registered"}`), which retrying
            // will never fix. Mapping it to an empty document the way the read
            // path does would silently discard the user's settings.
            guard case .notFound = error else { throw error }
            throw AppSettingsError.deviceNotRegistered
        }
    }

    public func copyDeviceSettingsToShared(deviceID: String) async throws -> AppSettingsDocument {
        guard let source = try await deviceDocument(deviceID: deviceID) else {
            throw AppSettingsError.noSettingsToCopy
        }
        // Read the destination purely for its version. The write is a
        // compare-and-set replace, so it needs the version that is current
        // *now*, not one cached from an earlier screen refresh.
        let destinationVersion = try await sharedDocument()?.version ?? 0
        return try await writeSharedSettings(source.bag, baseVersion: destinationVersion)
    }

    // MARK: - Device registry

    public func devices() async throws -> [AppDevice] {
        let response = try await api.send(AppSettings.devices(appKey: appKey))
        return response.devices.map(AppDevice.init(from:))
    }

    // No default for `platform` here: the protocol extension already supplies
    // the two-argument spelling, and a default would make both visible and the
    // call ambiguous.
    public func registerDevice(
        deviceID: String,
        name: String,
        platform: String
    ) async throws -> AppDevice {
        let envelope = try await api.send(
            AppSettings.registerDevice(
                appKey: appKey,
                RegisterDeviceRequest(deviceId: deviceID, deviceName: name, platform: platform)
            )
        )
        return AppDevice(from: envelope.device)
    }

    public func renameDevice(deviceID: String, to name: String) async throws -> AppDevice {
        let envelope = try await api.send(
            AppSettings.updateDevice(
                appKey: appKey,
                deviceId: deviceID,
                UpdateDeviceRequest(deviceName: name)
            )
        )
        return AppDevice(from: envelope.device)
    }

    public func makeMainWorkstation(deviceID: String) async throws -> AppDevice {
        // Sends only the flag — a PATCH that also carried `deviceName` would
        // clobber a rename made on another machine between this client's read
        // and its write.
        let envelope = try await api.send(
            AppSettings.updateDevice(
                appKey: appKey,
                deviceId: deviceID,
                UpdateDeviceRequest(isDefault: true)
            )
        )
        return AppDevice(from: envelope.device)
    }

    @discardableResult
    public func deregisterDevice(deviceID: String) async throws -> DeviceRemovalOutcome {
        let response = try await api.send(AppSettings.deleteDevice(appKey: appKey, deviceId: deviceID))
        return DeviceRemovalOutcome(
            deleted: response.deleted,
            promotedDeviceID: response.promotedDeviceId
        )
    }

    // MARK: - Shared plumbing

    /// Sends a settings read, mapping the "nothing stored yet" 404 to nil.
    /// Every other error still propagates — a 401 or a 500 is a real failure
    /// and must reach the UI.
    private func documentOrNil(
        _ build: @Sendable () -> Request<AppSettingsDocumentDTO>
    ) async throws -> AppSettingsDocument? {
        do {
            return AppSettingsDocument(from: try await api.send(build()))
        } catch let error as APIError {
            guard case .notFound = error else { throw error }
            return nil
        }
    }

    /// Sends a compare-and-set write, translating the 409 into a domain error.
    ///
    /// The 409 body carries the winning document under `current`, which would in
    /// principle let the client merge and retry without a re-read. It is
    /// deliberately **not** plumbed through: `APIClient` reduces every non-2xx
    /// body to a message string, so surfacing `current` means teaching the
    /// client to carry typed error payloads — a change to every endpoint's
    /// error path, far outside this pane. Re-reading costs one request and the
    /// blob is opaque, so there is nothing to merge field-by-field anyway.
    private func write(
        _ build: @Sendable () -> Request<AppSettingsDocumentDTO>
    ) async throws -> AppSettingsDocument {
        do {
            return AppSettingsDocument(from: try await api.send(build()))
        } catch let error as APIError {
            // 409 is not one of the statuses `APIError` narrows, so it arrives
            // as `.httpStatus`.
            guard case .httpStatus(let code, _) = error, code == 409 else { throw error }
            throw AppSettingsError.versionConflict
        }
    }
}

// MARK: - Mapping

extension AppSettingsDocument {
    init(from dto: AppSettingsDocumentDTO) {
        self.init(
            bag: AppSettingsBag(storage: dto.settings),
            version: dto.version,
            updatedAt: dto.updatedAt,
            // The wire says `"account"` for the user-wide document and
            // `"device"` for a pinned one; anything unrecognised is treated as
            // account-wide, which is the safe reading — a device document
            // always names its device.
            scope: dto.deviceId.map(AppSettingsDocument.Scope.device(id:)) ?? .account,
            schemaVersion: dto.schemaVersion
        )
    }
}

extension AppDevice {
    public init(from dto: AppDeviceDTO) {
        self.init(
            id: dto.deviceId,
            // A blank name would render as an empty row with nothing to click,
            // so fall back to the id the user can at least match against.
            name: dto.deviceName.isEmpty ? dto.deviceId : dto.deviceName,
            isMainWorkstation: dto.isDefault,
            platform: dto.platform,
            lastSeenAt: dto.lastSeenAt,
            appVersion: dto.appVersion,
            osVersion: dto.osVersion,
            hasDeviceSettings: dto.hasDeviceSettings
        )
    }
}

extension AppSettingsSeed {
    init(from dto: AppSettingsBootstrapDTO) {
        let origin: AppSettingsOrigin
        switch dto.source {
        case .own:
            origin = .own
        case .defaultDevice:
            origin = .mainWorkstation(
                deviceID: dto.defaultDeviceId,
                deviceName: dto.defaultDeviceName
            )
        case .account:
            origin = .account
        case .none:
            origin = .none
        }
        self.init(origin: origin, document: dto.document.map(AppSettingsDocument.init(from:)))
    }
}
