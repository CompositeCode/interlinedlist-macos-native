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
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }

            // Bio: only render when non-nil and non-empty. Per decision
            // 0002, this branch never fires in M1 — the fallback omits
            // bio entirely. Wired for forward-compatibility.
            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Counts: only render when the follow-up call succeeded.
            // Suppress when nil so the user doesn't see "0 followers"
            // for a profile whose count we never fetched.
            if let counts {
                countsRow(counts: counts)
            }

            // JoinedAt: only render when non-nil. Per decision 0002, this
            // branch never fires in M1. Wired for forward-compatibility.
            if let joinedAt = profile.joinedAt {
                Label(
                    "Joined \(joinedAt.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "calendar"
                )
                .font(.footnote)
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
            Color.accentColor.opacity(0.15)
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
        .font(.callout)
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
