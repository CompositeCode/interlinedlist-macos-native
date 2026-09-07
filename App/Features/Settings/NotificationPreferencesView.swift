// NotificationPreferencesView
//
// Settings ▸ Notifications (work-consolidation.md G18). The pane is entirely
// data-driven: every row, its label, its description and which channel switches
// appear all come from the server's catalogue, so a new event type shows up
// without a client release.
//
// SwiftUI-only (no AppKit). Consumes only `InterlinedDomain` per Decision 0003.

import SwiftUI
import InterlinedDomain

struct NotificationPreferencesView: View {

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: NotificationPreferencesViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if viewModel == nil {
                let model = NotificationPreferencesViewModel(
                    service: environment?.notificationPreferences
                )
                viewModel = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: NotificationPreferencesViewModel) -> some View {
        if viewModel.isUnavailable {
            SettingsUnavailableView(
                title: "Notification preferences unavailable",
                message: "This build has no notification-preferences service configured."
            )
        } else {
            Form {
                if let error = viewModel.error {
                    Section { SettingsErrorRow(error: error) }
                }
                if viewModel.isLoading && viewModel.events.isEmpty {
                    Section { ProgressView() }
                } else if viewModel.events.isEmpty {
                    Section {
                        Text("No notification events available.").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(viewModel.events) { event in
                        Section {
                            // Only render channels the server actually offered
                            // for this event — a dead switch is worse than none.
                            ForEach(NotificationChannel.allCases) { channel in
                                if let value = viewModel.channelValue(event.key, channel) {
                                    Toggle(
                                        channel.title,
                                        isOn: Binding(
                                            get: { value },
                                            set: { viewModel.setChannel(event.key, channel, to: $0) }
                                        )
                                    )
                                }
                            }
                        } header: {
                            Text(event.label)
                        } footer: {
                            if let description = event.description {
                                Text(description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    if viewModel.isSaving { ProgressView().controlSize(.small) }
                    Button("Save") { Task { await viewModel.save() } }
                        .disabled(!viewModel.hasChanges || viewModel.isSaving)
                        .keyboardShortcut("s")
                }
                .padding(.horizontal).padding(.bottom, 8)
            }
        }
    }
}
