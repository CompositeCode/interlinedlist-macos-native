// ListsBrowserView
//
// Public-list browser (PLAN.md §1 "Public list browsing", §6 M1).
// The user enters a username and we render that user's public lists
// in a `NavigationStack`; tapping a row pushes `ListDetailView` onto
// the detail column's own stack.
//
// The view is a thin shell over `ListsBrowserViewModel`: it observes
// state, dispatches user intents, and leaves all loading / paging
// logic in the view model so unit tests cover the behavior without
// touching SwiftUI.

import SwiftUI
import InterlinedDomain

struct ListsBrowserView: View {

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: ListsBrowserViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    browserBody(viewModel: viewModel)
                } else {
                    unconfiguredState
                }
            }
            .navigationTitle("Lists")
            .navigationDestination(for: ListDetailRoute.self) { route in
                ListDetailView(username: route.username, slug: route.slug)
            }
        }
        .task {
            // Defer construction until the environment is in scope.
            // SwiftUI doesn't expose `@Environment` during `init`, so
            // building the view model in `.task` is the canonical
            // pattern.
            if viewModel == nil, let environment {
                viewModel = ListsBrowserViewModel(lists: environment.lists)
            }
        }
    }

    // MARK: - Body sections

    @ViewBuilder
    private func browserBody(viewModel: ListsBrowserViewModel) -> some View {
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
    private func toolbar(viewModel: ListsBrowserViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "at")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                "Browse a user's lists",
                text: Binding(
                    get: { viewModel.usernameInput },
                    set: { viewModel.usernameInput = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                Task { await viewModel.loadInitial(username: viewModel.usernameInput) }
            }
            .accessibilityLabel("Username to browse")

            Button("Browse") {
                Task { await viewModel.loadInitial(username: viewModel.usernameInput) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if viewModel.loadedUsername != nil {
                Button {
                    viewModel.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear results")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func content(viewModel: ListsBrowserViewModel) -> some View {
        if viewModel.loadedUsername == nil, viewModel.error == nil {
            promptState
        } else if let error = viewModel.error, viewModel.lists_loaded.isEmpty {
            errorState(error: error, viewModel: viewModel)
        } else if viewModel.lists_loaded.isEmpty, viewModel.isLoading {
            loadingState
        } else if viewModel.lists_loaded.isEmpty {
            emptyState(username: viewModel.loadedUsername ?? "")
        } else {
            listSection(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func listSection(viewModel: ListsBrowserViewModel) -> some View {
        List {
            ForEach(viewModel.lists_loaded) { summary in
                NavigationLink(
                    value: ListDetailRoute(
                        username: viewModel.loadedUsername ?? "",
                        slug: summary.id
                    )
                ) {
                    ListRowSummaryView(summary: summary)
                }
                .onAppear {
                    // Trigger paging when we surface the row five from
                    // the bottom — keeps scroll smooth; the view model
                    // gates concurrent loads.
                    if shouldLoadMore(for: summary, in: viewModel.lists_loaded) {
                        Task { await viewModel.loadMore() }
                    }
                }
            }
            if viewModel.isLoading, !viewModel.lists_loaded.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading more lists")
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(.inset)
    }

    // MARK: - States

    private var promptState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Browse public lists")
                .font(.ilSubtitle())
            Text("Enter a username to browse their public lists.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading lists…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(username: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("No public lists")
                .font(.ilSubtitle())
            Text("@\(username) has no public lists yet.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(error: Error, viewModel: ListsBrowserViewModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load lists")
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
            Text("Lists unavailable")
                .font(.ilSubtitle())
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func shouldLoadMore(for summary: ListSummary, in loaded: [ListSummary]) -> Bool {
        guard let index = loaded.firstIndex(where: { $0.id == summary.id }) else { return false }
        return index >= max(0, loaded.count - 5)
    }
}

// MARK: - ListDetailRoute

/// Value-typed navigation route the browser pushes onto its stack.
/// `Hashable` is required by `.navigationDestination(for:)`. Keeping
/// this scoped to the Lists feature avoids leaking a UI concern into
/// the domain layer.
struct ListDetailRoute: Hashable {
    let username: String
    let slug: String
}
