import XCTest
@testable import InterlinedListSyncCore

@MainActor
final class PreferencesManagerTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "iltest-prefs-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func test_defaults_areSensible() {
        let prefs = PreferencesManager(defaults: freshDefaults())
        XCTAssertEqual(prefs.pollIntervalSeconds, SyncConfiguration.defaultPollInterval)
        XCTAssertTrue(prefs.syncEnabled)
        XCTAssertFalse(prefs.hasSyncFolder)
        XCTAssertNil(prefs.syncFolderPath)
    }

    func test_pollInterval_persistsAndClampsOnReload() {
        let defaults = freshDefaults()
        let prefs = PreferencesManager(defaults: defaults)
        prefs.pollIntervalSeconds = 120
        // Simulate a stored out-of-range value from a previous version.
        defaults.set(5, forKey: "pollIntervalSeconds")
        let reloaded = PreferencesManager(defaults: defaults)
        XCTAssertEqual(reloaded.pollIntervalSeconds, SyncConfiguration.minPollInterval)
    }

    func test_togglesPersist() {
        let defaults = freshDefaults()
        let prefs = PreferencesManager(defaults: defaults)
        prefs.notifyOnCompletion = true
        prefs.launchAtLogin = true
        let reloaded = PreferencesManager(defaults: defaults)
        XCTAssertTrue(reloaded.notifyOnCompletion)
        XCTAssertTrue(reloaded.launchAtLogin)
    }
}
