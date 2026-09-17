// DeviceIdentity
//
// This machine's stable identifier for the app-settings device registry
// (work-consolidation.md G17).
//
// Deliberately still `UserDefaults`-backed even though G17 exists to replace
// local settings state: the device id is what *addresses* a row in the remote
// registry, so it cannot itself live there without a chicken-and-egg problem.
// It is an opaque UUID minted once per machine — no hardware identifier, so it
// carries nothing personally identifying and resets cleanly if the user wipes
// preferences.
//
// GitHub issue #104 adds a second home for the same value: the shared Keychain
// group, so the bundled document-sync agent — a separate process with its own
// defaults domain — can address the *same* per-machine settings document this
// app does. `UserDefaults` remains the primary source of truth so machines
// already registered under an id keep it.

import Foundation
import InterlinedKit

enum DeviceIdentity {

    private static let defaultsKey = "com.interlinedlist.deviceId"

    /// The shared-Keychain channel the sync agent reads. Service and group must
    /// match the agent's `SyncConfiguration.deviceIDService` /
    /// `sharedAccessGroup` — two independent codebases agreeing on one contract.
    static let sharedStore: any DeviceIDStoring = KeychainDeviceIDStore(
        service: "com.interlinedlist.macos.device-id",
        accessGroup: "BJA9558E4B.com.interlinedlist.shared"
    )

    /// The stable id for this machine, minting and persisting one on first use,
    /// and publishing it where the sync agent can find it.
    ///
    /// Resolution order matters:
    ///
    /// 1. **`UserDefaults`** — a machine already registered with the server
    ///    keeps the id its registry row is keyed on. Preferring anything else
    ///    would orphan that row and its per-machine settings.
    /// 2. **the shared Keychain** — the app's preferences were wiped or
    ///    reinstalled while the agent stayed put. Adopting the published id
    ///    reunites the app with the machine's existing registry row instead of
    ///    minting a duplicate.
    /// 3. **mint** — genuinely new machine.
    @discardableResult
    static func current(
        defaults: UserDefaults = .standard,
        sharedStore: any DeviceIDStoring = DeviceIdentity.sharedStore
    ) -> String {
        let resolved: String
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            resolved = existing
        } else if let published = sharedStore.read(), !published.isEmpty {
            resolved = published
            defaults.set(published, forKey: defaultsKey)
        } else {
            resolved = UUID().uuidString
            defaults.set(resolved, forKey: defaultsKey)
        }

        // Publish only on a mismatch. The Keychain write is cheap but not free,
        // and `current()` is called on every Applications-pane load.
        if sharedStore.read() != resolved {
            sharedStore.write(resolved)
        }
        return resolved
    }

    /// A human-friendly default name for this machine, used when registering.
    /// `ProcessInfo.hostName` avoids AppKit entirely (Decision: SwiftUI-only App
    /// target) and matches what the user sees in Sharing preferences.
    static var suggestedName: String {
        let host = ProcessInfo.processInfo.hostName
        // `hostName` often comes back as "studio-mac.local"; trim the suffix.
        return host.hasSuffix(".local") ? String(host.dropLast(6)) : host
    }
}
