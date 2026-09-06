// DevicesViewModel
//
// Drives Settings ▸ Devices (work-consolidation.md G17) — the machines
// registered under this app's key, with rename, "make main workstation", and
// deregister actions.
//
// The main workstation matters because its configuration seeds a brand-new
// device on first sign-in, so promoting one is a real, user-visible decision
// rather than cosmetic.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class DevicesViewModel {

    private let service: AppSettingsServicing?
    /// This machine's stable id, so the list can mark "This Mac".
    private let currentDeviceID: String

    private(set) var devices: [AppDevice] = []
    private(set) var isLoading = false
    /// The device id with an action in flight, so only that row shows progress.
    private(set) var busyID: String?
    private(set) var error: Error?

    /// True when no `appKey` is registered yet (see `AppEnvironment.appSettingsKey`).
    var isUnavailable: Bool { service == nil }

    init(service: AppSettingsServicing?, currentDeviceID: String) {
        self.service = service
        self.currentDeviceID = currentDeviceID
    }

    func isCurrentDevice(_ device: AppDevice) -> Bool { device.id == currentDeviceID }

    func load() async {
        guard let service else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            // This Mac first, then the main workstation, then by name — the two
            // rows a user acts on are the ones they can identify.
            devices = try await service.devices().sorted { lhs, rhs in
                if isCurrentDevice(lhs) != isCurrentDevice(rhs) { return isCurrentDevice(lhs) }
                if lhs.isMainWorkstation != rhs.isMainWorkstation { return lhs.isMainWorkstation }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        } catch {
            self.error = error
        }
    }

    func rename(_ device: AppDevice, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let service, busyID == nil, !trimmed.isEmpty, trimmed != device.name else { return }
        busyID = device.id
        error = nil
        defer { busyID = nil }
        do {
            let updated = try await service.renameDevice(deviceID: device.id, to: trimmed)
            replace(updated)
        } catch {
            self.error = error
        }
    }

    func makeMainWorkstation(_ device: AppDevice) async {
        guard let service, busyID == nil, !device.isMainWorkstation else { return }
        busyID = device.id
        error = nil
        defer { busyID = nil }
        do {
            let updated = try await service.makeMainWorkstation(deviceID: device.id)
            // Exactly one device holds the flag, so clear it locally everywhere
            // else rather than re-fetching the whole registry.
            devices = devices.map { existing in
                guard existing.id != updated.id, existing.isMainWorkstation else { return existing }
                return AppDevice(
                    id: existing.id,
                    name: existing.name,
                    isMainWorkstation: false,
                    createdAt: existing.createdAt,
                    lastSeenAt: existing.lastSeenAt
                )
            }
            replace(updated)
        } catch {
            self.error = error
        }
    }

    func deregister(_ device: AppDevice) async {
        guard let service, busyID == nil else { return }
        busyID = device.id
        error = nil
        defer { busyID = nil }
        do {
            try await service.deregisterDevice(deviceID: device.id)
            devices.removeAll { $0.id == device.id }
        } catch {
            self.error = error
        }
    }

    private func replace(_ device: AppDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index] = device
    }
}
