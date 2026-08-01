import SwiftUI

/// Actions the preferences window forwards to the app/engine.
@MainActor
public struct PreferencesActions {
    public var chooseFolder: () -> Void
    public var pollIntervalChanged: (TimeInterval) -> Void
    public var launchAtLoginChanged: (Bool) -> Void
    public var syncEnabledChanged: (Bool) -> Void
    public var syncNow: () -> Void
    public var openInterlinedList: () -> Void

    public init(
        chooseFolder: @escaping () -> Void,
        pollIntervalChanged: @escaping (TimeInterval) -> Void,
        launchAtLoginChanged: @escaping (Bool) -> Void,
        syncEnabledChanged: @escaping (Bool) -> Void,
        syncNow: @escaping () -> Void,
        openInterlinedList: @escaping () -> Void
    ) {
        self.chooseFolder = chooseFolder
        self.pollIntervalChanged = pollIntervalChanged
        self.launchAtLoginChanged = launchAtLoginChanged
        self.syncEnabledChanged = syncEnabledChanged
        self.syncNow = syncNow
        self.openInterlinedList = openInterlinedList
    }
}

public struct PreferencesView: View {
    @ObservedObject private var prefs: PreferencesManager
    @ObservedObject private var state: SyncStateModel
    private let actions: PreferencesActions

    public init(prefs: PreferencesManager, state: SyncStateModel, actions: PreferencesActions) {
        self.prefs = prefs
        self.state = state
        self.actions = actions
    }

    public var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Sync status", value: state.statusTitle)
                LabeledContent("Last synced", value: state.lastSyncedTitle.replacingOccurrences(of: "Last synced: ", with: ""))
                if let error = state.lastError {
                    LabeledContent("Last error", value: error)
                        .foregroundStyle(.red)
                }
                if state.status == .signedOut || state.status == .authExpired {
                    Button("Open InterlinedList to Sign In…", action: actions.openInterlinedList)
                }
                Button("Sync Now", action: actions.syncNow)
            }

            Section("Sync Folder") {
                LabeledContent("Folder", value: prefs.syncFolderPath ?? "Not chosen")
                Button(prefs.hasSyncFolder ? "Change Folder…" : "Choose Folder…", action: actions.chooseFolder)
            }

            Section("Behavior") {
                Toggle("Keep documents synced", isOn: Binding(
                    get: { prefs.syncEnabled },
                    set: { prefs.syncEnabled = $0; actions.syncEnabledChanged($0) }
                ))
                Toggle("Start at login and run in the background", isOn: Binding(
                    get: { prefs.launchAtLogin },
                    set: { prefs.launchAtLogin = $0; actions.launchAtLoginChanged($0) }
                ))
                VStack(alignment: .leading) {
                    Text("Check for changes every \(Int(prefs.pollIntervalSeconds))s")
                    Slider(
                        value: Binding(
                            get: { prefs.pollIntervalSeconds },
                            set: { prefs.pollIntervalSeconds = $0; actions.pollIntervalChanged($0) }
                        ),
                        in: SyncConfiguration.minPollInterval...SyncConfiguration.maxPollInterval,
                        step: 30
                    )
                }
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $prefs.notificationsEnabled)
                Toggle("Notify on completed syncs", isOn: $prefs.notifyOnCompletion)
                    .disabled(!prefs.notificationsEnabled)
                Toggle("Notify on conflicts", isOn: $prefs.notifyOnConflicts)
                    .disabled(!prefs.notificationsEnabled)
                Toggle("Notify on errors", isOn: $prefs.notifyOnErrors)
                    .disabled(!prefs.notificationsEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }
}
