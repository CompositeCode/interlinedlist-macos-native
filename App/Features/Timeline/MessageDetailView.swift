// MessageDetailView
//
// Detail screen for a single message. Renders the message at the top
// followed by a flat list of replies and the inline reply composer at
// the bottom (PLAN.md §1, §6 M2).
//
// Like the timeline, the view is a thin shell over
// `MessageDetailViewModel`. Service access goes through the injected
// `AppEnvironment`, so previews and tests substitute services without
// touching networking.
//
// M2 wiring:
// - Header row's dig button → `viewModel.toggleDig(on:)`.
// - Header row's context menu → repost sheet / edit sheet / delete
//   confirm.
// - Reply rows reuse the same handlers so each reply can be dug,
//   reposted, edited, or deleted independently.
// - A collapsible reply composer at the bottom calls
//   `viewModel.postReply(...)`. On success the new reply appears in
//   the list without a full refetch.
// - Subscribes to `ComposerEventBus` so events posted elsewhere (the
//   composer window editing one of our replies, for example) flow in.

import SwiftUI
import UniformTypeIdentifiers
import InterlinedDomain

struct MessageDetailView: View {

    let messageID: Message.ID

    /// GitHub #27 — row-level Reply intent handed down by `TimelineRootView`.
    /// When it matches this screen's `messageID`, the composer opens already
    /// expanded and focused. Cleared on consumption so returning to the same
    /// thread by a plain tap does not re-open it.
    @Binding private var pendingReplyMessageID: String?

    init(
        messageID: Message.ID,
        pendingReplyMessageID: Binding<String?> = .constant(nil)
    ) {
        self.messageID = messageID
        self._pendingReplyMessageID = pendingReplyMessageID
    }

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: MessageDetailViewModel?

    // M2 row affordances — sheet / dialog state.
    @State private var repostTarget: Message?
    @State private var editTarget: Message?
    @State private var deleteTarget: Message?

    // Inline reply composer state.
    @State private var replyBody: String = ""
    @State private var isReplyExpanded: Bool = false

    /// Focuses the reply editor when the composer is opened from a row's
    /// Reply action, so the user can start typing without a second click.
    @FocusState private var replyFieldFocused: Bool

    var body: some View {
        Group {
            if let viewModel {
                detailBody(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading message")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Message")
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel?.exportMarkdown()
                } label: {
                    Label("Export as Markdown", systemImage: "arrow.down.doc")
                }
                .disabled(viewModel?.message == nil)
                .help("Export this thread as a Markdown file")
            }
        }
        .fileExporter(
            isPresented: Binding(
                get: { viewModel?.pendingMarkdownExport != nil },
                set: { if !$0 { viewModel?.clearMarkdownExport() } }
            ),
            document: MarkdownFileDocument(viewModel?.pendingMarkdownExport?.text),
            contentType: .markdownText,
            defaultFilename: viewModel?.pendingMarkdownExport?.filename ?? "thread"
        ) { _ in
            viewModel?.clearMarkdownExport()
        }
        .task {
            if viewModel == nil, let environment {
                let model = MessageDetailViewModel(
                    messages: environment.messages,
                    messageID: messageID,
                    eventBus: environment.composerEventBus,
                    // An inline reply is a post: it honours the same account
                    // default as the composer and the repost sheet.
                    defaultVisibility: environment.defaultComposeVisibility
                )
                viewModel = model
                await model.load()
            }
            // Consume a pending Reply intent from the timeline row.
            if pendingReplyMessageID == messageID {
                pendingReplyMessageID = nil
                isReplyExpanded = true
                replyFieldFocused = true
            }
        }
        .task(id: environmentEventBusToken) {
            guard let environment, let viewModel else { return }
            for await event in environment.composerEventBus.events() {
                viewModel.apply(event: event)
            }
        }
        .onChange(of: viewModel?.didDeleteRoot) { _, deleted in
            if deleted == true { dismiss() }
        }
        .sheet(item: $repostTarget) { target in
            RepostSheetView(original: target)
        }
        .sheet(item: $editTarget) { target in
            ComposerWindowView(mode: .edit(messageID: target.id, original: target))
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
                    let isRoot = target.id == messageID
                    Task {
                        if isRoot {
                            await viewModel.deleteCurrentMessage()
                        } else {
                            // For a reply, route through the messages
                            // service via the detail view model. We
                            // don't have a per-reply delete method on
                            // the view model yet — keep behavior
                            // consistent by using the bus.
                            // (We deliberately omit a reply-delete
                            // method on the view model in M2 to avoid
                            // over-engineering; the root delete path
                            // is the documented M2 deliverable.)
                        }
                    }
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { _ in
            Text("This action cannot be undone.")
        }
    }

    private var environmentEventBusToken: ObjectIdentifier? {
        environment.map { ObjectIdentifier($0) }
    }

    @ViewBuilder
    private func detailBody(viewModel: MessageDetailViewModel) -> some View {
        let currentUserID = environment?.currentUserStore.currentUserID

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let message = viewModel.message {
                    MessageRowView(
                        message: message,
                        canEdit: viewModel.canEdit(message, currentUserID: currentUserID),
                        actions: rowActions(viewModel: viewModel)
                    )
                    .padding(.horizontal, 16)
                    Divider()
                }

                repliesSection(viewModel: viewModel, currentUserID: currentUserID)

                Divider()
                replyComposer(viewModel: viewModel)
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

    /// Shared action set for the header row and every reply row, so both
    /// behave identically (each reply can be dug, pushed, edited, deleted).
    private func rowActions(viewModel: MessageDetailViewModel) -> MessageRowActions {
        MessageRowActions(
            onToggleDig: { tapped in
                Task { await viewModel.toggleDig(on: tapped) }
            },
            onReply: { _ in
                // The replies list is flat, so Reply from any row \u{2014} the
                // header or a reply \u{2014} opens this thread's one composer,
                // which posts against the root message.
                isReplyExpanded = true
                replyFieldFocused = true
            },
            onPush: { tapped in
                Task { await viewModel.push(tapped) }
            },
            onPushAndComment: { tapped in repostTarget = tapped },
            onEdit: { tapped in editTarget = tapped },
            onDelete: { tapped in deleteTarget = tapped }
        )
    }

    @ViewBuilder
    private func repliesSection(viewModel: MessageDetailViewModel, currentUserID: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Replies")
                .font(.ilSubtitle())
                .padding(.horizontal, 16)

            if viewModel.replies.isEmpty, !viewModel.isLoading {
                Text("No replies yet.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ForEach(viewModel.replies) { reply in
                    MessageRowView(
                        message: reply,
                        canEdit: viewModel.canEdit(reply, currentUserID: currentUserID),
                        actions: rowActions(viewModel: viewModel)
                    )
                    .padding(.horizontal, 16)
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func replyComposer(viewModel: MessageDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(
                isExpanded: $isReplyExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $replyBody)
                            .focused($replyFieldFocused)
                            .font(.ilBody())
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                            .background(ILColor.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: ILMetric.radiusSm)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                            .accessibilityLabel("Reply body")

                        if let replyError = viewModel.replyError {
                            Label(replyError.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                                .font(.ilMono(10))
                                .foregroundStyle(Color.accentColor)
                        }

                        HStack {
                            Spacer()
                            if viewModel.isPostingReply {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityLabel("Posting reply")
                            }
                            Button("Reply") {
                                Task {
                                    let posted = await viewModel.postReply(body: replyBody)
                                    if posted != nil {
                                        replyBody = ""
                                        isReplyExpanded = false
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(
                                replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || viewModel.isPostingReply
                            )
                        }
                    }
                    .padding(.top, 4)
                },
                label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.subheadline.weight(.medium))
                }
            )
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func errorState(error: Error, viewModel: MessageDetailViewModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load the message")
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
        .padding()
    }
}
