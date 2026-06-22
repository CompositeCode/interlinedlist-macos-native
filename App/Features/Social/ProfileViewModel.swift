// ProfileViewModel
//
// Drives `ProfileRootView`: owns the username the user is browsing, the
// loaded profile, the follow counts follow-up, and the loading / error
// state. Reads through `SocialServicing` only — no direct API access —
// so unit tests substitute a stub service (PLAN.md §3, §7).
//
// M1 is read-only. The profile load is a single round-trip through the
// public-author fallback documented in `docs/decisions/0002-public-profile-fallback.md`:
// `SocialService.profile(username:)` returns identity only (id, username,
// displayName, avatarURL). Bio, joinedAt, isPrivate, follower / following
// counts are absent on that response. Once the profile resolves we fire a
// follow-up `social.counts(of: profile.id)` to backfill the count pair —
// failure there is *soft* (the profile is the load-bearing data and stays
// rendered).
//
// M2: when a `MessagesService.userMessages(username:)` wrapper exists on
// the Domain side, this view model grows a recent-messages tab. Today the
// kit-level builder (`Messages.userMessages(username:limit:offset:)`)
// exists but isn't wrapped by `MessagesService`, and the App layer is not
// permitted to call the kit directly (layering — see PLAN.md §3).

import Foundation
import Observation
import InterlinedDomain
import InterlinedKit

@MainActor
@Observable
final class ProfileViewModel {

    // MARK: - Dependencies

    private let social: SocialServicing

    // MARK: - Observable state

    /// Text the user is typing into the browse field. Two-way bound from
    /// the view; not necessarily the username currently loaded.
    var usernameInput: String = ""

    /// The username whose profile is currently loaded (or being loaded).
    /// `nil` before the first successful load. Distinct from
    /// `usernameInput` so the view can show "@alice" even while the user
    /// edits the input toward something else.
    private(set) var loadedUsername: String?

    /// The resolved profile from `SocialService.profile(username:)`. Per
    /// decision 0002 only `{ id, username, displayName, avatarURL }` are
    /// populated; the view renders the remaining fields conditionally.
    private(set) var profile: UserProfile?

    /// The follower / following counts from the follow-up
    /// `social.counts(of:)` call. `nil` when the counts request hasn't
    /// completed yet or failed. Counts failure is *soft* — `profile`
    /// stays set so the header still renders.
    private(set) var counts: FollowCountsDTO?

    /// True while either the profile load or the counts follow-up is in
    /// flight. The view shows a single progress indicator for both.
    private(set) var isLoading: Bool = false

    /// Surfaced error from the profile load. The view distinguishes
    /// `SocialError.profileUnavailable` from generic API errors so the
    /// user sees a friendly "no public messages yet" message in the
    /// former case (decision 0002).
    ///
    /// A failed counts follow-up does *not* populate this — it's logged
    /// and dropped, with the profile staying rendered.
    private(set) var error: Error?

    // MARK: - Init

    init(social: SocialServicing) {
        self.social = social
    }

    // MARK: - Intents

    /// Loads the profile for the supplied username. Whitespace-trims the
    /// input and bails out on an empty handle so a stray submit doesn't
    /// fire a doomed request. Resets prior state on every call.
    ///
    /// On success, chains a `counts(of: profile.id)` follow-up so the
    /// view can render follower / following totals when available.
    /// Counts failure is logged and dropped — the profile header is the
    /// load-bearing data and stays rendered.
    func loadProfile(username: String) async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        loadedUsername = trimmed
        profile = nil
        counts = nil
        error = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let resolved = try await social.profile(username: trimmed)
            profile = resolved
            // Counts follow-up: keyed by userId, which we now have. A
            // failure here is non-fatal — we log it and leave `counts`
            // nil so the view simply omits the count row.
            do {
                counts = try await social.counts(of: resolved.id)
            } catch {
                // Soft error path. Intentionally no rethrow, no
                // assignment to `self.error` (the profile must keep
                // rendering). Future work: pipe through a real logger.
                #if DEBUG
                print("ProfileViewModel: counts follow-up failed for \(resolved.id): \(error)")
                #endif
            }
        } catch {
            self.error = error
        }
    }

    /// Re-runs `loadProfile` for the currently loaded username. Bound to
    /// the "Try again" button on the error state. No-op when no username
    /// is loaded yet.
    func refresh() async {
        guard let loadedUsername else { return }
        await loadProfile(username: loadedUsername)
    }

    /// Resets the browser back to the empty prompt state. Used by the
    /// view's "clear" affordance and by tests that want a clean slate.
    func clear() {
        usernameInput = ""
        loadedUsername = nil
        profile = nil
        counts = nil
        error = nil
        isLoading = false
    }
}
