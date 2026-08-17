// PreferencesView
//
// Settings ▸ Preferences pane — the account's server-synced preferences
// (work-consolidation.md — settings storage). A grouped `Form` of toggles plus a
// posts-per-page stepper, bound to `PreferencesViewModel.settings`; "Save"
// persists via `POST /api/user/update`.
//
// SwiftUI-only (no AppKit). The pane reads `AppEnvironment.userService` and
// builds its view model on first appearance, mirroring the other Settings panes.

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
                let model = PreferencesViewModel(userService: environment.userService)
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
            }

            Section("Reading") {
                Toggle("Show link previews", isOn: boolBinding(viewModel, \.showPreviews))
                Stepper(
                    "Posts per page: \(viewModel.settings.messagesPerPage)",
                    value: Binding(
                        get: { viewModel.settings.messagesPerPage },
                        set: { viewModel.settings.messagesPerPage = $0 }
                    ),
                    in: 5...100,
                    step: 5
                )
                .accessibilityLabel("Posts per page")
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
