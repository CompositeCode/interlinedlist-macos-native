// ProfileStatTilesView
//
// The five stat tiles the web profile shows — Followers, Following, Posts,
// Documents, Lists (GitHub #44 / G32). macOS showed followers and following in
// the header and nothing else.
//
// Four of the five come straight off `GET /api/users/{username}`, which has
// always returned them:
//
//     {"followerCount":1,"followingCount":1,
//      "publicMessageCount":31,"publicListCount":0}
//
// `publicMessageCount` and `publicListCount` were decoded by the kit and dropped
// at the domain boundary, so the information was already on the wire and simply
// not carried. The fifth, Documents, has no count on that payload — it is
// reported by the documents column, which fetches the documents anyway.
//
// A tile whose count is unknown is **omitted**, not rendered as zero. "0 posts"
// and "we could not find out how many posts" look identical and mean opposite
// things, and a profile that claims zero when the count call merely failed is
// worse than one that shows four tiles.
//
// Pure SwiftUI; no AppKit. Decision 0003: consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct ProfileStatTilesView: View {

    let profile: UserProfile

    /// The follow-counts follow-up, when it landed. Preferred over the
    /// profile payload's own pair because it is the fresher read — the same
    /// precedence the header already applies.
    let counts: FollowCounts?

    /// The public-document count, from the documents column. `nil` until that
    /// column has loaded, which is why the tile can appear a moment after the
    /// other four.
    let documentCount: Int?

    private struct Tile: Identifiable {
        let id: String
        let label: String
        let value: Int
    }

    private var tiles: [Tile] {
        var result: [Tile] = []
        if let followers = counts?.followers ?? profile.followerCount {
            result.append(Tile(id: "followers", label: "Followers", value: followers))
        }
        if let following = counts?.following ?? profile.followingCount {
            result.append(Tile(id: "following", label: "Following", value: following))
        }
        if let posts = profile.publicMessageCount {
            result.append(Tile(id: "posts", label: "Posts", value: posts))
        }
        if let documentCount {
            result.append(Tile(id: "documents", label: "Documents", value: documentCount))
        }
        if let lists = profile.publicListCount {
            result.append(Tile(id: "lists", label: "Lists", value: lists))
        }
        return result
    }

    var body: some View {
        if !tiles.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                ForEach(tiles) { tile in
                    VStack(spacing: 2) {
                        Text(tile.value.formatted())
                            .font(.ilTitle(18))
                            .monospacedDigit()
                        Text(tile.label)
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(ILColor.surface2, in: RoundedRectangle(cornerRadius: ILMetric.radiusMd))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(tile.value) \(tile.label)")
                }
            }
        }
    }
}
