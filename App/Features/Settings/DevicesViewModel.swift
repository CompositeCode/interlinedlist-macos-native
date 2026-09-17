// DevicesViewModel
//
// Drives Settings ▸ Applications (work-consolidation.md G17, GitHub issue #56)
// — the machines registered under this app's key, plus the settings documents
// they share and pin.
//
// The six actions `/help/app-settings` documents: rename a machine, promote one
// to main workstation, remove one, inspect the shared and per-machine settings,
// copy a machine's settings to shared, and delete the shared settings.
//
// The main workstation matters because its configuration seeds a brand-new
// device on first sign-in, so promoting one is a real, user-visible decision
// rather than cosmetic.
//
// This section is free — there is deliberately no capability gate here.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class DevicesViewModel {

    /// One machine's settings document, loaded on demand for the inspector.
    struct Inspection: Equatable {
        let device: AppDevice
        /// nil once loaded means the machine has stored no settings of its own.
        var document: AppSettingsDocument?
        var isLoading: Bool
        var error: String?
    }

    /// Identifies the shared-settings row for `busyID`, which otherwise holds a
    /// device id. A reserved sentinel rather than a second flag so that "only
    /// one mutation at a time" stays a single invariant.
    static let sharedSettingsRowID = "\u{0}shared-settings"

    private let service: AppSettingsServicing?
    /// This machine's stable id, so the list can mark "This Mac".
    private let currentDeviceID: String
    /// The name to register this machine under if it is not in the registry.
    private let currentDeviceName: String

    private(set) var devices: [AppDevice] = []
    /// The account-wide document, nil when nothing is stored yet.
    private(set) var sharedDocument: AppSettingsDocument?
    private(set) var isLoading = false
    /// The row with an action in flight, so only that row shows progress.
    private(set) var busyID: String?
    private(set) var error: Error?

    /// True when the main workstation was removed and this client could not
    /// learn who inherited the role. The badge must then show nothing rather
    /// than a stale flag pointing at a machine that no longer holds it.
    private(set) var mainWorkstationIsUnknown = false

    /// The machine whose settings the inspector is showing, if any.
    private(set) var inspection: Inspection?

    /// True when no `appKey` is configured in this build
    /// (see `AppEnvironment.appSettingsKey`).
    var isUnavailable: Bool { service == nil }

    init(
        service: AppSettingsServicing?,
        currentDeviceID: String,
        currentDeviceName: String = ""
    ) {
        self.service = service
        self.currentDeviceID = currentDeviceID
        self.currentDeviceName = currentDeviceName
    }

    func isCurrentDevice(_ device: AppDevice) -> Bool { device.id == currentDeviceID }

    // MARK: - Loading

    func load() async {
        guard let service else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            // The registry and the account document are independent reads, so
            // overlap them — this pane is behind a tab the user just clicked.
            async let devicesTask = service.devices()
            async let sharedTask = service.sharedDocument()
            let (loaded, shared) = try await (devicesTask, sharedTask)
            apply(try await registeringThisMacIfAbsent(in: loaded, using: service))
            sharedDocument = shared
            // A successful list is authoritative about who holds the role.
            mainWorkstationIsUnknown = false
        } catch {
            self.error = error
        }
    }

    /// Adds this Mac to the registry the first time the pane is opened on it.
    ///
    /// Nothing else registers this machine, so without this the pane lists every
    /// *other* computer and never the one the user is sitting at — and the
    /// per-machine settings half has no row to hang off.
    ///
    /// **Only when absent.** Verified live 2026-09-16 that `POST …/devices` is
    /// an upsert keyed on `deviceId`: re-posting an existing id does not
    /// duplicate the row, it overwrites `deviceName`. Registering
    /// unconditionally would therefore reset the machine's name to this Mac's
    /// hostname every single time the pane was opened, silently undoing any
    /// rename the user had made.
    ///
    /// A failure here is swallowed deliberately: the registry itself loaded, and
    /// failing to add this Mac must not blank a list of machines the user came
    /// here to manage.
    private func registeringThisMacIfAbsent(
        in loaded: [AppDevice],
        using service: AppSettingsServicing
    ) async throws -> [AppDevice] {
        guard !loaded.contains(where: { $0.id == currentDeviceID }),
              !currentDeviceName.isEmpty
        else { return loaded }
        guard let registered = try? await service.registerDevice(
            deviceID: currentDeviceID,
            name: currentDeviceName
        ) else { return loaded }
        return loaded + [registered]
    }

    /// This Mac first, then the main workstation, then by name — the two rows a
    /// user acts on are the ones they can identify.
    private func apply(_ loaded: [AppDevice]) {
        devices = loaded.sorted { lhs, rhs in
            if isCurrentDevice(lhs) != isCurrentDevice(rhs) { return isCurrentDevice(lhs) }
            if lhs.isMainWorkstation != rhs.isMainWorkstation { return lhs.isMainWorkstation }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Device actions

    func rename(_ device: AppDevice, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let service, busyID == nil, !trimmed.isEmpty, trimmed != device.name else { return }
        await mutate(device.id) {
            let updated = try await service.renameDevice(deviceID: device.id, to: trimmed)
            self.replace(updated)
        }
    }

    func makeMainWorkstation(_ device: AppDevice) async {
        guard let service, busyID == nil, !device.isMainWorkstation else { return }
        await mutate(device.id) {
            let updated = try await service.makeMainWorkstation(deviceID: device.id)
            // Exactly one device holds the flag and the server enforces it by
            // demoting the previous holder, so clear it locally everywhere else
            // rather than spending a second round-trip to learn what we already
            // know.
            self.devices = self.devices.map { existing in
                existing.id == updated.id || !existing.isMainWorkstation
                    ? existing
                    : existing.settingMainWorkstation(false)
            }
            self.replace(updated)
            self.mainWorkstationIsUnknown = false
        }
    }

    /// Removes a machine from the registry. Its per-machine settings go with
    /// it; the shared settings are untouched.
    func deregister(_ device: AppDevice) async {
        guard let service, busyID == nil else { return }
        let wasMain = device.isMainWorkstation
        await mutate(device.id) {
            let outcome = try await service.deregisterDevice(deviceID: device.id)
            self.devices.removeAll { $0.id == device.id }
            if self.inspection?.device.id == device.id { self.inspection = nil }

            if let promoted = outcome.promotedDeviceID {
                // The server names the machine it promoted, so there is nothing
                // to guess at and nothing to re-read to find out.
                self.devices = self.devices.map {
                    $0.settingMainWorkstation($0.id == promoted)
                }
            } else if wasMain && !self.devices.isEmpty {
                // The removed machine held the role, the server did not say who
                // took it over, and someone must have. Showing the old flags
                // would assert something we no longer know to be true.
                self.mainWorkstationIsUnknown = true
            }

            // Refetch so `hasDeviceSettings` and last-seen times reconcile — and
            // so an unknown main workstation resolves. Deliberately not through
            // `load()`: a failure here must not raise an error banner, because
            // the removal itself succeeded. The unknown badge is how a failed
            // reconcile shows up.
            if let reloaded = try? await service.devices() {
                self.apply(reloaded)
                self.mainWorkstationIsUnknown = false
            }
        }
    }

    // MARK: - Settings documents

    /// Loads one machine's settings document for the inspector.
    func inspect(_ device: AppDevice) async {
        guard let service else { return }
        inspection = Inspection(device: device, document: nil, isLoading: true, error: nil)
        do {
            let document = try await service.deviceDocument(deviceID: device.id)
            // The user may have closed the inspector or opened another machine's
            // while this was in flight; do not stamp a stale answer over it.
            guard inspection?.device.id == device.id else { return }
            inspection = Inspection(device: device, document: document, isLoading: false, error: nil)
        } catch {
            guard inspection?.device.id == device.id else { return }
            inspection = Inspection(
                device: device,
                document: nil,
                isLoading: false,
                error: error.localizedDescription
            )
        }
    }

    func dismissInspection() { inspection = nil }

    /// Replaces the shared settings with this machine's own, wholesale.
    ///
    /// Not a merge: the write replaces the document, so any shared key this
    /// machine does not have is deleted. The view confirms destructively.
    func copySettingsToShared(from device: AppDevice) async {
        guard let service, busyID == nil else { return }
        await mutate(device.id) {
            self.sharedDocument = try await service.copyDeviceSettingsToShared(deviceID: device.id)
        }
    }

    func deleteSharedSettings() async {
        guard let service, busyID == nil else { return }
        await mutate(Self.sharedSettingsRowID) {
            try await service.deleteSharedSettings()
            // The document is gone; a re-read would only 404 back to the same
            // nil this already represents.
            self.sharedDocument = nil
        }
    }

    // MARK: - Plumbing

    /// Runs one mutation with the shared busy/error bookkeeping, so every action
    /// marks exactly one row busy and clears it on every exit path.
    private func mutate(_ rowID: String, _ body: () async throws -> Void) async {
        busyID = rowID
        error = nil
        defer { busyID = nil }
        do {
            try await body()
        } catch {
            self.error = error
        }
    }

    private func replace(_ device: AppDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index] = device
    }
}
