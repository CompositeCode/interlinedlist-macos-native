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

    /// The public-document count, reported upward by the documents column.
    ///
    /// Lives here rather than on the view model because the column already
    /// fetches the documents for its own rows: asking a second time would be a
    /// duplicate request whose answer could disagree with what is on screen.
    @State private var documentCount: Int?

    /// Mirrors of the view model's session-derived flags, read in the body.
    private var isOwnProfile: Bool { viewModel?.isOwnProfile ?? false }
    private var isSignedIn: Bool { viewModel?.isSignedIn ?? false }

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
                let model = ProfileViewModel(
                    social: environment.social,
                    relationshipReader: environment.followRelationshipReader,
                    currentUserID: { [weak environment] in
                        environment?.currentUserStore.currentUserID
                    },
                    currentUsername: { [weak environment] in
                        environment?.currentUserStore.currentUsername
                    }
                )
                viewModel = model
                // Land on your own profile (GitHub #44 / G32). The session
                // already knows who the user is, so opening Profile to an
                // "enter a username" prompt made the one profile everybody
                // wants to see the one that took the most typing to reach.
                // The lookup field stays, as the way to visit someone else.
                await model.loadOwnProfileIfNeeded()
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
                .accessibilityHidden(true)
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
            VStack(alignment: .leading, spacing: 16) {
                ProfileHeaderView(
                    profile: profile,
                    counts: counts,
                    mutuals: mutuals,
                    followButton: followButton
                )
                // The five stat tiles the web profile shows (GitHub #44).
                // Followers / Following / Posts / Lists come straight off the
                // profile payload — the client had been decoding the last two
                // and dropping them at the domain boundary. Documents has no
                // count on that payload, so the documents column reports its
                // own, which is also why the tile and the column can never
                // disagree.
                ProfileStatTilesView(
                    profile: profile,
                    counts: counts,
                    documentCount: documentCount
                )
                .padding(.horizontal, 16)

                // work-consolidation.md G24 — the documents column the web
                // profile has and macOS lacked. Self-contained: it owns its
                // view model and its own load, so this stays one line and the
                // Social feature learns nothing about `DocumentsServicing`.
                Divider()
                PublicUserDocumentsView(
                    username: profile.username,
                    onCountChange: { documentCount = $0 }
                )
                .padding(.horizontal, 16)

                // The public-lists column, with a Watch button per row when the
                // profile is someone else's (GitHub #44 / G32).
                Divider()
                PublicUserListsView(
                    username: profile.username,
                    isOwnProfile: isOwnProfile,
                    isSignedIn: isSignedIn
                )
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - States

    private var promptState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Browse a public profile")
                .font(.ilSubtitle())
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
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Profile unavailable")
                .font(.ilSubtitle())
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
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load profile")
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
            Text("Profile unavailable")
                .font(.ilSubtitle())
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
