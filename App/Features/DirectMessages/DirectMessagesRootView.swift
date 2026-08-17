// DirectMessagesRootView
//
// The Direct Messages sidebar section (work-consolidation.md G1). A three-part flow
// inside the detail column:
//   1. a folder switcher (Inbox / Sent / Deleted) — a segmented picker,
//   2. the conversation list for that folder (grouped by other participant),
//   3. the thread for the selected conversation.
//
// The folder + list are driven by `DirectMessagesListViewModel`; the
// selected thread is rendered by `DMThreadView`, re-identified by
// username so switching conversations tears down the old poll and starts
// a fresh one. A "New message" toolbar button presents `NewMessageSheet`.
//
// The current user id — needed for conversation grouping and bubble
// alignment — is read from `CurrentUserStore` (the App-layer session
// projection), threaded down as a closure so the view models always see
// the latest session (mirrors `ProfileRootView`).
//
// Per decision 0003, this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct DirectMessagesRootView: View {

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: DirectMessagesListViewModel?
    @State private var selectedUsername: String?
    @State private var showNewMessage = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    listBody(viewModel: viewModel)
                } else {
                    unconfiguredState
                }
            }
            .navigationTitle("Direct Messages")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewMessage = true
                    } label: {
                        Label("New message", systemImage: "square.and.pencil")
                    }
                    .accessibilityLabel("New message")
                }
            }
        }
        .task {
            if viewModel == nil, let environment {
                let vm = DirectMessagesListViewModel(
                    service: environment.directMessages,
                    eventBus: environment.directMessagesEventBus,
                    currentUserID: { [weak environment] in
                        environment?.currentUserStore.currentUserID
                    }
                )
                viewModel = vm
                await vm.load()
            }
        }
        .sheet(isPresented: $showNewMessage) {
            NewMessageSheet(onSent: { username in
                selectedUsername = username
                Task { await viewModel?.load() }
            })
        }
        // Open a thread when the "Message" button on a profile fires.
        .onReceive(NotificationCenter.default.publisher(for: .directMessagesOpenThread)) { note in
            guard let username = note.object as? String else { return }
            selectedUsername = username
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func listBody(viewModel: DirectMessagesListViewModel) -> some View {
        HSplitView {
            VStack(spacing: 0) {
                folderPicker(viewModel: viewModel)
                Divider()
                conversationList(viewModel: viewModel)
            }
            .frame(minWidth: 260, idealWidth: 300)

            threadPane
                .frame(minWidth: 320)
        }
    }

    @ViewBuilder
    private func folderPicker(viewModel: DirectMessagesListViewModel) -> some View {
        Picker(
            "Folder",
            selection: Binding(
                get: { viewModel.folder },
                set: { viewModel.folder = $0 }
            )
        ) {
            ForEach(DMFolder.allCases) { folder in
                Text(folder.label).tag(folder)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(12)
    }

    @ViewBuilder
    private func conversationList(viewModel: DirectMessagesListViewModel) -> some View {
        if let error = viewModel.error, viewModel.conversations.isEmpty {
            errorState(error: error, viewModel: viewModel)
        } else if viewModel.conversations.isEmpty, viewModel.hasLoadedOnce {
            emptyState(folder: viewModel.folder)
        } else {
            List(selection: $selectedUsername) {
                ForEach(viewModel.conversations) { conversation in
                    conversationRow(conversation, viewModel: viewModel)
                        .tag(conversation.otherUsername)
                }
                if viewModel.hasMore {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .task { await viewModel.loadMore() }
                }
            }
            .listStyle(.inset)
            .refreshable { await viewModel.load() }
            .overlay {
                if viewModel.isLoading, !viewModel.hasLoadedOnce {
                    ProgressView("Loading…")
                }
            }
        }
    }

    @ViewBuilder
    private func conversationRow(
        _ conversation: DMConversation,
        viewModel: DirectMessagesListViewModel
    ) -> some View {
        HStack(spacing: 10) {
            DMAvatarView(user: conversation.otherUser, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.otherUser?.displayName ?? "@\(conversation.otherUsername)")
                    .font(.body.weight(conversation.unreadCount > 0 ? .semibold : .regular))
                    .lineLimit(1)
                Text(conversation.latestMessage.body)
                    .font(.ilSubtitle())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if conversation.unreadCount > 0 {
                Text("\(conversation.unreadCount)")
                    .font(.ilMono(10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .accessibilityLabel("\(conversation.unreadCount) unread")
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if viewModel.folder == .deleted {
                Button {
                    Task { await viewModel.restore(messageID: conversation.latestMessage.id) }
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button(role: .destructive) {
                    Task { await viewModel.trash(messageID: conversation.latestMessage.id) }
                } label: {
                    Label("Move to Deleted", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var threadPane: some View {
        if let username = selectedUsername {
            DMThreadView(
                username: username,
                currentUserID: { [weak environment] in
                    environment?.currentUserStore.currentUserID
                }
            )
            .id(username)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.ilDisplay(36))
                    .foregroundStyle(Color.accentColor)
                Text("Select a conversation")
                    .font(.ilSubtitle())
                Text("Pick a conversation on the left, or start a new message.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - States

    private func emptyState(folder: DMFolder) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.ilDisplay(32))
                .foregroundStyle(.secondary)
            Text("No messages in \(folder.label)")
                .font(.ilSubtitle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(error: Error, viewModel: DirectMessagesListViewModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.ilDisplay(32))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load messages")
                .font(.ilSubtitle())
            Text(error.localizedDescription)
                .font(.ilSubtitle())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Try again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unconfiguredState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.adjustable")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Messages unavailable")
                .font(.ilSubtitle())
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cross-scene routing

extension Foundation.Notification.Name {
    /// Posted with a username `object` when the user taps "Message" on a
    /// profile. `MainWindowView` switches the sidebar to Messages and
    /// `DirectMessagesRootView` selects that conversation's thread.
    static let directMessagesOpenThread = Foundation.Notification.Name("InterlinedList.directMessagesOpenThread")

    /// Posted by the ⌥⌘M menu command / the Messages menu to route the
    /// sidebar to the Messages section.
    static let directMessagesShow = Foundation.Notification.Name("InterlinedList.directMessagesShow")
}
