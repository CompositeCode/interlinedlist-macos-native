// NewMessageSheet
//
// Modal composer for a brand-new conversation (work-consolidation.md G1,
// G22). A recipient picker over the eligible-recipient set
// (`recipients()`, mutual followers), a body field, and photo attachments.
// A thin shell over `NewMessageViewModel`.
//
// The recipient list is mutual-followers-only, so its empty state explains
// the rule rather than just reporting emptiness — the wording matches
// `/help/direct-messages`.
//
// On a successful send the sheet dismisses and reports the recipient's
// username via `onSent` so the root view can select that conversation and
// open its thread.
//
// Per decision 0003, this view consumes only `InterlinedDomain`.

import SwiftUI
import UniformTypeIdentifiers
import InterlinedDomain

struct NewMessageSheet: View {

    /// Optional username to preselect (the "Message" button on a profile).
    var preselectUsername: String? = nil
    /// Called with the recipient username after a successful send.
    var onSent: (String) -> Void = { _ in }

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: NewMessageViewModel?

    /// Controls the `.fileImporter` sheet for picking photos (G22).
    @State private var isPhotoImporterPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New message")
                .font(.ilTitle())

            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            if viewModel == nil, let environment {
                let vm = NewMessageViewModel(
                    service: environment.directMessages,
                    eventBus: environment.directMessagesEventBus
                )
                viewModel = vm
                await vm.loadRecipients(preselectUsername: preselectUsername)
            }
        }
        // SwiftUI-only file picking (Decision 0005 — no NSOpenPanel).
        // Images only: DMs have no video route.
        .fileImporter(
            isPresented: $isPhotoImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                viewModel?.addAttachments(urls: urls)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            viewModel?.addAttachments(urls: urls)
            return true
        }
    }

    @ViewBuilder
    private func content(viewModel: NewMessageViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isLoadingRecipients {
                ProgressView("Loading recipients…")
            } else if viewModel.recipients.isEmpty, viewModel.hasLoadedRecipients {
                // Wording from `/help/direct-messages`: an empty list is not a
                // failure, it means the mutual-follow condition is unmet — say
                // so, otherwise the sheet reads as broken.
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No one to message yet.")
                        Text("If the list is empty, it means no one who follows you also follows you back yet.")
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.2.slash")
                }
                .font(.ilSubtitle())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            } else {
                Picker(
                    "To",
                    selection: Binding(
                        get: { viewModel.selectedRecipientId },
                        set: { viewModel.selectedRecipientId = $0 }
                    )
                ) {
                    Text("Select a recipient").tag(String?.none)
                    ForEach(viewModel.recipients) { user in
                        Text("\(user.displayName) (@\(user.username))")
                            .tag(String?.some(user.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Recipient")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Message")
                    .font(.ilSubtitle())
                    .foregroundStyle(.secondary)
                TextEditor(
                    text: Binding(
                        get: { viewModel.body },
                        set: { viewModel.body = $0 }
                    )
                )
                .frame(minHeight: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .accessibilityLabel("Message body")
                HStack {
                    Text("Markdown supported")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    // The DM ceiling is 10,000 — not the post composer's
                    // 5,000. Shown only as it gets close, to stay quiet.
                    Text("\(viewModel.body.count) / \(viewModel.bodyCharacterLimit)")
                        .font(.ilMono(10))
                        .foregroundStyle(viewModel.isOverBodyLimit ? .red : .secondary)
                        .accessibilityLabel(
                            "\(viewModel.body.count) of \(viewModel.bodyCharacterLimit) characters"
                        )
                }
            }

            // G22: photo attachments, up to 8. Sending photos needs a
            // verified email address; the server refuses with an explanation
            // when it isn't, and that message is what the error line shows.
            // TODO(#41): once issue #41's `CapabilityGate` merges, disable
            // this and explain up front rather than after the attempt.
            VStack(alignment: .leading, spacing: 6) {
                if !viewModel.attachments.isEmpty {
                    DMAttachmentStrip(
                        attachments: viewModel.attachments,
                        limit: viewModel.maxAttachments,
                        onRemove: { viewModel.removeAttachment(id: $0) }
                    )
                }
                Button {
                    isPhotoImporterPresented = true
                } label: {
                    Label("Add photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.attachmentsAreFull)
                .help(
                    viewModel.attachmentsAreFull
                        ? "Up to \(viewModel.maxAttachments) photos per message"
                        : "Attach photos"
                )
            }

            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.ilSubtitle())
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task {
                        await viewModel.send()
                        if let sent = viewModel.sentMessage,
                           let username = viewModel.selectedRecipientUsername {
                            _ = sent
                            onSent(username)
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Send")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSend || viewModel.isSending)
            }
        }
    }
}
