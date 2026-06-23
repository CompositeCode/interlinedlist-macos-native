// ComposerWindowView
//
// The dedicated composer window opened via ⌘N or the File → New Post
// menu command (PLAN.md §5 — "Composer: separate `Window` scene, ⌘N
// anywhere, ⌘↩ to publish"). UI is intentionally simple for M2: a
// plain-text body editor, a tag-token input, a visibility segment,
// and a publish button. Media attachments / scheduling / cross-post
// pickers land in M6 (PLAN.md §6 M6) and are deliberately absent here.
//
// All business logic lives in `ComposerViewModel`; this view binds
// observable state to controls and dismisses itself when
// `didFinish` flips true.

import SwiftUI
import InterlinedDomain

struct ComposerWindowView: View {

    /// The mode the window opens in. `.newPost` for a fresh draft,
    /// `.edit(...)` when reopened to edit an existing message.
    let mode: ComposerMode

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ComposerViewModel?

    var body: some View {
        Group {
            if let viewModel {
                composerBody(viewModel: viewModel)
            } else {
                unconfiguredState
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .task {
            if viewModel == nil, let environment {
                viewModel = ComposerViewModel(
                    messages: environment.messages,
                    eventBus: environment.composerEventBus,
                    mode: mode
                )
            }
        }
        .onChange(of: viewModel?.didFinish) { _, finished in
            if finished == true { dismiss() }
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func composerBody(viewModel: ComposerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Body editor — Markdown is just a body string in M2 (no
            // toolbar, no preview). `TextEditor` gives us a native
            // multi-line plain-text field with macOS-standard
            // affordances (find/replace, system spellcheck).
            bodyEditor(viewModel: viewModel)
                .frame(minHeight: 180)

            // Tag input. Comma- or space-separated tokens — the view
            // model normalises on submit.
            tagsField(viewModel: viewModel)

            visibilityPicker(viewModel: viewModel)

            if let error = viewModel.error {
                errorBanner(error: error)
            }

            footer(viewModel: viewModel)
        }
        .padding(16)
        .navigationTitle(mode.windowTitle)
    }

    @ViewBuilder
    private func bodyEditor(viewModel: ComposerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Body")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { viewModel.body },
                set: { viewModel.body = $0 }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .accessibilityLabel("Message body")
        }
    }

    @ViewBuilder
    private func tagsField(viewModel: ComposerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tags")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Comma- or space-separated", text: Binding(
                get: { viewModel.tagsInput },
                set: { viewModel.tagsInput = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Tags")
        }
    }

    @ViewBuilder
    private func visibilityPicker(viewModel: ComposerViewModel) -> some View {
        Picker("Visibility", selection: Binding(
            get: { viewModel.visibility },
            set: { viewModel.setVisibility($0) }
        )) {
            Text("Public").tag(Visibility.public)
            Text("Private").tag(Visibility.private)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
        .accessibilityLabel("Post visibility")
    }

    @ViewBuilder
    private func errorBanner(error: Error) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.accentColor)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func footer(viewModel: ComposerViewModel) -> some View {
        HStack {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if viewModel.isSubmitting {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }

            Button(mode.publishButtonLabel) {
                Task { await viewModel.submit() }
            }
            .buttonStyle(.borderedProminent)
            // PLAN.md §5: "⌘↩ to publish".
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!viewModel.isPublishable || viewModel.isSubmitting)
        }
    }

    private var unconfiguredState: some View {
        // Reached only if the scene wasn't wired through `AppEnvironment`,
        // which is a programmer error rather than a runtime one — keep
        // the message diagnostic rather than user-facing.
        VStack(spacing: 8) {
            Image(systemName: "wrench.adjustable")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Composer unavailable")
                .font(.headline)
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
