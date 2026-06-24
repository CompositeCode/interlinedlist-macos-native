// SocialRosterRootView
//
// Three-tab panel exposing the signed-in user's followers, following,
// and inbound follow requests (PLAN.md §1 "Follow system", §6 M5).
// Routed from the main window's sidebar by the new `.requests` case
// added in this wave; also reachable via `SocialMenuCommands`.
//
// The view is a thin shell over `SocialRosterViewModel`: it observes
// state, dispatches user intents, and leaves loading / error / write
// logic in the view model so unit tests cover the behavior without
// touching SwiftUI.
//
// When no session has resolved yet (current user id is nil per the
// M2 ownership-gating rule) the view renders an explanatory empty
// state rather than the empty roster — a follower list for an
// unknown user is meaningless.
//
// Per decision 0003 the view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct SocialRosterRootView: View {

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: SocialRosterViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    body(viewModel: viewModel)
                } else {
                    unconfiguredState
                }
            }
            .navigationTitle("Connections")
        }
        .task {
            guard viewModel == nil, let environment else { return }
            // Ownership-gate: no session → no roster (a follower list
            // for "unknown" is meaningless).
            guard let userID = environment.currentUserStore.currentUserID else { return }
            let vm = SocialRosterViewModel(
                social: environment.social,
                targetUserID: userID,
                notificationsEventBus: environment.notificationsEventBus
            )
            viewModel = vm
            await vm.initialLoad()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func body(viewModel: SocialRosterViewModel) -> some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: Binding(
                get: { viewModel.selectedTab },
                set: { viewModel.selectedTab = $0 }
            )) {
                ForEach(SocialRosterViewModel.Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            switch viewModel.selectedTab {
            case .followers:
                followersList(viewModel: viewModel)
            case .following:
                followingList(viewModel: viewModel)
            case .requests:
                requestsList(viewModel: viewModel)
            }
        }
        .refreshable {
            switch viewModel.selectedTab {
            case .followers:
                await viewModel.loadFollowers(reset: true)
            case .following:
                await viewModel.loadFollowing(reset: true)
            case .requests:
                await viewModel.loadRequests()
            }
        }
    }

    @ViewBuilder
    private func followersList(viewModel: SocialRosterViewModel) -> some View {
        rosterList(
            users: viewModel.followers,
            isLoading: viewModel.isLoadingFollowers,
            hasMore: viewModel.followersHasMore,
            error: viewModel.followersError,
            emptyTitle: "No followers yet",
            emptyMessage: "When other people follow you, you'll see them here.",
            retry: { await viewModel.loadFollowers(reset: true) },
            loadMore: { await viewModel.loadFollowers(reset: false) }
        )
    }

    @ViewBuilder
    private func followingList(viewModel: SocialRosterViewModel) -> some View {
        rosterList(
            users: viewModel.following,
            isLoading: viewModel.isLoadingFollowing,
            hasMore: viewModel.followingHasMore,
            error: viewModel.followingError,
            emptyTitle: "Not following anyone yet",
            emptyMessage: "When you follow other people, you'll see them here.",
            retry: { await viewModel.loadFollowing(reset: true) },
            loadMore: { await viewModel.loadFollowing(reset: false) }
        )
    }

    @ViewBuilder
    private func rosterList(
        users: [UserSummary],
        isLoading: Bool,
        hasMore: Bool,
        error: Error?,
        emptyTitle: String,
        emptyMessage: String,
        retry: @escaping () async -> Void,
        loadMore: @escaping () async -> Void
    ) -> some View {
        if let error, users.isEmpty {
            ErrorRosterState(error: error, retry: retry)
        } else if users.isEmpty, !isLoading {
            EmptyRosterState(title: emptyTitle, message: emptyMessage)
        } else {
            List(users) { user in
                UserRowView(user: user)
                    .onAppear {
                        if user.id == users.last?.id, hasMore {
                            Task { await loadMore() }
                        }
                    }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func requestsList(viewModel: SocialRosterViewModel) -> some View {
        if let error = viewModel.requestsError, viewModel.requests.isEmpty {
            ErrorRosterState(error: error, retry: { await viewModel.loadRequests() })
        } else if viewModel.requests.isEmpty, !viewModel.isLoadingRequests {
            EmptyRosterState(
                title: "No pending follow requests",
                message: "Requests from other accounts will show up here for you to approve or reject."
            )
        } else {
            List(viewModel.requests) { request in
                FollowRequestRow(request: request, viewModel: viewModel)
            }
            .listStyle(.inset)
        }
    }

    private var unconfiguredState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Sign in to see your connections")
                .font(.headline)
            Text("Followers, following, and follow requests appear here once you're signed in.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - UserRowView

private struct UserRowView: View {
    let user: UserSummary

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var avatar: some View {
        Group {
            if let url = user.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        avatarFallback
                    @unknown default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    private var avatarFallback: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.accentColor.opacity(0.6))
    }
}

// MARK: - FollowRequestRow

private struct FollowRequestRow: View {

    let request: FollowRequest
    @Bindable var viewModel: SocialRosterViewModel

    @State private var inFlight: Bool = false
    @State private var error: Error?

    var body: some View {
        HStack(spacing: 12) {
            UserRowView(user: request.user)
            Spacer()
            HStack(spacing: 6) {
                Button("Reject") {
                    Task { await act(approve: false) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(inFlight)

                Button("Approve") {
                    Task { await act(approve: true) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(inFlight)
            }
        }
        .padding(.vertical, 4)
    }

    private func act(approve: Bool) async {
        inFlight = true
        defer { inFlight = false }
        if approve {
            error = await viewModel.approve(request: request)
        } else {
            error = await viewModel.reject(request: request)
        }
    }
}

// MARK: - State stand-ins

private struct EmptyRosterState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorRosterState: View {
    let error: Error
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") {
                Task { await retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
