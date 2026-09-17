// PublicUserListsView
//
// The public-lists column on a profile (GitHub #44 / G32), mirroring
// `PublicUserDocumentsView`: a self-contained section, not a screen. It owns its
// view model, its loading state and its own empty copy, so the host profile view
// adds it in one line and never learns about `ListsServicing`.
//
// The Watch button appears only when the profile belongs to someone else and a
// session exists — watching your own list is meaningless, and offering the
// action while signed out would present a control that can only fail.
//
// Pure SwiftUI; no AppKit. Decision 0003: consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct PublicUserListsView: View {

    /// The handle to show lists for. A change re-triggers the load.
    let username: String

    /// Whether this profile is the signed-in user's own. Drives whether the
    /// Watch affordance is offered at all.
    let isOwnProfile: Bool

    /// Whether a session exists. `false` while signed out, where Watch would be
    /// a button that can only fail.
    let isSignedIn: Bool

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: PublicUserListsViewModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let viewModel {
                content(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: username) {
            // `@Environment` isn't readable during `init`, so the view model is
            // built here; `task(id:)` re-runs when the browsed handle changes,
            // which is exactly when a reload is wanted.
            guard let environment else { return }
            let model = viewModel ?? PublicUserListsViewModel(lists: environment.lists)
            viewModel = model
            await model.load(username: username)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Public lists")
                .font(.ilSubtitle())
            if viewModel?.isLoading == true {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading public lists")
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: PublicUserListsViewModel) -> some View {
        if let error = viewModel.error {
            errorState(error: error, viewModel: viewModel)
        } else if !viewModel.hasLoaded {
            // First load in flight — the header spinner is enough chrome.
            EmptyView()
        } else if viewModel.isEmpty {
            Text("@\(username) hasn't published any lists.")
                .font(.ilBody())
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.listsLoaded) { list in
                    PublicListRow(
                        list: list,
                        showsWatch: !isOwnProfile && isSignedIn,
                        isWatching: viewModel.isWatching(list.id),
                        isPending: viewModel.isWatchPending(list.id),
                        failure: viewModel.watchErrors[list.id],
                        onWatch: { Task { await viewModel.watch(listID: list.id) } }
                    )
                    if list.id != viewModel.listsLoaded.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func errorState(
        error: Error,
        viewModel: PublicUserListsViewModel
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(error.localizedDescription)
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
            Button("Try again") {
                Task { await viewModel.load(username: username) }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }
}

// MARK: - PublicListRow

private struct PublicListRow: View {

    let list: ListSummary
    let showsWatch: Bool
    let isWatching: Bool
    let isPending: Bool
    /// The message from a failed watch on *this* row, so the failure reports
    /// where it happened rather than against the whole column.
    let failure: String?
    let onWatch: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(list.title.isEmpty ? "Untitled list" : list.title)
                    .font(.ilBody())
                    .lineLimit(1)
                if let description = list.description, !description.isEmpty {
                    Text(description)
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let failure {
                    Text(failure)
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if showsWatch {
                watchButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var watchButton: some View {
        if isWatching {
            // Deliberately a label, not a toggle. The route's self-subscribe
            // branch has no documented un-watch counterpart, and offering an
            // Unwatch that silently does nothing would be worse than not
            // offering one — a watched list is managed from the Lists surface.
            Label("Watching", systemImage: "checkmark")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        } else {
            Button(action: onWatch) {
                if isPending {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("Watch")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isPending)
            .accessibilityLabel("Watch \(list.title)")
        }
    }
}
