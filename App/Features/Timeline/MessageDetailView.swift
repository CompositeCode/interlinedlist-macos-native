// MessageDetailView
//
// Detail screen for a single message. Renders the message at the top
// followed by a flat list of replies (the indented thread tree lands
// in M2 alongside reply composition — PLAN.md §1, §6).
//
// Like the timeline, the view is a thin shell over
// `MessageDetailViewModel`. Service access goes through the injected
// `AppEnvironment`, so previews and tests substitute services without
// touching networking.

import SwiftUI
import InterlinedDomain

struct MessageDetailView: View {

    let messageID: Message.ID

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: MessageDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                detailBody(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Message")
        .task {
            if viewModel == nil, let environment {
                let model = MessageDetailViewModel(messages: environment.messages, messageID: messageID)
                viewModel = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func detailBody(viewModel: MessageDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let message = viewModel.message {
                    MessageRowView(message: message)
                        .padding(.horizontal, 16)
                    Divider()
                }

                repliesSection(viewModel: viewModel)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .overlay {
            if viewModel.isLoading, viewModel.message == nil {
                ProgressView()
            } else if let error = viewModel.error, viewModel.message == nil {
                errorState(error: error, viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private func repliesSection(viewModel: MessageDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Replies")
                .font(.headline)
                .padding(.horizontal, 16)

            if viewModel.replies.isEmpty, !viewModel.isLoading {
                Text("No replies yet.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ForEach(viewModel.replies) { reply in
                    MessageRowView(message: reply)
                        .padding(.horizontal, 16)
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func errorState(error: Error, viewModel: MessageDetailViewModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load the message")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
