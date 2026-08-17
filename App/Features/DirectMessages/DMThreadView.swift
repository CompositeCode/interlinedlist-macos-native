// DMThreadView
//
// The thread column of `DirectMessagesRootView` (work-consolidation.md G1): a
// resolved 1:1 conversation. Renders the message bubbles (aligned by
// `isOutgoing`), a live-polling load driven by `.task`/`.onDisappear`,
// and a composer bar. A thin shell over `DMThreadViewModel` — all load /
// send / poll logic lives in the view model so unit tests cover it
// without SwiftUI.
//
// The view constructs its own `DMThreadViewModel` in `.task` from the
// environment (SwiftUI doesn't expose `@Environment` at init), keyed on
// `username`. When `username` changes (the user picks a different
// conversation) the view is re-identified by the caller via `.id(...)`,
// so a fresh view model + poll are created and the old poll is torn down.
//
// Per decision 0003, this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct DMThreadView: View {

    let username: String
    /// Current user id provider, threaded from the root so bubbles align.
    let currentUserID: @MainActor () -> String?

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: DMThreadViewModel?

    var body: some View {
        Group {
            if let viewModel {
                threadBody(viewModel: viewModel)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if viewModel == nil, let environment {
                let vm = DMThreadViewModel(
                    username: username,
                    service: environment.directMessages,
                    eventBus: environment.directMessagesEventBus,
                    currentUserID: currentUserID
                )
                viewModel = vm
                await vm.startPolling()
            }
        }
        .onDisappear {
            viewModel?.stopPolling()
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func threadBody(viewModel: DMThreadViewModel) -> some View {
        VStack(spacing: 0) {
            header(viewModel: viewModel)
            Divider()
            transcript(viewModel: viewModel)
            Divider()
            composer(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func header(viewModel: DMThreadViewModel) -> some View {
        HStack(spacing: 10) {
            DMAvatarView(user: viewModel.otherUser, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.otherUser?.displayName ?? "@\(username)")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("@\(viewModel.otherUser?.username ?? username)")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if viewModel.isBlocked {
                Label("Blocked", systemImage: "hand.raised")
                    .font(.ilSubtitle())
                    .foregroundStyle(.red)
            } else if !viewModel.isMutual, viewModel.hasLoadedOnce {
                Label("Not mutual", systemImage: "person.crop.circle.badge.xmark")
                    .font(.ilSubtitle())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func transcript(viewModel: DMThreadViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        bubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .overlay {
            if viewModel.isLoading, !viewModel.hasLoadedOnce {
                ProgressView("Loading conversation…")
            } else if viewModel.messages.isEmpty, viewModel.hasLoadedOnce {
                emptyState
            }
        }
    }

    @ViewBuilder
    private func bubble(message: DirectMessage) -> some View {
        let me = currentUserID()
        let outgoing = me.map { message.isOutgoing(currentUserId: $0) } ?? false
        HStack {
            if outgoing { Spacer(minLength: 40) }
            VStack(alignment: outgoing ? .trailing : .leading, spacing: 4) {
                if !message.body.isEmpty {
                    Text(message.body)
                        .font(.ilBody())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(outgoing ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.15))
                        )
                        .foregroundStyle(outgoing ? Color.white : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(Self.timeFormatter.localizedString(for: message.createdAt, relativeTo: .now))
                    .font(.ilMono(9))
                    .foregroundStyle(.secondary)
            }
            if !outgoing { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(outgoing ? "You said" : "They said"): \(message.body)")
    }

    @ViewBuilder
    private func composer(viewModel: DMThreadViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.ilSubtitle())
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                TextField(
                    composerPlaceholder(viewModel: viewModel),
                    text: Binding(
                        get: { viewModel.draft },
                        set: { viewModel.draft = $0 }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(!viewModel.isMutual || viewModel.isBlocked)
                .onSubmit {
                    Task { await viewModel.send() }
                }
                .accessibilityLabel("Message text")

                Button {
                    Task { await viewModel.send() }
                } label: {
                    if viewModel.isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSend || viewModel.isSending)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func composerPlaceholder(viewModel: DMThreadViewModel) -> String {
        if viewModel.isBlocked { return "You can't message this account" }
        if !viewModel.isMutual, viewModel.hasLoadedOnce {
            return "You can only message mutual followers"
        }
        return "Message @\(viewModel.otherUser?.username ?? username)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.ilDisplay(32))
                .foregroundStyle(.secondary)
            Text("No messages yet")
                .font(.ilSubtitle())
            Text("Say hello.")
                .foregroundStyle(.secondary)
        }
    }

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
