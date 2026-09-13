// ScheduledPostsRootView
//
// The "Scheduled" sidebar section (PLAN.md §5 — "Scheduled sidebar
// section", §6 M6). A thin shell over `ScheduledPostsViewModel`: it
// observes state, dispatches the load intent, and leaves loading /
// error / empty logic in the view model so unit tests cover the
// behavior without touching SwiftUI.
//
// Rows support cancel (DELETE /api/messages/[id]) and reschedule
// (PATCH /api/messages/[id] with a new `scheduledAt`). Both operations
// use the optimistic-UI pattern (NW-3): the list is updated locally
// before the network call and rolled back on failure.
//
// GitHub #55: each row now shows the cross-post destinations the post will fan
// out to, so they are readable without opening anything. The reschedule sheet
// became `EditScheduledPostSheet`, which shows the post's content and
// destinations alongside the (editable) publish time. Those two are read-only on
// purpose, not by oversight: the live API has no route that edits them —
// `PATCH /api/messages/[id]` honours `scheduledAt` alone and silently discards a
// `content` sent beside it, and the web client ships no message `PATCH` at all.
// The sheet says so plainly rather than offering a control that cannot save.
//
// Per Decision 0003 the view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct ScheduledPostsRootView: View {

    /// Pre-warmed view model supplied by `MainWindowView` via the launch
    /// coordinator. When non-nil the view skips creation and its cache-first
    /// initial load; a re-appearance still honors the freshness TTL.
    var preloadedViewModel: ScheduledPostsViewModel? = nil

    @Environment(\.appEnvironment) private var environment
    @Environment(\.openWindow) private var openWindow

    @State private var viewModel: ScheduledPostsViewModel?
    @State private var editingPost: Message? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    bodyContent(viewModel: viewModel)
                } else {
                    unconfiguredState
                }
            }
            .navigationTitle("Scheduled")
            .toolbar {
                if let viewModel {
                    ToolbarItemGroup(placement: .primaryAction) {
                        // Stale-while-revalidate: a subtle spinner while a
                        // background refresh runs over cached posts already on
                        // screen. The full-screen loading state only shows on a
                        // cold start.
                        if viewModel.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .help("Refreshing scheduled posts…")
                        }
                        Button {
                            openWindow(id: ComposeWindowID.newPost)
                        } label: {
                            Label("New Post", systemImage: "square.and.pencil")
                        }
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .sheet(item: $editingPost) { post in
            EditScheduledPostSheet(post: post) { newDate in
                Task { await viewModel?.reschedule(post: post, to: newDate) }
                editingPost = nil
            }
        }
        .task {
            await bootstrap()
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        guard let environment else { return }
        if viewModel == nil {
            if let preloaded = preloadedViewModel {
                // Pre-warmed by the launch coordinator — its cache-first load
                // is already in flight / done; don't refetch here.
                viewModel = preloaded
            } else {
                let vm = ScheduledPostsViewModel(messages: environment.messages)
                viewModel = vm
                await vm.load()
            }
        } else if let vm = viewModel, vm.shouldRefresh {
            // Re-appearance past the freshness TTL — revalidate; within the
            // TTL we trust the cache and skip the network.
            await vm.load()
        }
    }

    // MARK: - Body sections

    @ViewBuilder
    private func bodyContent(viewModel: ScheduledPostsViewModel) -> some View {
        if viewModel.posts.isEmpty, !viewModel.hasLoadedOnce {
            loadingState
        } else if let error = viewModel.error, viewModel.posts.isEmpty {
            errorState(error: error, viewModel: viewModel)
        } else if viewModel.posts.isEmpty {
            emptyState
        } else {
            list(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func list(viewModel: ScheduledPostsViewModel) -> some View {
        List {
            Section {
                ForEach(viewModel.posts) { post in
                    ScheduledPostRow(post: post)
                        .contextMenu {
                            Button("Edit\u{2026}") {
                                editingPost = post
                            }
                            Button("Cancel Post", role: .destructive) {
                                Task { await viewModel.cancel(post: post) }
                            }
                        }
                }
            } header: {
                // A failed cancel / reschedule is reported here rather than
                // replacing the list: the rows are still valid, only the last
                // mutation was not applied.
                if let actionError = viewModel.actionError {
                    actionErrorBanner(
                        message: actionError.localizedDescription,
                        onDismiss: { viewModel.clearActionError() }
                    )
                }
            }
        }
        .listStyle(.inset)
        .refreshable {
            await viewModel.load()
        }
    }

    private func actionErrorBanner(
        message: String,
        onDismiss: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.accentColor)
            Text(message)
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
                .textCase(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.link)
                .font(.ilMono(10))
                .textCase(nil)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scheduled post action failed. \(message)")
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading scheduled posts…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Nothing scheduled")
                .font(.ilSubtitle())
            Text("Posts you schedule for later will appear here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("New Post") {
                openWindow(id: ComposeWindowID.newPost)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(
        error: Error,
        viewModel: ScheduledPostsViewModel
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load scheduled posts")
                .font(.ilSubtitle())
            Text(error.localizedDescription)
                .font(.ilSubtitle())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
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
            Text("Scheduled posts unavailable")
                .font(.ilSubtitle())
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - EditScheduledPostSheet

/// The editor for a queued post (GitHub #55).
///
/// The publish time is editable and is the one change the live API accepts. The
/// body and the cross-post destinations are shown but not editable — see the
/// file header: no live route can change them, so offering a text field here
/// would let the user type an edit that silently never saves. Showing them
/// read-only still answers the question the sheet exists to answer ("what is
/// this post, and where is it going?") and the footnote says why they are
/// fixed.
private struct EditScheduledPostSheet: View {
    let post: Message
    let onReschedule: (Date) -> Void

    @State private var selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    /// How far ahead of now the earliest selectable time sits. A minute of
    /// slack, rather than `Date()` exactly, so a sheet left open for a moment
    /// cannot submit a time that went stale between render and click.
    private static let minimumLeadTime: TimeInterval = 60

    init(post: Message, onReschedule: @escaping (Date) -> Void) {
        self.post = post
        self.onReschedule = onReschedule
        // Boundary: a post about to fire (or one whose time has just passed
        // while the list sat on screen) would seed a selection outside the
        // picker's own range. Clamp it forward so the sheet opens on a valid,
        // submittable time instead of relying on SwiftUI to silently fix it.
        let floorDate = Date().addingTimeInterval(Self.minimumLeadTime)
        let seed = post.scheduledAt ?? Date().addingTimeInterval(3600)
        _selectedDate = State(initialValue: max(seed, floorDate))
    }

    private var earliestSelectableDate: Date {
        Date().addingTimeInterval(Self.minimumLeadTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Scheduled Post")
                .font(.ilTitle(18))

            VStack(alignment: .leading, spacing: 4) {
                Text("Message")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                Text(post.text.isEmpty ? "(No text)" : post.text)
                    .font(.ilBody())
                    .lineLimit(4)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Destinations")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                ScheduledDestinationsLabel(destinations: post.scheduledDestinations)
            }

            DatePicker(
                "Publish at",
                selection: $selectedDate,
                in: earliestSelectableDate...,
                displayedComponents: [.date, .hourAndMinute]
            )

            Text("Only the publish time can be changed. To change the message or its "
                 + "destinations, cancel this post and schedule a new one.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    onReschedule(selectedDate)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedDate <= Date())
            }
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 300)
    }
}

// MARK: - ScheduledDestinationsLabel

/// The destination summary shared by the row and the edit sheet (GitHub #55).
///
/// Three distinct states, deliberately not collapsed into two: `nil` means the
/// server sent no config for this message (also what a row painted from the
/// on-disk cache shows before the first revalidation), while an empty config
/// means the post really is going to InterlinedList only.
private struct ScheduledDestinationsLabel: View {
    let destinations: ScheduledDestinations?

    var body: some View {
        Group {
            if let destinations, !destinations.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(destinations.displayNames.joined(separator: " \u{00B7} "))
                }
            } else if destinations != nil {
                Text("InterlinedList only")
            } else {
                Text("Destinations unavailable")
            }
        }
        .font(.ilMono(10))
        .foregroundStyle(.secondary)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let destinations else { return "Cross-post destinations unavailable" }
        guard !destinations.isEmpty else { return "Posting to InterlinedList only" }
        return "Also posting to \(destinations.displayNames.joined(separator: ", "))"
    }
}

// MARK: - ScheduledPostRow

/// One queued scheduled post: its publish time, a body preview, and — per
/// GitHub #55 — the cross-post destinations it will fan out to, so they are
/// readable without opening the editor.
private struct ScheduledPostRow: View {
    let post: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let scheduledAt = post.scheduledAt {
                Label(Self.dateFormatter.string(from: scheduledAt), systemImage: "clock")
                    .font(.ilMono(10))
                    .foregroundStyle(Color.accentColor)
            }
            Text(post.text.isEmpty ? "(No text)" : post.text)
                .font(.ilBody())
                .lineLimit(3)
                .foregroundStyle(post.text.isEmpty ? .secondary : .primary)
            if !post.tags.isEmpty {
                Text(post.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }
            // Only drawn when the server actually sent a config — a row with no
            // destination data stays as compact as it was before #55 rather than
            // carrying an "unavailable" line on every entry.
            if post.scheduledDestinations != nil {
                ScheduledDestinationsLabel(destinations: post.scheduledDestinations)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        var parts: [String] = []
        if let scheduledAt = post.scheduledAt {
            parts.append("Scheduled for \(Self.dateFormatter.string(from: scheduledAt))")
        }
        let bodyText = post.text.isEmpty ? "No text" : post.text
        parts.append(bodyText)
        if !post.tags.isEmpty {
            parts.append("Tags: \(post.tags.joined(separator: ", "))")
        }
        if let destinations = post.scheduledDestinations {
            parts.append(destinations.isEmpty
                         ? "Posting to InterlinedList only"
                         : "Also posting to \(destinations.displayNames.joined(separator: ", "))")
        }
        return parts.joined(separator: ". ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
