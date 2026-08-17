// BlockedAndMutedView
//
// Settings "Blocked & Muted" pane (work-consolidation.md G2). Lists the accounts the
// current user has blocked and muted, each with an inline unblock / unmute
// action. A thin shell over `BlockedAndMutedViewModel`: it observes state,
// dispatches user intents, and leaves all loading / mutation logic in the
// view model so unit tests cover the behavior without touching SwiftUI.
//
// Per decision 0003, this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct BlockedAndMutedView: View {

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: BlockedAndMutedViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                unconfiguredState
            }
        }
        .task {
            if viewModel == nil, let environment {
                let vm = BlockedAndMutedViewModel(service: environment.moderation)
                viewModel = vm
                await vm.load()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(viewModel: BlockedAndMutedViewModel) -> some View {
        Form {
            if let error = viewModel.error {
                Section {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button("Try again") {
                        Task { await viewModel.load() }
                    }
                }
            }

            Section("Blocked") {
                if viewModel.blocked.isEmpty {
                    emptyRow(text: "You haven't blocked anyone.")
                } else {
                    ForEach(viewModel.blocked) { user in
                        moderatedRow(user: user, actionTitle: "Unblock") {
                            if let username = user.username {
                                Task { await viewModel.unblock(username: username) }
                            }
                        }
                    }
                }
            }

            Section("Muted") {
                if viewModel.muted.isEmpty {
                    emptyRow(text: "You haven't muted anyone.")
                } else {
                    ForEach(viewModel.muted) { user in
                        moderatedRow(user: user, actionTitle: "Unmute") {
                            if let username = user.username {
                                Task { await viewModel.unmute(username: username) }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .overlay {
            if viewModel.isLoading, !viewModel.hasLoadedOnce {
                ProgressView("Loading…")
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func moderatedRow(
        user: ModeratedUser,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            avatar(user: user)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(user.handle)
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                // Only actionable when we know the username to send.
                .disabled(user.username == nil)
                .accessibilityLabel("\(actionTitle) \(user.handle)")
        }
        .padding(.vertical, 2)
    }

    private func avatar(user: ModeratedUser) -> some View {
        AsyncImage(url: user.avatarURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private func emptyRow(text: String) -> some View {
        Text(text)
            .font(.ilSubtitle())
            .foregroundStyle(.secondary)
    }

    private var unconfiguredState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.adjustable")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Moderation unavailable")
                .font(.ilSubtitle())
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
