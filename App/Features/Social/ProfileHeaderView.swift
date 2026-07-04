// ProfileHeaderView
//
// Read-only public profile header (PLAN.md §1 "Profile", §6 M1). Pure
// presentation: it takes a `UserProfile` plus an optional `FollowCounts`
// and renders avatar, display name, handle, and the conditional fields.
//
// Per `docs/decisions/0002-public-profile-fallback.md`, the M1 fallback
// populates only `{ id, username, displayName, avatarURL }` on the
// `UserProfile`. Bio, joinedAt, and follower / following counts are nil
// or zero. This view renders *nothing* (not "0", not "—" in fields, not
// "Joined") when those values are absent — surfacing zero placeholders
// would be a UX bug per the decision.
//
// `isPrivate` on `UserProfile` is a non-optional `Bool` (defaults to
// `false`), so we treat the M1 fallback's `false` as "don't show the
// private badge" — the badge is only ever rendered when the value
// transitions to `true`, which won't happen until the upstream profile
// endpoint lands and the decision is revived.
//
// Per decision 0003 (App-layer Kit-import policy), this view consumes the
// domain `FollowCounts` and does not `import InterlinedKit`.

import SwiftUI
import InterlinedDomain

struct ProfileHeaderView: View {

    let profile: UserProfile
    /// Optional follow-counts follow-up. `nil` while the call is in
    /// flight or after it failed (the failure is soft — see
    /// `ProfileViewModel.loadProfile`).
    let counts: FollowCounts?
    /// Mutual-follow counts for the profile (PLAN.md §1 "Follow system
    /// / mutuals", §6 M5). `nil` while the call is in flight or after
    /// it failed.
    let mutuals: MutualCounts?
    /// Drives the M5 follow button. `nil` for the M1 read-only paths
    /// that don't need the button (previews, fallback scaffolding).
    /// When non-nil, the button is rendered inline against the
    /// view model's `relationship` state.
    let followButton: FollowButtonViewModel?

    /// M1 read-only initialiser, kept for previews / older call sites
    /// that don't have the M5 follow-button surface wired yet.
    init(profile: UserProfile, counts: FollowCounts?) {
        self.profile = profile
        self.counts = counts
        self.mutuals = nil
        self.followButton = nil
    }

    /// M5 initialiser exposing the mutual-counts row and the follow
    /// button.
    init(
        profile: UserProfile,
        counts: FollowCounts?,
        mutuals: MutualCounts?,
        followButton: FollowButtonViewModel?
    ) {
        self.profile = profile
        self.counts = counts
        self.mutuals = mutuals
        self.followButton = followButton
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(profile.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        if profile.isPrivate {
                            // Won't render in M1 (the fallback never sets
                            // this to true). Wired now so the view is
                            // ready when the upstream endpoint lands and
                            // decision 0002 is revived.
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Private account")
                        }
                    }
                    Text("@\(profile.username)")
                        .font(.ilBody(14))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                if let followButton {
                    FollowButton(viewModel: followButton)
                }
            }

            // Bio: only render when non-nil and non-empty. Per decision
            // 0002, this branch never fires in M1 — the fallback omits
            // bio entirely. Wired for forward-compatibility.
            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.ilBody())
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Counts: only render when the follow-up call succeeded.
            // Suppress when nil so the user doesn't see "0 followers"
            // for a profile whose count we never fetched.
            if let counts {
                countsRow(counts: counts)
            }

            // Mutuals row: rendered only when the mutual call succeeded
            // AND at least one mutual exists. A `0 / 0` mutual band
            // would be visual clutter — the user is reading a profile,
            // not auditing zeros.
            if let mutuals, mutuals.mutualFollowers + mutuals.mutualFollowing > 0 {
                mutualsRow(mutuals: mutuals)
            }

            // JoinedAt: only render when non-nil. Per decision 0002, this
            // branch never fires in M1. Wired for forward-compatibility.
            if let joinedAt = profile.joinedAt {
                Label(
                    "Joined \(joinedAt.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "calendar"
                )
                .font(.ilMono(11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Profile for \(profile.displayName), @\(profile.username)")
    }

    // MARK: - Subviews

    @ViewBuilder
    private var avatar: some View {
        // `AsyncImage` covers the broken / missing URL case with the
        // `placeholder` closure — anything other than a successful image
        // load (in-flight, transport error, decode error, nil URL handled
        // by the outer `if let`) renders the SF Symbol fallback. The
        // visible behavior for a broken avatar URL is identical to the
        // "no avatar URL set" state, which is the right call here:
        // surfacing a load failure to the user gives them no actionable
        // information about a public profile they're browsing.
        Group {
            if let url = profile.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
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
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var avatarFallback: some View {
        ZStack {
            ILColor.primary.opacity(0.15)
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.accentColor)
                .padding(8)
        }
    }

    @ViewBuilder
    private func countsRow(counts: FollowCounts) -> some View {
        HStack(spacing: 24) {
            countPill(
                value: counts.followers,
                singular: "follower",
                plural: "followers"
            )
            countPill(
                value: counts.following,
                singular: "following",
                plural: "following"
            )
        }
        .font(.ilBody(14))
    }

    @ViewBuilder
    private func mutualsRow(mutuals: MutualCounts) -> some View {
        // PLAN.md §1 "Follow system / mutuals": "X mutual followers / Y
        // you both follow". Rendered inline below the counts row so the
        // header reads top-down: identity → counts → mutuals.
        HStack(spacing: 16) {
            if mutuals.mutualFollowers > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.secondary)
                    Text("\(mutuals.mutualFollowers) mutual \(mutuals.mutualFollowers == 1 ? "follower" : "followers")")
                        .foregroundStyle(.secondary)
                }
            }
            if mutuals.mutualFollowing > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(.secondary)
                    Text("\(mutuals.mutualFollowing) you both follow")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.ilMono(11))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(mutuals.mutualFollowers) mutual followers, \(mutuals.mutualFollowing) you both follow"
        )
    }

    @ViewBuilder
    private func countPill(value: Int, singular: String, plural: String) -> some View {
        // The counts call yields a concrete `Int`, not a nil placeholder,
        // so rendering "0 followers" here is real data — the user has
        // zero followers, not an unknown follower count. That's a meaningful
        // distinction the API can express; we honor it.
        let label = value == 1 ? singular : plural
        HStack(spacing: 4) {
            Text("\(value)")
                .fontWeight(.semibold)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}
