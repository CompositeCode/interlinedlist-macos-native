// RepostSheetView
//
// Small sheet opened from a message row's "Repost" context-menu item
// (PLAN.md §6 M2). Collects optional commentary + visibility, then
// calls into `RepostSheetViewModel.submit()`. UI is intentionally
// minimal — a multi-line commentary field and a visibility segment.

import SwiftUI
import InterlinedDomain

struct RepostSheetView: View {

    /// The original message being reposted. Rendered as a compact
    /// header so the user sees what they're sharing.
    let original: Message

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: RepostSheetViewModel?

    var body: some View {
        Group {
            if let viewModel {
                sheetBody(viewModel: viewModel)
            } else {
                unconfiguredState
            }
        }
        .frame(minWidth: 420, minHeight: 280)
        .task {
            if viewModel == nil, let environment {
                viewModel = RepostSheetViewModel(
                    messages: environment.messages,
                    eventBus: environment.composerEventBus,
                    originalMessageID: original.id
                )
            }
        }
        .onChange(of: viewModel?.didFinish) { _, finished in
            if finished == true { dismiss() }
        }
    }

    @ViewBuilder
    private func sheetBody(viewModel: RepostSheetViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repost")
                .font(.headline)

            originalPreview

            VStack(alignment: .leading, spacing: 4) {
                Text("Commentary (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { viewModel.commentary },
                    set: { viewModel.commentary = $0 }
                ))
                .font(.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .accessibilityLabel("Repost commentary")
            }

            Picker("Visibility", selection: Binding(
                get: { viewModel.visibility },
                set: { viewModel.visibility = $0 }
            )) {
                Text("Public").tag(Visibility.public)
                Text("Private").tag(Visibility.private)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .accessibilityLabel("Repost visibility")

            if let error = viewModel.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }

            footer(viewModel: viewModel)
        }
        .padding(16)
    }

    private var originalPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("@\(original.author.username)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(original.text)
                .font(.subheadline)
                .lineLimit(3)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func footer(viewModel: RepostSheetViewModel) -> some View {
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

            Button("Repost") {
                Task { await viewModel.submit() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.isSubmitting)
        }
    }

    private var unconfiguredState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.adjustable")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Repost unavailable")
                .font(.headline)
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
