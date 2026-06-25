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
            // Read-only in v1 (P3.3): a footnote so the missing
            // cancel / reschedule affordance is intentional, not a gap.
            Section {
                ForEach(viewModel.posts) { post in
                    ScheduledPostRow(post: post)
                }
            } footer: {
                Text("Cancelling or rescheduling a queued post isn't available yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Nothing scheduled")
                .font(.headline)
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
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load scheduled posts")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
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
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Scheduled posts unavailable")
                .font(.headline)
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ScheduledPostRow

/// One queued scheduled post: its publish time plus a body preview. No
/// destructive affordance (P3.3 — read-only v1).
private struct ScheduledPostRow: View {
    let post: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let scheduledAt = post.scheduledAt {
                Label(Self.dateFormatter.string(from: scheduledAt), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            Text(post.text.isEmpty ? "(No text)" : post.text)
                .font(.body)
                .lineLimit(3)
                .foregroundStyle(post.text.isEmpty ? .secondary : .primary)
            if !post.tags.isEmpty {
                Text(post.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
