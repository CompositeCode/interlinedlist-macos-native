// StubSettingsClusterServices
//
// Test doubles for the Settings-cluster services (work-consolidation.md
// G17-G20), so the panes' view models are driven without networking.
//
// Each stub follows `StubUserService`'s shape: a lock-guarded outcome queue,
// `@unchecked Sendable` because the lock provides the safety the compiler
// cannot see.

import Foundation
import InterlinedDomain

// MARK: - G19 sessions

final class StubSessionsService: SessionsServicing, @unchecked Sendable {

    private let lock = NSLock()
    private var listOutcomes: [Result<[ActiveSession], Error>] = []
    private var revokeOutcomes: [Result<Void, Error>] = []
    private(set) var revokedIDs: [String] = []

    func enqueueSessions(success: [ActiveSession]) {
        lock.withLock { listOutcomes.append(.success(success)) }
    }

    func enqueueSessions(failure: Error) {
        lock.withLock { listOutcomes.append(.failure(failure)) }
    }

    func enqueueRevoke(failure: Error? = nil) {
        lock.withLock { revokeOutcomes.append(failure.map { .failure($0) } ?? .success(())) }
    }

    func sessions() async throws -> [ActiveSession] {
        try lock.withLock {
            guard !listOutcomes.isEmpty else { return [] }
            return try listOutcomes.removeFirst().get()
        }
    }

    func revoke(sessionID: String) async throws {
        try lock.withLock {
            revokedIDs.append(sessionID)
            guard !revokeOutcomes.isEmpty else { return }
            return try revokeOutcomes.removeFirst().get()
        }
    }
}

// MARK: - G18 notification preferences

final class StubNotificationPreferencesService: NotificationPreferencesServicing, @unchecked Sendable {

    private let lock = NSLock()
    private var catalogueOutcomes: [Result<[NotificationEventPreference], Error>] = []
    private var updateOutcomes: [Result<[NotificationEventPreference], Error>] = []
    /// What the last `update` was asked to write — lets a test assert that only
    /// changed events are sent.
    private(set) var lastUpdatePayload: [NotificationEventPreference] = []

    func enqueueCatalogue(success: [NotificationEventPreference]) {
        lock.withLock { catalogueOutcomes.append(.success(success)) }
    }

    func enqueueCatalogue(failure: Error) {
        lock.withLock { catalogueOutcomes.append(.failure(failure)) }
    }

    func enqueueUpdate(success: [NotificationEventPreference]) {
        lock.withLock { updateOutcomes.append(.success(success)) }
    }

    func enqueueUpdate(failure: Error) {
        lock.withLock { updateOutcomes.append(.failure(failure)) }
    }

    func catalogue() async throws -> [NotificationEventPreference] {
        try lock.withLock {
            guard !catalogueOutcomes.isEmpty else { return [] }
            return try catalogueOutcomes.removeFirst().get()
        }
    }

    func update(_ events: [NotificationEventPreference]) async throws -> [NotificationEventPreference] {
        try lock.withLock {
            lastUpdatePayload = events
            guard !updateOutcomes.isEmpty else { return events }
            return try updateOutcomes.removeFirst().get()
        }
    }
}

// MARK: - G17 app settings + device registry

final class StubAppSettingsService: AppSettingsServicing, @unchecked Sendable {

    private let lock = NSLock()
    private var deviceOutcomes: [Result<[AppDevice], Error>] = []
    private var mutationOutcomes: [Result<AppDevice, Error>] = []
    private var deregisterOutcomes: [Result<Void, Error>] = []
    private(set) var deregisteredIDs: [String] = []
    private(set) var renamedTo: [String: String] = [:]
    private(set) var promotedIDs: [String] = []

    func enqueueDevices(success: [AppDevice]) {
        lock.withLock { deviceOutcomes.append(.success(success)) }
    }

    func enqueueDevices(failure: Error) {
        lock.withLock { deviceOutcomes.append(.failure(failure)) }
    }

    func enqueueMutation(success: AppDevice) {
        lock.withLock { mutationOutcomes.append(.success(success)) }
    }

    func enqueueMutation(failure: Error) {
        lock.withLock { mutationOutcomes.append(.failure(failure)) }
    }

    func enqueueDeregister(failure: Error? = nil) {
        lock.withLock { deregisterOutcomes.append(failure.map { .failure($0) } ?? .success(())) }
    }

    // MARK: Settings surface — unused by the Devices pane, minimally satisfied.

    func bootstrap(deviceID: String) async throws -> AppSettingsSnapshot { AppSettingsSnapshot() }
    func sharedSettings() async throws -> AppSettingsBag { AppSettingsBag() }
    func writeSharedSettings(_ bag: AppSettingsBag) async throws -> AppSettingsBag { bag }
    func deviceSettings(deviceID: String) async throws -> AppSettingsBag { AppSettingsBag() }
    func writeDeviceSettings(_ bag: AppSettingsBag, deviceID: String) async throws -> AppSettingsBag { bag }

    // MARK: Device registry

    func devices() async throws -> [AppDevice] {
        try lock.withLock {
            guard !deviceOutcomes.isEmpty else { return [] }
            return try deviceOutcomes.removeFirst().get()
        }
    }

    func registerDevice(deviceID: String, name: String?) async throws -> AppDevice {
        try lock.withLock {
            guard !mutationOutcomes.isEmpty else {
                return AppDevice(id: deviceID, name: name ?? deviceID)
            }
            return try mutationOutcomes.removeFirst().get()
        }
    }

    func renameDevice(deviceID: String, to name: String) async throws -> AppDevice {
        try lock.withLock {
            renamedTo[deviceID] = name
            guard !mutationOutcomes.isEmpty else { return AppDevice(id: deviceID, name: name) }
            return try mutationOutcomes.removeFirst().get()
        }
    }

    func makeMainWorkstation(deviceID: String) async throws -> AppDevice {
        try lock.withLock {
            promotedIDs.append(deviceID)
            guard !mutationOutcomes.isEmpty else {
                return AppDevice(id: deviceID, name: deviceID, isMainWorkstation: true)
            }
            return try mutationOutcomes.removeFirst().get()
        }
    }

    func deregisterDevice(deviceID: String) async throws {
        try lock.withLock {
            deregisteredIDs.append(deviceID)
            guard !deregisterOutcomes.isEmpty else { return }
            return try deregisterOutcomes.removeFirst().get()
        }
    }
}
