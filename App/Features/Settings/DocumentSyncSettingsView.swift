// DocumentSyncSettingsView
//
// Settings pane that controls the bundled document-sync background agent.
// Turning it on registers + starts the agent (SMAppService.agent), which then
// keeps a local folder of Markdown files in sync with your documents so an
// external editor like Obsidian can be used. The agent runs autonomously and
// relaunches at login.
//
// The folder to sync into is chosen in the agent's own menu-bar Preferences
// (the agent is sandboxed and must receive the folder via a user-selected
// security-scoped bookmark), so this pane focuses on enabling the service.

import SwiftUI

struct DocumentSyncSettingsView: View {

    @StateObject private var controller = SyncServiceController()
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { controller.isEnabled },
                    set: { controller.set(enabled: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync my documents to a local folder")
                        Text("Runs a background helper that mirrors your documents as Markdown files and keeps them in sync — ideal for editing in Obsidian.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Service", value: controller.statusDescription)

                if let error = controller.lastErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Document Sync")
            } footer: {
                Text("The helper starts now and every time you log in, running independently of this app. Choose the sync folder from the InterlinedList Sync icon in the menu bar › Preferences.")
                    .font(.caption)
            }

            if controller.status == .requiresApproval {
                Section {
                    Button("Open Login Items Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            openURL(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { controller.refresh() }
    }
}

#Preview {
    DocumentSyncSettingsView()
}
