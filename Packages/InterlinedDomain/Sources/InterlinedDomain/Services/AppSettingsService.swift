import Foundation
import InterlinedKit

/// The synced-settings + device-registry surface the App layer codes against
/// (work-consolidation.md G17).
///
/// This is the sanctioned home for the app's preferences *and* the Document
/// Sync Agent's per-machine configuration, replacing purely local
/// `UserDefaults` state: **shared** settings follow the account to every
/// machine, **device** settings stay pinned to one computer.
public protocol AppSettingsServicing: Sendable {
    /// The one launch call: shared + this machine's settings, seeding a new
    /// device from the main workstation when the server has not seen it before.
    func bootstrap(deviceID: String) async throws -> AppSettingsSnapshot

    func sharedSettings() async throws -> AppSettingsBag
    func writeSharedSettings(_ bag: AppSettingsBag) async throws -> AppSettingsBag

    func deviceSettings(deviceID: String) async throws -> AppSettingsBag
    func writeDeviceSettings(_ bag: AppSettingsBag, deviceID: String) async throws -> AppSettingsBag

    func devices() async throws -> [AppDevice]
    func registerDevice(deviceID: String, name: String?) async throws -> AppDevice
    func renameDevice(deviceID: String, to name: String) async throws -> AppDevice
    func makeMainWorkstation(deviceID: String) async throws -> AppDevice
    func deregisterDevice(deviceID: String) async throws
}

/// Talks to `/api/user/app-settings/{appKey}/…`.
///
/// ⚠️ The `appKey` must be **registered with the backend owner** before this
/// ships (stated prerequisite in the G17 definition). It is injected at the
/// composition root rather than hard-coded here, so changing it is a one-line
/// edit and tests can use their own key.
///
/// ⚠️ The live response shapes are unverified — the DTOs decode tolerantly and
/// should be tightened after a live probe.
public final class AppSettingsService: AppSettingsServicing {

    private let api: APIClientProtocol
    private let appKey: String

    public init(api: APIClientProtocol, appKey: String) {
        self.api = api
        self.appKey = appKey
    }

    // MARK: - Bootstrap

    public func bootstrap(deviceID: String) async throws -> AppSettingsSnapshot {
        do {
            let dto = try await api.send(AppSettings.bootstrap(appKey: appKey, deviceId: deviceID))
            return AppSettingsSnapshot(from: dto)
        } catch let error as APIError {
            // Verified live 2026-09-06: an unregistered device answers
            // `404 {"source":"none"}`. That is the ordinary first-run state, not
            // a failure — a brand-new Mac has nothing stored yet — so it maps to
            // an empty snapshot flagged `isNewDevice`, and the caller registers.
            guard case .notFound = error else { throw error }
            return AppSettingsSnapshot(isNewDevice: true)
        }
    }

    // MARK: - Shared settings

    public func sharedSettings() async throws -> AppSettingsBag {
        // Verified live 2026-09-06: an app key with nothing stored yet answers
        // 404, while `OPTIONS` on the same path reports
        // `allow: DELETE, GET, HEAD, OPTIONS, PUT` — the route exists, the
        // bucket is simply empty. Treating that as an error would make every
        // fresh account show a failure instead of empty settings.
        try await emptyOnNotFound { AppSettings.shared(appKey: self.appKey) }
    }

    public func writeSharedSettings(_ bag: AppSettingsBag) async throws -> AppSettingsBag {
        let dto = try await api.send(
            AppSettings.writeShared(appKey: appKey, WriteAppSettingsRequest(settings: bag.payload))
        )
        return AppSettingsBag(from: dto)
    }

    // MARK: - Per-device settings

    public func deviceSettings(deviceID: String) async throws -> AppSettingsBag {
        try await emptyOnNotFound {
            AppSettings.deviceSettings(appKey: self.appKey, deviceId: deviceID)
        }
    }

    /// Sends a settings read, mapping the "nothing stored yet" 404 to an empty
    /// bag. Every other error still propagates — a 401 or a 500 is a real
    /// failure and must reach the UI.
    private func emptyOnNotFound(
        _ build: @Sendable () -> Request<AppSettingsDTO>
    ) async throws -> AppSettingsBag {
        do {
            return AppSettingsBag(from: try await api.send(build()))
        } catch let error as APIError {
            guard case .notFound = error else { throw error }
            return AppSettingsBag()
        }
    }

    public func writeDeviceSettings(
        _ bag: AppSettingsBag,
        deviceID: String
    ) async throws -> AppSettingsBag {
        let dto = try await api.send(
            AppSettings.writeDeviceSettings(
                appKey: appKey,
                deviceId: deviceID,
                WriteAppSettingsRequest(settings: bag.payload)
            )
        )
        return AppSettingsBag(from: dto)
    }

    // MARK: - Device registry

    public func devices() async throws -> [AppDevice] {
        let response = try await api.send(AppSettings.devices(appKey: appKey))
        return response.devices.map(AppDevice.init(from:))
    }

    public func registerDevice(deviceID: String, name: String?) async throws -> AppDevice {
        let dto = try await api.send(
            AppSettings.registerDevice(
                appKey: appKey,
                RegisterDeviceRequest(deviceId: deviceID, name: name)
            )
        )
        return AppDevice(from: dto)
    }

    public func renameDevice(deviceID: String, to name: String) async throws -> AppDevice {
        let dto = try await api.send(
            AppSettings.updateDevice(appKey: appKey, deviceId: deviceID, UpdateDeviceRequest(name: name))
        )
        return AppDevice(from: dto)
    }

    public func makeMainWorkstation(deviceID: String) async throws -> AppDevice {
        // Sends only the flag — a PATCH that also carried `name` would clobber a
        // rename made on another machine between this client's read and write.
        let dto = try await api.send(
            AppSettings.updateDevice(
                appKey: appKey,
                deviceId: deviceID,
                UpdateDeviceRequest(isMainWorkstation: true)
            )
        )
        return AppDevice(from: dto)
    }

    public func deregisterDevice(deviceID: String) async throws {
        try await api.sendVoid(AppSettings.deleteDevice(appKey: appKey, deviceId: deviceID))
    }
}
