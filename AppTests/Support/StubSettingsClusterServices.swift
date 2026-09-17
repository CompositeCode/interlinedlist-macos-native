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

/// Stub for the Applications pane (work-consolidation.md G17, GitHub issue #56).
///
/// Every surface is queue-driven so a test can script a sequence — which the
/// remove path needs, because it lists the registry twice: once to load the
/// pane and again to reconcile after the deletion.
final class StubAppSettingsService: AppSettingsServicing, @unchecked Sendable {

    private let lock = NSLock()
    private var deviceOutcomes: [Result<[AppDevice], Error>] = []
    private var mutationOutcomes: [Result<AppDevice, Error>] = []
    private var removalOutcomes: [Result<DeviceRemovalOutcome, Error>] = []
    private var sharedDocumentOutcomes: [Result<AppSettingsDocument?, Error>] = []
    private var deviceDocumentOutcomes: [Result<AppSettingsDocument?, Error>] = []
    private var copyOutcomes: [Result<AppSettingsDocument, Error>] = []
    private var deleteSharedOutcomes: [Result<Bool, Error>] = []

    private(set) var deregisteredIDs: [String] = []
    private(set) var renamedTo: [String: String] = [:]
    private(set) var promotedIDs: [String] = []
    private(set) var inspectedIDs: [String] = []
    private(set) var registeredIDs: [String] = []
    private(set) var copiedFromIDs: [String] = []
    private(set) var deleteSharedCallCount = 0
    /// How many times the registry was listed — the remove path must reconcile.
    private(set) var devicesCallCount = 0

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

    func enqueueRemoval(_ outcome: DeviceRemovalOutcome) {
        lock.withLock { removalOutcomes.append(.success(outcome)) }
    }

    func enqueueRemoval(failure: Error) {
        lock.withLock { removalOutcomes.append(.failure(failure)) }
    }

    func enqueueSharedDocument(_ document: AppSettingsDocument?) {
        lock.withLock { sharedDocumentOutcomes.append(.success(document)) }
    }

    func enqueueSharedDocument(failure: Error) {
        lock.withLock { sharedDocumentOutcomes.append(.failure(failure)) }
    }

    func enqueueDeviceDocument(_ document: AppSettingsDocument?) {
        lock.withLock { deviceDocumentOutcomes.append(.success(document)) }
    }

    func enqueueDeviceDocument(failure: Error) {
        lock.withLock { deviceDocumentOutcomes.append(.failure(failure)) }
    }

    func enqueueCopyToShared(success: AppSettingsDocument) {
        lock.withLock { copyOutcomes.append(.success(success)) }
    }

    func enqueueCopyToShared(failure: Error) {
        lock.withLock { copyOutcomes.append(.failure(failure)) }
    }

    func enqueueDeleteShared(_ deleted: Bool = true) {
        lock.withLock { deleteSharedOutcomes.append(.success(deleted)) }
    }

    func enqueueDeleteShared(failure: Error) {
        lock.withLock { deleteSharedOutcomes.append(.failure(failure)) }
    }

    // MARK: Settings documents

    func bootstrap(deviceID: String) async throws -> AppSettingsSeed { AppSettingsSeed() }

    func sharedDocument() async throws -> AppSettingsDocument? {
        try lock.withLock {
            guard !sharedDocumentOutcomes.isEmpty else { return nil }
            return try sharedDocumentOutcomes.removeFirst().get()
        }
    }

    func writeSharedSettings(_ bag: AppSettingsBag, baseVersion: Int) async throws -> AppSettingsDocument {
        AppSettingsDocument(bag: bag, version: baseVersion + 1)
    }

    @discardableResult
    func deleteSharedSettings() async throws -> Bool {
        try lock.withLock {
            deleteSharedCallCount += 1
            guard !deleteSharedOutcomes.isEmpty else { return true }
            return try deleteSharedOutcomes.removeFirst().get()
        }
    }

    func deviceDocument(deviceID: String) async throws -> AppSettingsDocument? {
        try lock.withLock {
            inspectedIDs.append(deviceID)
            guard !deviceDocumentOutcomes.isEmpty else { return nil }
            return try deviceDocumentOutcomes.removeFirst().get()
        }
    }

    func writeDeviceSettings(
        _ bag: AppSettingsBag,
        deviceID: String,
        baseVersion: Int
    ) async throws -> AppSettingsDocument {
        AppSettingsDocument(bag: bag, version: baseVersion + 1, scope: .device(id: deviceID))
    }

    func copyDeviceSettingsToShared(deviceID: String) async throws -> AppSettingsDocument {
        try lock.withLock {
            copiedFromIDs.append(deviceID)
            guard !copyOutcomes.isEmpty else { return AppSettingsDocument() }
            return try copyOutcomes.removeFirst().get()
        }
    }

    // MARK: Device registry

    func devices() async throws -> [AppDevice] {
        try lock.withLock {
            devicesCallCount += 1
            guard !deviceOutcomes.isEmpty else { return [] }
            return try deviceOutcomes.removeFirst().get()
        }
    }

    func registerDevice(deviceID: String, name: String, platform: String) async throws -> AppDevice {
        try lock.withLock {
            registeredIDs.append(deviceID)
            guard !mutationOutcomes.isEmpty else {
                return AppDevice(id: deviceID, name: name, platform: platform)
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

    @discardableResult
    func deregisterDevice(deviceID: String) async throws -> DeviceRemovalOutcome {
        try lock.withLock {
            deregisteredIDs.append(deviceID)
            guard !removalOutcomes.isEmpty else { return DeviceRemovalOutcome(deleted: true) }
            return try removalOutcomes.removeFirst().get()
        }
    }
}

// MARK: - G20 tags

final class StubTagsService: TagsServicing, @unchecked Sendable {

    private let lock = NSLock()
    private var trendingOutcomes: [Result<[TrendingTag], Error>] = []
    private var suggestionOutcomes: [Result<[String], Error>] = []
    private(set) var requestedPrefixes: [String] = []

    func enqueueTrending(success: [TrendingTag]) {
        lock.withLock { trendingOutcomes.append(.success(success)) }
    }

    func enqueueTrending(failure: Error) {
        lock.withLock { trendingOutcomes.append(.failure(failure)) }
    }

    func enqueueSuggestions(success: [String]) {
        lock.withLock { suggestionOutcomes.append(.success(success)) }
    }

    func enqueueSuggestions(failure: Error) {
        lock.withLock { suggestionOutcomes.append(.failure(failure)) }
    }

    func trending(limit: Int?) async throws -> [TrendingTag] {
        try lock.withLock {
            guard !trendingOutcomes.isEmpty else { return [] }
            return try trendingOutcomes.removeFirst().get()
        }
    }

    func suggestions(prefix: String, limit: Int?) async throws -> [String] {
        try lock.withLock {
            requestedPrefixes.append(prefix)
            guard !suggestionOutcomes.isEmpty else { return [] }
            return try suggestionOutcomes.removeFirst().get()
        }
    }
}
