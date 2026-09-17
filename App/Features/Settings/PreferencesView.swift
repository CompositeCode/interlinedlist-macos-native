// PreferencesView
//
// Settings ▸ Preferences pane — the account's server-synced preferences
// (work-consolidation.md — settings storage). A grouped `Form` of toggles plus a
// posts-per-page stepper, bound to `PreferencesViewModel.settings`; "Save"
// persists via `POST /api/user/update`.
//
// SwiftUI-only (no AppKit). The pane reads `AppEnvironment.userService` and
// builds its view model on first appearance, mirroring the other Settings panes.
//
// G35 / issue #43 completes the "View preferences" card against the web's own
// controls (verified live 2026-09-09): posts-per-page is `10...30` (it shipped
// as `5...100 step 5`, which could save values the web cannot represent), the
// Viewing picker and the notification-tray stepper are new, and the advanced
// post options toggle now actually drives the composer's gear.

import SwiftUI
import InterlinedDomain

struct PreferencesView: View {

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: PreferencesViewModel?

    var body: some View {
        Group {
            if let viewModel {
                form(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if viewModel == nil, let environment {
                let model = PreferencesViewModel(
                    userService: environment.userService,
                    preferencesStore: environment.userPreferences,
                    currentUserStore: environment.currentUserStore
                )
                viewModel = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func form(viewModel: PreferencesViewModel) -> some View {
        Form {
            Section("Posting") {
                Toggle("New posts are public by default", isOn: boolBinding(viewModel, \.defaultPubliclyVisible))
                Toggle("Show advanced post options", isOn: boolBinding(viewModel, \.showAdvancedPostSettings))
                Text("Reveals the composer's options gear — media, scheduling, and cross-posting — without clicking it first.")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }

            Section("Reading") {
                Toggle("Show link previews", isOn: boolBinding(viewModel, \.showPreviews))

                // Range mirrors the web's `min=10 max=30` exactly; step 1
                // because the web's number input has no step attribute. The
                // old `5...100 step 5` could save 5 or 100, values the web
                // control cannot represent (G35 / issue #43).
                Stepper(
                    "Posts per page: \(viewModel.settings.messagesPerPage)",
                    value: Binding(
                        get: { viewModel.settings.messagesPerPage },
                        set: { viewModel.settings.messagesPerPage = $0 }
                    ),
                    in: viewModel.messagesPerPageRange,
                    step: 1
                )
                .accessibilityLabel("Posts per page")

                viewingPreferencePicker(viewModel: viewModel)

                Stepper(
                    "Notifications in tray: \(viewModel.settings.notificationTrayLimit)",
                    value: Binding(
                        get: { viewModel.settings.notificationTrayLimit },
                        set: { viewModel.settings.notificationTrayLimit = $0 }
                    ),
                    in: viewModel.notificationTrayLimitRange,
                    step: 1
                )
                .accessibilityLabel("Notifications in tray")
                Text("How many notifications the bell tray holds before older ones drop off.")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Toggle("Private account", isOn: boolBinding(viewModel, \.isPrivateAccount))
            }

            if let error = viewModel.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.ilMono(11))
                    .foregroundStyle(Color.red)
            }

            Section {
                HStack {
                    Spacer()
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Saving preferences")
                    }
                    Button("Save") {
                        Task { await viewModel.save() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.hasChanges || viewModel.isSaving)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(viewModel.isLoading)
    }

    /// The account's default feed slice. All four documented values are offered
    /// rather than hiding the two the backend cannot serve yet: hiding them
    /// would silently rewrite a preference the user set on the web the moment
    /// they saved anything else here. Selecting an unserved value shows an
    /// honest note instead — the timeline renders its existing "coming soon"
    /// empty state for that scope (P1-G, re-verified 2026-09-09).
    @ViewBuilder
    private func viewingPreferencePicker(viewModel: PreferencesViewModel) -> some View {
        Picker(
            "Viewing",
            selection: Binding(
                get: { viewModel.settings.viewingPreference },
                set: { viewModel.settings.viewingPreference = $0 }
            )
        ) {
            ForEach(viewModel.viewingPreferenceOptions, id: \.self) { preference in
                Text(preference.displayName).tag(preference)
            }
        }
        .accessibilityLabel("Viewing preference")

        if !viewModel.selectedViewingPreferenceIsServed {
            Label(
                "This feed isn't available yet — the timeline will show a \"coming soon\" state for it. Your choice is still saved and honoured on the web.",
                systemImage: "clock.badge.exclamationmark"
            )
            .font(.ilMono(10))
            .foregroundStyle(.secondary)
        }
    }

    /// A two-way binding into one boolean field of the working-copy settings.
    private func boolBinding(
        _ viewModel: PreferencesViewModel,
        _ keyPath: WritableKeyPath<UserSettings, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { viewModel.settings[keyPath: keyPath] },
            set: { viewModel.settings[keyPath: keyPath] = $0 }
        )
    }
}
