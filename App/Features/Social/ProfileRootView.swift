// ProfileRootView
//
// Read-only public profile surface (PLAN.md §1 "Profile", §6 M1). The
// user enters a username and we render that user's public profile
// header inside a `NavigationStack`; subsequent profile sub-routes
// (recent messages, followers, following) land in later milestones.
//
// The M1 load is the public-author fallback documented in
// `docs/decisions/0002-public-profile-fallback.md`: identity is
// projected from the embedded author on the user's most recent public
// message, and `SocialError.profileUnavailable(username:)` is the
// typed "no public messages, so no profile to synthesize" outcome —
// rendered here as a friendly empty state, not as a generic error.
//
// The view is a thin shell over `ProfileViewModel`: it observes state,
// dispatches user intents, and leaves all loading / error logic in the
// view model so unit tests cover the behavior without touching SwiftUI.
//
// Per decision 0003 (App-layer Kit-import policy), this view consumes the
// domain `FollowCounts` and does not `import InterlinedKit`.

import SwiftUI
import InterlinedDomain

struct ProfileRootView: View {

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: ProfileViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    profileBody(viewModel: viewModel)
                } else {
                    unconfiguredState
                }
            }
            .navigationTitle("Profile")
        }
        .task {
            // Defer construction until the environment is in scope.
            // SwiftUI doesn't expose `@Environment` during `init`, so
            // building the view model in `.task` is the canonical
            // pattern.
            if viewModel == nil, let environment {
                viewModel = ProfileViewModel(
                    social: environment.social,
                    relationshipReader: environment.followRelationshipReader,
                    currentUserID: { [weak environment] in
                        environment?.currentUserStore.currentUserID
                    }
                )
            }
        }
    }

    // MARK: - Body sections

    @ViewBuilder
    private func profileBody(viewModel: ProfileViewModel) -> some View {
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
    private func toolbar(viewModel: ProfileViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "at")
                .foregroundStyle(.secondary)
            TextField(
                "Browse a user's profile",
                text: Binding(
                    get: { viewModel.usernameInput },
                    set: { viewModel.usernameInput = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                Task { await viewModel.loadProfile(username: viewModel.usernameInput) }
            }
            .accessibilityLabel("Username to browse")

            Button("Browse") {
                Task { await viewModel.loadProfile(username: viewModel.usernameInput) }
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
    private func content(viewModel: ProfileViewModel) -> some View {
        if viewModel.loadedUsername == nil, viewModel.error == nil {
            promptState
        } else if let error = viewModel.error, viewModel.profile == nil {
            // Decision 0002: distinguish the typed "no public messages"
            // outcome from a generic API error so the user sees a
            // friendly empty rather than a scary error card.
            if case let SocialError.profileUnavailable(username) = error {
                profileUnavailableState(username: username)
            } else {
                errorState(error: error, viewModel: viewModel)
            }
        } else if viewModel.profile == nil, viewModel.isLoading {
            loadingState
        } else if let profile = viewModel.profile {
            profileSection(
                profile: profile,
                counts: viewModel.counts,
                mutuals: viewModel.mutuals,
                followButton: viewModel.followButton
            )
        } else {
            // Defensive: loadedUsername is set, no error, no profile,
            // not loading. Should be unreachable under the current view
            // model contract, but render the loading state rather than
            // a blank pane if state ever drifts.
            loadingState
        }
    }

    @ViewBuilder
    private func profileSection(
        profile: UserProfile,
        counts: FollowCounts?,
        mutuals: MutualCounts?,
        followButton: FollowButtonViewModel?
    ) -> some View {
        ScrollView {
            ProfileHeaderView(
                profile: profile,
                counts: counts,
                mutuals: mutuals,
                followButton: followButton
            )
        }
    }

    // MARK: - States

    private var promptState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Browse a public profile")
                .font(.headline)
            Text("Enter a username to view their public profile.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading profile…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func profileUnavailableState(username: String) -> some View {
        // Decision 0002: the public-author fallback can't synthesize a
        // profile for a user with zero public messages. Surface this as
        // an explanatory empty state so the user understands why nothing
        // renders — and so it doesn't look like a transport failure.
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Profile unavailable")
                .font(.headline)
            Text("@\(username) has no public messages yet, so we can't show their profile in this version.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(error: Error, viewModel: ProfileViewModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load profile")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
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
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Profile unavailable")
                .font(.headline)
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
