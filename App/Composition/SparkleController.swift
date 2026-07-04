// SparkleController
//
// Composition-root owner of the Sparkle automatic-update controller.
// Held for the app's lifetime by InterlinedListApp as a @StateObject so
// Sparkle's automatic launch-time check fires before any window renders.
//
// SHIPPING CHECKLIST — complete every item before the first public release:
//
//  1. Replace SUFeedURL in App/Resources/Info.plist with your real appcast URL.
//     Example: https://downloads.interlinedlist.com/appcast.xml
//
//  2. Generate an Ed25519 key pair with Sparkle's included tool:
//       .build/artifacts/.../generate_keys   (or download from Sparkle releases)
//     The tool prints both keys. Paste ONLY the PUBLIC key into
//     SUPublicEDKeyString in Info.plist. Store the PRIVATE key in a secrets
//     manager — it is needed to sign every update package with sign_update.
//
//  3. For each release, sign the .zip / .dmg with:
//       ./sign_update YourApp.zip --ed-key-file private_key
//     and include the printed sparkle:edSignature attribute in the appcast.
//
//  See full documentation: https://sparkle-project.org/documentation/

import Sparkle

/// Composition-root owner of the `SPUStandardUpdaterController`.
///
/// Responsible only for starting Sparkle at launch and vending the
/// `checkForUpdates()` action to menu commands. All update UI (progress
/// sheets, release notes window, permission prompts) is managed by Sparkle
/// itself via its standard user driver.
///
/// Sandboxing note: Sparkle 2 supports App Sandbox via its bundled XPC
/// services. The `com.apple.security.network.client` entitlement — already
/// present in InterlinedList.entitlements — satisfies the download requirement.
final class SparkleController: ObservableObject {

    // MARK: - Private state

    /// The Sparkle standard controller. Private — callers reach capabilities
    /// only through `checkForUpdates()`.
    private let updaterController: SPUStandardUpdaterController

    // MARK: - Init

    /// Starts the Sparkle updater immediately.
    ///
    /// `startingUpdater: true` triggers the automatic launch-time update check
    /// (subject to the user-configured check interval). Must be called on the
    /// main thread; SwiftUI's `@StateObject` initialization guarantees this.
    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    // MARK: - API

    /// Initiates a user-triggered explicit update check.
    ///
    /// Sparkle surfaces its own progress sheet and result UI; no additional
    /// handling is needed at the call site. Call only from the main thread.
    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}
