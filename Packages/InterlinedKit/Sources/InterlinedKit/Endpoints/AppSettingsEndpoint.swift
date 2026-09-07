import Foundation

/// Request builders for **Applications: synced settings + device registry**
/// (work-consolidation.md G17) — the platform's own mechanism for companion
/// apps, and the sanctioned home for this app's preferences *and* the Document
/// Sync Agent's per-machine configuration, replacing purely local
/// `UserDefaults` state.
///
/// The model, per `/help/app-settings`:
/// - **shared settings** follow the account to every machine;
/// - **per-device settings** stay pinned to one computer;
/// - one machine is the **main workstation**, whose config seeds a brand-new
///   device on first sign-in;
/// - devices can be renamed or deregistered.
///
/// ⚠️ **The `appKey` must be registered with the backend owner before this
/// ships** (stated prerequisite in the gap definition). `AppSettings` takes the
/// key as a parameter rather than hard-coding one, so registering a different
/// key later is a one-line change at the composition root.
///
/// ⚠️ Response shapes are **unverified** — see the note on `AppSettingsDTO`.
public enum AppSettings {

    // MARK: - Shared (account-wide) settings

    /// `GET /api/user/app-settings/{appKey}` — the account-wide shared settings.
    public static func shared(appKey: String) -> Request<AppSettingsDTO> {
        Request(method: .get, path: "/api/user/app-settings/\(appKey)", auth: .bearer)
    }

    /// `PUT /api/user/app-settings/{appKey}` — replace the shared settings.
    public static func writeShared(
        appKey: String,
        _ body: WriteAppSettingsRequest
    ) -> Request<AppSettingsDTO> {
        Request(
            method: .put,
            path: "/api/user/app-settings/\(appKey)",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `DELETE /api/user/app-settings/{appKey}` — drop all settings for the app.
    public static func deleteShared(appKey: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/user/app-settings/\(appKey)", auth: .bearer)
    }

    // MARK: - Bootstrap

    /// `GET /api/user/app-settings/{appKey}/bootstrap?deviceId=…` — the single
    /// launch call: shared settings + this machine's settings, seeding a new
    /// device from the main workstation.
    public static func bootstrap(appKey: String, deviceId: String) -> Request<AppSettingsBootstrapDTO> {
        Request(
            method: .get,
            path: "/api/user/app-settings/\(appKey)/bootstrap",
            query: [.string("deviceId", deviceId)],
            auth: .bearer
        )
    }

    // MARK: - Device registry

    /// `GET /api/user/app-settings/{appKey}/devices` — every machine registered
    /// under this app key.
    public static func devices(appKey: String) -> Request<AppDevicesResponse> {
        Request(method: .get, path: "/api/user/app-settings/\(appKey)/devices", auth: .bearer)
    }

    /// `POST /api/user/app-settings/{appKey}/devices` — register this machine.
    public static func registerDevice(
        appKey: String,
        _ body: RegisterDeviceRequest
    ) -> Request<AppDeviceDTO> {
        Request(
            method: .post,
            path: "/api/user/app-settings/\(appKey)/devices",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `PATCH /api/user/app-settings/{appKey}/devices/{deviceId}` — rename a
    /// device or promote it to main workstation.
    public static func updateDevice(
        appKey: String,
        deviceId: String,
        _ body: UpdateDeviceRequest
    ) -> Request<AppDeviceDTO> {
        Request(
            method: .patch,
            path: "/api/user/app-settings/\(appKey)/devices/\(deviceId)",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `DELETE /api/user/app-settings/{appKey}/devices/{deviceId}` — deregister.
    public static func deleteDevice(appKey: String, deviceId: String) -> Request<EmptyResponse> {
        Request(
            method: .delete,
            path: "/api/user/app-settings/\(appKey)/devices/\(deviceId)",
            auth: .bearer
        )
    }

    // MARK: - Per-device settings

    /// `GET …/devices/{deviceId}/settings` — one machine's pinned settings.
    public static func deviceSettings(appKey: String, deviceId: String) -> Request<AppSettingsDTO> {
        Request(
            method: .get,
            path: "/api/user/app-settings/\(appKey)/devices/\(deviceId)/settings",
            auth: .bearer
        )
    }

    /// `PUT …/devices/{deviceId}/settings` — replace one machine's settings.
    public static func writeDeviceSettings(
        appKey: String,
        deviceId: String,
        _ body: WriteAppSettingsRequest
    ) -> Request<AppSettingsDTO> {
        Request(
            method: .put,
            path: "/api/user/app-settings/\(appKey)/devices/\(deviceId)/settings",
            body: .json(body),
            auth: .bearer
        )
    }
}
