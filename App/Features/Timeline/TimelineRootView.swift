// TimelineRootView
//
// Timeline feed (PLAN.md §1 / §6 M1). Owns the scope picker and tag
// filter affordances and renders the message list inside a
// `NavigationStack` so a tap pushes `MessageDetailView` onto the
// detail column's own stack.
//
// The view is a thin shell over `TimelineViewModel`: it observes
// state, dispatches user intents, and leaves all loading / paging /
// optimistic-dig / delete logic in the view model so unit tests cover
// the behavior without touching SwiftUI.
//
// M2 wiring:
// - The row's dig button calls `TimelineViewModel.toggleDig`.
// - The row's context menu opens a repost sheet, opens the composer
//   in edit mode, or confirms + deletes.
// - The view subscribes to the shared `ComposerEventBus` so a new
//   post / repost / update / delete from the composer window flows
//   into the rendered list in place.

import SwiftUI
import InterlinedDomain

struct TimelineRootView: View {

    @Environment(\.appEnvironment) private var environment

    // Opens the dedicated composer `Window` scene (same target as ⌘N /
    // File → New Message). Gives the timeline a visible, on-screen compose
    // affordance rather than relying on the keyboard shortcut / menu alone.
    @Environment(\.openWindow) private var openWindow

    @State private var viewModel: TimelineViewModel?
    @State private var selection: Message.ID?
    @State private var tagDraft: String = ""

    // M2 row affordances — sheet / dialog state.
    @State private var repostTarget: Message?
    @State private var editTarget: Message?
    @State private var deleteTarget: Message?

    // Web-parity (work-consolidation.md G2) — moderation. The report sheet is
    // driven by a `ModerationActionViewModel` built for the tapped
    // message's author; block / mute fire directly against the
    // moderation service.
    @State private var reportActionVM: ModerationActionViewModel?
    @State private var createIssueTarget: Message?

    // M5.x — deep-link routing. When a system notification banner for a
    // message is tapped, `MainWindowView` sets this binding to the target
    // message ID before switching the sidebar to `.timeline`. The view
    // navigates to that message and clears the binding so a re-appearing
    // timeline doesn't re-navigate. Default `.constant(nil)` keeps every
    // existing call site parameter-free.
    @Binding private var pendingDeepLinkMessageID: String?

    init(pendingDeepLinkMessageID: Binding<String?> = .constant(nil)) {
        self._pendingDeepLinkMessageID = pendingDeepLinkMessageID
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    timelineBody(viewModel: viewModel)
                } else {
                    unconfiguredState
                }
            }
            .navigationTitle("Messages Timeline")
            .navigationDestination(for: Message.ID.self) { id in
                MessageDetailView(messageID: id)
            }
        }
        .task {
            // Build the view model once we have the environment in
            // hand; SwiftUI doesn't expose `@Environment` during
            // `init`, so deferred construction inside `.task` is the
            // canonical pattern.
            if viewModel == nil, let environment {
                let model = TimelineViewModel(messages: environment.messages)
                viewModel = model
                await model.initialLoad()
            }
        }
        .task(id: environmentEventBusToken) {
            // Subscribe to composer events so writes in the composer
            // window flow into the timeline without a full refetch.
            // `task(id:)` re-runs if the environment ever changes
            // identity.
            guard let environment, let viewModel else { return }
            for await event in environment.composerEventBus.events() {
                viewModel.apply(event: event)
            }
        }
        // Repost sheet — opens with the original message and dismisses
        // itself on success / cancel.
        .sheet(item: $repostTarget) { target in
            RepostSheetView(original: target)
        }
        // Edit sheet — reuses the composer window UI inside a sheet so
        // the user can edit without leaving the timeline context.
        .sheet(item: $editTarget) { target in
            ComposerWindowView(mode: .edit(messageID: target.id, original: target))
        }
        // Report sheet (work-consolidation.md G2). Presented when the row's
        // "Report…" item fires. The action VM carries the message id so
        // it submits a message report; dismissing clears it.
        .sheet(
            isPresented: Binding(
                get: { reportActionVM != nil },
                set: { if !$0 { reportActionVM = nil } }
            )
        ) {
            if let reportActionVM {
                ReportReasonSheet(viewModel: reportActionVM)
            }
        }
        // Create-GitHub-issue-from-message sheet (work-consolidation.md G4).
        // Presented when the row's "Create GitHub Issue…" item fires.
        .sheet(item: $createIssueTarget) { target in
            if let environment {
                CreateIssueFromMessageView(message: target, environment: environment)
            }
        }
        .confirmationDialog(
            "Delete this post?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { target in
            Button("Delete", role: .destructive) {
                if let viewModel {
                    Task { await viewModel.deleteMessage(id: target.id) }
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { _ in
            Text("This action cannot be undone.")
        }
        // M5.x — deep-link navigation. `pendingDeepLinkMessageID` is set
        // by `MainWindowView` when the user taps a system notification
        // banner targeting a message. We handle it on appear (the sidebar
        // just switched to timeline) and on change (timeline was already
        // visible when the banner was tapped), then immediately clear the
        // binding so re-appearing timelines don't re-navigate.
        .onAppear {
            if let id = pendingDeepLinkMessageID {
                selection = id
                pendingDeepLinkMessageID = nil
            }
        }
        .onChange(of: pendingDeepLinkMessageID) { _, newID in
            if let id = newID {
                selection = id
                pendingDeepLinkMessageID = nil
            }
        }
    }

    /// Stable token derived from the environment identity so
    /// `task(id:)` re-subscribes if the environment is swapped.
    private var environmentEventBusToken: ObjectIdentifier? {
        environment.map { ObjectIdentifier($0) }
    }

    // MARK: - Moderation

    /// Blocks the message author, then refreshes the timeline so their
    /// posts drop out of the feed. Errors are swallowed at the view
    /// boundary — the timeline refresh reflects the authoritative state.
    private func moderateBlock(author username: String) {
        guard let environment else { return }
        Task {
            try? await environment.moderation.block(username: username)
            await viewModel?.refresh()
        }
    }

    /// Mutes the message author, then refreshes the timeline.
    private func moderateMute(author username: String) {
        guard let environment else { return }
        Task {
            try? await environment.moderation.mute(username: username)
            await viewModel?.refresh()
        }
    }

    // MARK: - Body sections

    @ViewBuilder
    private func timelineBody(viewModel: TimelineViewModel) -> some View {
        VStack(spacing: 0) {
            toolbar(viewModel: viewModel)
            Divider()
            content(viewModel: viewModel)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private func toolbar(viewModel: TimelineViewModel) -> some View {
        HStack(spacing: 12) {
            Picker(
                "Scope",
                selection: Binding(
                    get: { viewModel.scope },
                    set: { newValue in
                        Task { await viewModel.changeScope(newValue) }
                    }
                )
            ) {
                Text("All").tag(TimelineScope.all)
                Text("Mine").tag(TimelineScope.mine)
                Text("Following").tag(TimelineScope.following)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            .accessibilityLabel("Timeline scope")

            HStack(spacing: 6) {
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Filter by tag", text: $tagDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await viewModel.setTagFilter(tagDraft) }
                    }
                if !tagDraft.isEmpty {
                    Button {
                        tagDraft = ""
                        Task { await viewModel.setTagFilter(nil) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear tag filter")
                }
            }
            .frame(maxWidth: 280)

            Spacer()

            // Visible compose affordance (parity with ⌘N / File → New Message).
            // Opens the same single-instance composer window; a second tap
            // re-focuses the existing window rather than spawning another.
            Button {
                openWindow(id: ComposeWindowID.newPost)
            } label: {
                Label("New Message", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .help("Compose a new message (⌘N)")
            .accessibilityLabel("New Message")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func content(viewModel: TimelineViewModel) -> some View {
        // Following has no API endpoint yet — always show the coming-soon
        // state regardless of load / error / empty conditions (App Store
        // Guideline 2.1: every visible control must work or show a graceful
        // unavailable state).
        if viewModel.scope == .following {
            followingComingSoonState
        } else if let error = viewModel.error, viewModel.messagesLoaded.isEmpty {
            errorState(error: error, viewModel: viewModel)
        } else if viewModel.messagesLoaded.isEmpty, viewModel.isLoading {
            loadingState
        } else if viewModel.messagesLoaded.isEmpty {
            emptyState
        } else {
            messageList(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func messageList(viewModel: TimelineViewModel) -> some View {
        let currentUserID = environment?.currentUserStore.currentUserID
        List(selection: $selection) {
            ForEach(viewModel.messagesLoaded) { message in
                NavigationLink(value: message.id) {
                    MessageRowView(
                        message: message,
                        canEdit: viewModel.canEdit(message, currentUserID: currentUserID),
                        onToggleDig: { tapped in
                            Task { await viewModel.toggleDig(on: tapped) }
                        },
                        onRepost: { tapped in
                            repostTarget = tapped
                        },
                        onEdit: { tapped in
                            editTarget = tapped
                        },
                        onDelete: { tapped in
                            deleteTarget = tapped
                        },
                        onBlock: { tapped in
                            moderateBlock(author: tapped.author.username)
                        },
                        onMute: { tapped in
                            moderateMute(author: tapped.author.username)
                        },
                        onReport: { tapped in
                            reportActionVM = ModerationActionViewModel(
                                username: tapped.author.username,
                                messageID: tapped.id,
                                service: environment?.moderation ?? NoopModerationService()
                            )
                        },
                        onCreateGitHubIssue: { tapped in
                            createIssueTarget = tapped
                        }
                    )
                }
                .onAppear {
                    // Trigger paging when we surface the row that's
                    // five from the bottom — keeps scroll smooth and
                    // never fires while a load is in flight (the view
                    // model gates).
                    if shouldLoadMore(for: message, in: viewModel.messagesLoaded) {
                        Task { await viewModel.loadMore() }
                    }
                }
            }
            if viewModel.isLoading && !viewModel.messagesLoaded.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading more messages")
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(.inset)
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading timeline…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("No messages")
                .font(.ilSubtitle())
            Text("Posts in this feed will appear here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var followingComingSoonState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Following feed coming soon")
                .font(.ilSubtitle())
            Text("The Following timeline is not yet available.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(error: Error, viewModel: TimelineViewModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load the timeline")
                .font(.ilSubtitle())
            Text(error.localizedDescription)
                .font(.ilSubtitle())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unconfiguredState: some View {
        // Hit only if the scene wasn't wired through `AppEnvironment`,
        // which is a programmer error rather than a runtime one — keep
        // the message diagnostic rather than user-facing.
        VStack(spacing: 8) {
            Image(systemName: "wrench.adjustable")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Timeline unavailable")
                .font(.ilSubtitle())
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func shouldLoadMore(for message: Message, in loaded: [Message]) -> Bool {
        guard let index = loaded.firstIndex(where: { $0.id == message.id }) else { return false }
        return index >= max(0, loaded.count - 5)
    }
}
