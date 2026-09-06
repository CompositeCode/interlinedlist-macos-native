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

import Foundation

enum DeviceIdentity {

    private static let defaultsKey = "com.interlinedlist.deviceId"

    /// The stable id for this machine, minting and persisting one on first use.
    static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let minted = UUID().uuidString
        defaults.set(minted, forKey: defaultsKey)
        return minted
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
