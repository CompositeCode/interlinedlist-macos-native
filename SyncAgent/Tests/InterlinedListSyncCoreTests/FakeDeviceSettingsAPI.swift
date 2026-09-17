import Foundation
@testable import InterlinedListSyncCore

/// In-memory stand-in for the per-machine app-settings routes (GitHub issue
/// #104), with the server's real compare-and-set semantics: a write carrying a
/// `baseVersion` other than the stored one is rejected with the winning document
/// attached, exactly as the live `409 version_conflict` body does.
///
/// Modelling the conflict rather than stubbing it matters here — the whole point
/// of the store's retry is that it re-bases onto a document it did not write.
actor FakeDeviceSettingsAPI: DeviceSettingsAPI {

    struct WriteRecord: Sendable, Equatable {
        let deviceId: String
        let settings: [String: SettingsValue]
        let baseVersion: Int
    }

    private(set) var reads: [String] = []
    private(set) var writes: [WriteRecord] = []
    private(set) var registrations: [String] = []

    private var document: DeviceSettingsDocument?
    private var readError: APIError?
    /// Errors to throw from the next writes, consumed one per attempt.
    private var writeFailures: [APIError] = []

    // MARK: - Test control

    func seed(settings: [String: SettingsValue], version: Int, deviceId: String = "mac-1") {
        document = DeviceSettingsDocument(
            version: version,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            deviceId: deviceId,
            schemaVersion: 1,
            settings: settings
        )
    }

    func failReads(with error: APIError) { readError = error }
    func failNextWrites(with errors: [APIError]) { writeFailures = errors }

    func storedSettings() -> [String: SettingsValue] { document?.settings ?? [:] }
    func storedVersion() -> Int { document?.version ?? 0 }

    // MARK: - DeviceSettingsAPI

    func fetchDeviceSettings(deviceId: String) async throws -> DeviceSettingsDocument? {
        reads.append(deviceId)
        if let readError { throw readError }
        return document
    }

    func writeDeviceSettings(
        deviceId: String,
        settings: [String: SettingsValue],
        baseVersion: Int
    ) async throws -> DeviceSettingsDocument {
        writes.append(WriteRecord(deviceId: deviceId, settings: settings, baseVersion: baseVersion))
        if !writeFailures.isEmpty {
            throw writeFailures.removeFirst()
        }
        let currentVersion = document?.version ?? 0
        guard baseVersion == currentVersion else {
            throw APIError.versionConflict(current: document)
        }
        let updated = DeviceSettingsDocument(
            version: currentVersion + 1,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            deviceId: deviceId,
            schemaVersion: 1,
            settings: settings
        )
        document = updated
        return updated
    }

    func registerDevice(deviceId: String, deviceName: String) async throws {
        registrations.append(deviceId)
    }
}
