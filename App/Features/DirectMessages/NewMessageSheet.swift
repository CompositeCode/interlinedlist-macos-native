// NewMessageSheet
//
// Modal composer for a brand-new conversation (the-gaps.md G1). A
// recipient picker over the eligible-recipient set (`recipients()`, mutual
// followers) plus a body field. A thin shell over `NewMessageViewModel`.
//
// On a successful send the sheet dismisses and reports the recipient's
// username via `onSent` so the root view can select that conversation and
// open its thread.
//
// Per decision 0003, this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct NewMessageSheet: View {

    /// Optional username to preselect (the "Message" button on a profile).
    var preselectUsername: String? = nil
    /// Called with the recipient username after a successful send.
    var onSent: (String) -> Void = { _ in }

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: NewMessageViewModel?

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
    }

    @ViewBuilder
    private func content(viewModel: NewMessageViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isLoadingRecipients {
                ProgressView("Loading recipients…")
            } else if viewModel.recipients.isEmpty, viewModel.hasLoadedRecipients {
                Label(
                    "You have no mutual followers to message yet.",
                    systemImage: "person.2.slash"
                )
                .font(.ilSubtitle())
                .foregroundStyle(.secondary)
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
