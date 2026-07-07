// ScheduledPostsRootView
//
// The "Scheduled" sidebar section (PLAN.md §5 — "Scheduled sidebar
// section", §6 M6). A thin shell over `ScheduledPostsViewModel`: it
// observes state, dispatches the load intent, and leaves loading /
// error / empty logic in the view model so unit tests cover the
// behavior without touching SwiftUI.
//
// v1 is read-only (backend ask P3.3 — no cancel / reschedule endpoint):
// the list surfaces what is queued and the empty state points the user
// at the composer for scheduling a new post. Rows carry no destructive
// affordance.
//
// Per Decision 0003 the view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct ScheduledPostsRootView: View {

    @Environment(\.appEnvironment) private var environment
    @Environment(\.openWindow) private var openWindow

    @State private var viewModel: ScheduledPostsViewModel?
    @State private var reschedulingPost: Message? = nil

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
        .sheet(item: $reschedulingPost) { post in
            RescheduleSheet(post: post) { newDate in
                Task { await viewModel?.reschedule(post: post, to: newDate) }
                reschedulingPost = nil
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
            let vm = ScheduledPostsViewModel(messages: environment.messages)
            viewModel = vm
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
                            Button("Reschedule\u{2026}") {
                                reschedulingPost = post
                            }
                            Button("Cancel Post", role: .destructive) {
                                Task { await viewModel.cancel(post: post) }
                            }
                        }
                }
            }
        }
        .listStyle(.inset)
        .refreshable {
            await viewModel.load()
        }
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

// MARK: - RescheduleSheet

private struct RescheduleSheet: View {
    let post: Message
    let onReschedule: (Date) -> Void

    @State private var selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    init(post: Message, onReschedule: @escaping (Date) -> Void) {
        self.post = post
        self.onReschedule = onReschedule
        _selectedDate = State(initialValue: post.scheduledAt ?? Date().addingTimeInterval(3600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reschedule Post")
                .font(.ilTitle(18))
            Text(post.text.isEmpty ? "(No text)" : post.text)
                .font(.ilBody())
                .lineLimit(2)
                .foregroundStyle(.secondary)
            DatePicker(
                "Publish at",
                selection: $selectedDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Reschedule") {
                    onReschedule(selectedDate)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 320, minHeight: 200)
    }
}

// MARK: - ScheduledPostRow

/// One queued scheduled post: its publish time plus a body preview.
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
        return parts.joined(separator: ". ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
