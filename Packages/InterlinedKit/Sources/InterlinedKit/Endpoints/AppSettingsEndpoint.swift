import Foundation

/// Request builders for **Applications: synced settings + device registry**
/// (work-consolidation.md G17, GitHub issue #56) — the platform's own mechanism
/// for companion apps, and the sanctioned home for this app's preferences *and*
/// the Document Sync Agent's per-machine configuration, replacing purely local
/// `UserDefaults` state.
///
/// The model, per `/help/app-settings` and confirmed by live probe 2026-09-16:
/// - **account-scoped settings** follow the account to every machine;
/// - **device-scoped settings** stay pinned to one computer;
/// - one machine is the **main workstation** (`isDefault` on the wire), whose
///   config seeds a new device on first sign-in;
/// - devices can be renamed, promoted, or deregistered.
///
/// The `appKey` is **not** registered with the backend — the segment is a
/// free-form namespace, proven by probe (an invented key answers
/// `200 {"devices":[]}` rather than rejecting). It is nonetheless passed in
/// rather than hard-coded, because the value in use
/// (`AppEnvironment.appSettingsKey` = `"interlinedlist-macos"`) **must stay
/// stable**: changing it orphans every setting already stored under the old one.
///
/// Every settings write is **compare-and-set** — see `WriteAppSettingsRequest`.
public enum AppSettings {

    // MARK: - Account-wide settings

    /// `GET /api/user/app-settings/{appKey}` — the account-wide document.
    ///
    /// 404 when nothing is stored yet. That is the ordinary first-run answer,
    /// not a failure; the domain layer maps it to "no document".
    public static func shared(appKey: String) -> Request<AppSettingsDocumentDTO> {
        Request(method: .get, path: "/api/user/app-settings/\(appKey)", auth: .bearer)
    }

    /// `PUT /api/user/app-settings/{appKey}` — compare-and-set replace.
    ///
    /// This **replaces** the document; it does not merge. Verified live: a PUT
    /// carrying only `{"theme":"light"}` over a stored
    /// `{"theme":"dark","sidebarWidth":280}` left `sidebarWidth` deleted.
    public static func writeShared(
        appKey: String,
        _ body: WriteAppSettingsRequest
    ) -> Request<AppSettingsDocumentDTO> {
        Request(
            method: .put,
            path: "/api/user/app-settings/\(appKey)",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `DELETE /api/user/app-settings/{appKey}` — drop the account-wide
    /// document. Idempotent; never 404s. Leaves per-device documents alone.
    public static func deleteShared(appKey: String) -> Request<DeleteAppSettingsResponse> {
        Request(method: .delete, path: "/api/user/app-settings/\(appKey)", auth: .bearer)
    }

    // MARK: - Bootstrap

    /// `GET /api/user/app-settings/{appKey}/bootstrap?deviceId=…` — the single
    /// launch call: the best available settings document for this machine, plus
    /// a `source` saying where it came from.
    ///
    /// `deviceId` is required; omitting it is `400 {"error":"Invalid deviceId"}`.
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
    /// under this app key. Answers `200 {"devices":[]}` when there are none, so
    /// unlike the settings routes this one never 404s on a fresh account.
    public static func devices(appKey: String) -> Request<AppDevicesResponse> {
        Request(method: .get, path: "/api/user/app-settings/\(appKey)/devices", auth: .bearer)
    }

    /// `POST /api/user/app-settings/{appKey}/devices` — register this machine.
    ///
    /// The **first** device registered is made the main workstation
    /// automatically (verified live: the first POST answered `isDefault:true`,
    /// the second `isDefault:false`).
    public static func registerDevice(
        appKey: String,
        _ body: RegisterDeviceRequest
    ) -> Request<AppDeviceEnvelope> {
        Request(
            method: .post,
            path: "/api/user/app-settings/\(appKey)/devices",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `PATCH /api/user/app-settings/{appKey}/devices/{deviceId}` — rename a
    /// device or promote it to main workstation.
    ///
    /// Promotion demotes the previous holder server-side; verified live by
    /// promoting a second device and re-listing.
    public static func updateDevice(
        appKey: String,
        deviceId: String,
        _ body: UpdateDeviceRequest
    ) -> Request<AppDeviceEnvelope> {
        Request(
            method: .patch,
            path: "/api/user/app-settings/\(appKey)/devices/\(deviceId)",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `DELETE /api/user/app-settings/{appKey}/devices/{deviceId}` — deregister.
    ///
    /// Deletes that machine's per-device settings along with it (verified live:
    /// re-registering the same id afterwards read back `404` for its settings),
    /// and leaves the account-wide document untouched. The response names any
    /// machine auto-promoted to fill a vacated main-workstation role.
    public static func deleteDevice(appKey: String, deviceId: String) -> Request<DeleteDeviceResponse> {
        Request(
            method: .delete,
            path: "/api/user/app-settings/\(appKey)/devices/\(deviceId)",
            auth: .bearer
        )
    }

    // MARK: - Per-device settings

    /// `GET …/devices/{deviceId}/settings` — one machine's pinned document.
    /// 404 when that machine has never written one.
    public static func deviceSettings(appKey: String, deviceId: String) -> Request<AppSettingsDocumentDTO> {
        Request(
            method: .get,
            path: "/api/user/app-settings/\(appKey)/devices/\(deviceId)/settings",
            auth: .bearer
        )
    }

    /// `PUT …/devices/{deviceId}/settings` — compare-and-set replace.
    ///
    /// A 404 here means **the device is not registered**
    /// (`{"error":"device not registered"}`), not "no document yet" —
    /// `baseVersion: 0` creates the document happily. Retrying will not fix it;
    /// registering the device will.
    public static func writeDeviceSettings(
        appKey: String,
        deviceId: String,
        _ body: WriteAppSettingsRequest
    ) -> Request<AppSettingsDocumentDTO> {
        Request(
            method: .put,
            path: "/api/user/app-settings/\(appKey)/devices/\(deviceId)/settings",
            body: .json(body),
            auth: .bearer
        )
    }
}
