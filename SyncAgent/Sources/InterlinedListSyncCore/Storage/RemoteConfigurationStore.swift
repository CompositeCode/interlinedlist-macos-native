import Foundation
import os

/// What a read of this machine's per-machine settings found.
///
/// The three cases are not interchangeable, and conflating two of them is the
/// bug GitHub issue #104 warns about. "Nothing stored" invites a one-time
/// migration; "could not ask" must never invite anything, because the document
/// on the server may be newer than the local values and re-uploading them would
/// destroy it.
public enum RemoteConfigurationState: Sendable, Equatable {
    /// The server holds a configuration written by this agent.
    case stored(SyncAgentConfiguration)
    /// The server holds no configuration for this machine — a fresh install.
    case absent
    /// The question could not be asked: no device id published yet, no token,
    /// or the request failed.
    case unavailable
}

/// Which configuration wins at launch, and whether the one-way migration should
/// run.
public struct ConfigurationResolution: Sendable, Equatable {
    public let configuration: SyncAgentConfiguration
    public let shouldMigrate: Bool

    public init(configuration: SyncAgentConfiguration, shouldMigrate: Bool) {
        self.configuration = configuration
        self.shouldMigrate = shouldMigrate
    }
}

/// The launch-time decision, extracted as a pure function.
///
/// It is four lines of logic guarding the one thing in this feature that can
/// lose a user's settings for good, so it is worth being able to test without a
/// network, a Keychain, or a clock.
public enum ConfigurationResolver {

    /// - Parameters:
    ///   - remote: what the server said.
    ///   - local: the `UserDefaults` configuration this machine has been using.
    ///   - hasMigrated: whether a migration write has already been *confirmed*.
    public static func resolve(
        remote: RemoteConfigurationState,
        local: SyncAgentConfiguration,
        hasMigrated: Bool
    ) -> ConfigurationResolution {
        switch remote {
        case .stored(let configuration):
            // Once a document exists it is authoritative, full stop. It may have
            // been written minutes ago by this same machine, or by a user who
            // reinstalled and expects their folder back. Merging it with local
            // values would mean choosing a winner field by field with no
            // timestamps to choose by.
            return ConfigurationResolution(configuration: configuration, shouldMigrate: false)

        case .absent where !hasMigrated:
            // The one moment migration is safe: the server has nothing, so
            // nothing can be overwritten.
            return ConfigurationResolution(configuration: local, shouldMigrate: true)

        case .absent:
            // Already migrated once and the document is gone — the machine was
            // deregistered, or the settings were deleted deliberately. Writing
            // the local values back would resurrect a configuration the user
            // removed. The agent keeps running on them locally; the next change
            // the user makes will store them again as a deliberate act.
            return ConfigurationResolution(configuration: local, shouldMigrate: false)

        case .unavailable:
            // Offline, signed out, or not yet addressable. Carry on locally and
            // decide nothing — the server's answer is simply not in evidence.
            return ConfigurationResolution(configuration: local, shouldMigrate: false)
        }
    }
}

/// Reads and writes the agent's configuration in per-machine app settings
/// (`…/devices/{deviceId}/settings`, GitHub issue #104).
///
/// **Per-machine, never shared.** The account-wide document seeds a brand-new
/// machine on first sign-in, so a sync-folder path stored there would arrive
/// pre-filled on a Mac where it means nothing — the exact failure this feature
/// exists to prevent.
///
/// An actor because the agent writes from wherever a preference changed and from
/// the sync loop's completion handler, and the cached `baseVersion` must not be
/// read by one of those while the other is replacing it.
public actor RemoteConfigurationStore {

    private let api: any DeviceSettingsAPI
    private let identity: any DeviceIdentifying
    /// Name to register this machine under if it turns out not to be in the
    /// registry. Hostname-derived, matching what the main app would use.
    private let deviceName: String
    private let logger = Logger(subsystem: SyncConfiguration.logSubsystem, category: "RemoteConfig")

    /// The document as last seen, so a write can overlay rather than replace and
    /// can send a `baseVersion` the server will accept.
    private var cachedPayload: [String: SettingsValue] = [:]
    private var cachedVersion = 0
    private var hasReadDocument = false

    /// Attempts a single `save` will make before giving up.
    ///
    /// Bounded on purpose. A 409 is re-based and retried rather than surfaced —
    /// the agent runs in the background, where there is no one to show a failure
    /// toast to — but an unbounded retry against a document another process is
    /// rewriting in a loop would turn a lost race into a request storm.
    private static let maxSaveAttempts = 3

    public init(
        api: any DeviceSettingsAPI,
        identity: any DeviceIdentifying,
        deviceName: String
    ) {
        self.api = api
        self.identity = identity
        self.deviceName = deviceName
    }

    /// This machine's device id, or nil when the main app has not published one
    /// into the shared Keychain group yet — in which case there is no
    /// per-machine document to address and the agent stays on local settings.
    public var currentDeviceID: String? { identity.currentDeviceID() }

    // MARK: - Reading

    public func load() async -> RemoteConfigurationState {
        guard let deviceID = identity.currentDeviceID() else {
            // The main app mints and publishes the id; the agent only consumes
            // it (see `SharedDeviceIdentity`). Until it appears there is no
            // document to address, which is "cannot ask", not "nothing stored".
            logger.info("No device id published yet; per-machine settings unavailable")
            return .unavailable
        }
        do {
            guard let document = try await api.fetchDeviceSettings(deviceId: deviceID) else {
                cachedPayload = [:]
                cachedVersion = 0
                hasReadDocument = true
                return .absent
            }
            cache(document)
            guard let configuration = SyncAgentConfiguration(
                settings: document.settings,
                thisMachineID: deviceID
            ) else {
                // A document exists but holds none of this agent's keys — the
                // main app stored per-machine settings of its own. Absent for
                // our purposes, and the cached payload means the migration write
                // will preserve those keys.
                return .absent
            }
            return .stored(configuration)
        } catch {
            logger.error("Per-machine settings read failed: \(error.localizedDescription, privacy: .public)")
            return .unavailable
        }
    }

    // MARK: - Writing

    /// Stores `configuration`, re-basing and retrying if the compare-and-set
    /// write loses.
    ///
    /// Throws only when the write genuinely cannot be completed; the caller
    /// treats that as "stay on local settings" rather than as an error to show.
    public func save(_ configuration: SyncAgentConfiguration) async throws {
        guard let deviceID = identity.currentDeviceID() else { throw APIError.noDeviceIdentity }

        // Read before the first write so the overlay has the real document to
        // preserve. Skipping this and writing with `baseVersion: 0` would 409
        // anyway — but only after the payload had already been built from
        // nothing, which is how the main app's keys would get dropped.
        if !hasReadDocument {
            _ = await load()
        }

        var didRegister = false
        var attempt = 0
        while true {
            attempt += 1
            do {
                let document = try await api.writeDeviceSettings(
                    deviceId: deviceID,
                    settings: configuration.apply(to: cachedPayload),
                    baseVersion: cachedVersion
                )
                cache(document)
                return
            } catch APIError.versionConflict(let current) {
                guard attempt < Self.maxSaveAttempts else { throw APIError.versionConflict(current: current) }
                if let current {
                    // The 409 body carries the winning document, so re-basing
                    // costs nothing. This is why the agent's client keeps typed
                    // error payloads where the main app's does not.
                    cache(current)
                } else if let refreshed = try? await api.fetchDeviceSettings(deviceId: deviceID) {
                    cache(refreshed)
                } else {
                    throw APIError.versionConflict(current: nil)
                }
            } catch APIError.deviceNotRegistered {
                // Registering is safe *here specifically*: the 404 proves the id
                // is absent from the registry, so the upsert has no existing
                // `deviceName` to clobber. Once only — a second 404 after a
                // successful register is a server-side problem retrying cannot
                // solve.
                guard !didRegister else { throw APIError.deviceNotRegistered }
                didRegister = true
                try await api.registerDevice(deviceId: deviceID, deviceName: deviceName)
            }
        }
    }

    private func cache(_ document: DeviceSettingsDocument) {
        cachedPayload = document.settings
        cachedVersion = document.version
        hasReadDocument = true
    }
}
