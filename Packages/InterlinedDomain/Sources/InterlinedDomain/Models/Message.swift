import Foundation

/// A single timeline message (post), as the UI consumes it (PLAN.md §1, §3).
///
/// This is the domain projection of `MessageDTO`: optional/nullable wire
/// fields are resolved into sensible non-optional defaults where the UI always
/// needs a value (`tags` defaults to `[]`), the `publiclyVisible` boolean
/// becomes a `Visibility`, and the recursively-nested repost target is carried
/// as an indirect `repost`. No `MessageDTO` ever escapes this package.
public struct Message: Sendable, Equatable, Identifiable {
    public let id: String
    /// The author identity for the card / thread row.
    public let author: UserSummary
    /// The message body. Markdown source is authored inline here; the renderer
    /// in the App layer turns it into attributed text.
    public let text: String
    public let createdAt: Date
    public let updatedAt: Date
    public let tags: [String]
    public let visibility: Visibility

    /// "I Dig!" reaction count and whether the signed-in user has dug it.
    public let digCount: Int
    public let didDig: Bool

    /// Repost ("push") count.
    public let repostCount: Int

    /// Number of direct replies, when the payload carries it. `nil` when the
    /// message endpoint did not include a reply count (the list endpoint does
    /// not; the replies endpoint reports its own `total`). Kept optional rather
    /// than defaulted to `0` so the UI can distinguish "no replies" from
    /// "unknown".
    public let replyCount: Int?

    /// The id of the parent message when this is a reply.
    public let parentID: String?

    /// The original message this post reposted, if any. `indirect` because a
    /// `Message` can contain another `Message`.
    public let repost: Repost?

    /// When set, the message is scheduled for future publication at this time.
    public let scheduledAt: Date?

    /// Per-platform cross-post outcomes attached to a published message.
    /// Empty when the message was not cross-posted or when the server did not
    /// return cross-post data for this response.
    ///
    /// NOTE: this is a **write-time** projection — it maps from the create /
    /// update response's sibling `crossPosts` array (status + error, used by the
    /// post-publish `CrossPostResultsSheet`). A message read back from the
    /// timeline does not carry it; use `crossPostLocations` for the persisted
    /// "where did this land" links shown on every row.
    public let crossPostResults: [CrossPostResult]

    /// The persisted places a published message was cross-posted to, projected
    /// from the message's own `crossPostUrls` (e.g. the X/Bluesky/Mastodon
    /// permalinks). Unlike `crossPostResults`, these travel with the message on
    /// **reads**, so the timeline / detail rows can link out to each copy.
    /// Empty when the message was not cross-posted.
    ///
    /// SCOPE DECISION (mirrors `linkPreviews`): cross-post locations are treated
    /// as a fetch-time / UI concern and are **not** persisted in SwiftData
    /// (`MessageRecord`). They are re-derived from the DTO on every load,
    /// refreshing naturally on the next fetch. This deliberately avoids a
    /// SwiftData schema migration; the trade-off is that the links are absent
    /// when a row is rendered purely from the local cache before a refresh.
    public let crossPostLocations: [CrossPostLocation]

    /// Server-rendered rich link previews for URLs found in the body
    /// (feature-gaps §1.5). Empty when the message contains no links or the
    /// server did not resolve any preview metadata for this response.
    ///
    /// SCOPE DECISION (feature-gaps §1.5): link previews are treated as a
    /// fetch-time / UI concern and are **not** persisted in SwiftData
    /// (`MessageRecord`). They are re-derived from the DTO on every load,
    /// refreshing naturally on the next fetch. This deliberately avoids a
    /// SwiftData schema migration; the trade-off is that previews are absent
    /// when a row is rendered purely from the local cache before a refresh.
    public let linkPreviews: [LinkPreview]

    /// The cross-post destinations a **queued scheduled post** will fan out to
    /// when it fires (GitHub #55). `nil` when the server sent no
    /// `scheduledCrossPostConfig` for this message — which is the normal case
    /// for anything already published.
    ///
    /// SCOPE DECISION (mirrors `linkPreviews` and `crossPostLocations`): the
    /// destinations are a fetch-time projection and are **not** persisted in
    /// SwiftData (`MessageRecord`). They are re-derived from the DTO on every
    /// load, so a row painted purely from the on-disk cache before the first
    /// revalidation shows no destination chips; they appear as soon as the
    /// background refresh lands. This deliberately avoids a schema migration.
    public let scheduledDestinations: ScheduledDestinations?

    public init(
        id: String,
        author: UserSummary,
        text: String,
        createdAt: Date,
        updatedAt: Date,
        tags: [String] = [],
        visibility: Visibility,
        digCount: Int,
        didDig: Bool,
        repostCount: Int,
        replyCount: Int? = nil,
        parentID: String? = nil,
        repost: Repost? = nil,
        scheduledAt: Date? = nil,
        crossPostResults: [CrossPostResult] = [],
        crossPostLocations: [CrossPostLocation] = [],
        linkPreviews: [LinkPreview] = [],
        scheduledDestinations: ScheduledDestinations? = nil
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.visibility = visibility
        self.digCount = digCount
        self.didDig = didDig
        self.repostCount = repostCount
        self.replyCount = replyCount
        self.parentID = parentID
        self.repost = repost
        self.scheduledAt = scheduledAt
        self.crossPostResults = crossPostResults
        self.crossPostLocations = crossPostLocations
        self.linkPreviews = linkPreviews
        self.scheduledDestinations = scheduledDestinations
    }
}

/// Indirection box for a reposted message. A value type cannot contain itself
/// by value, so the nested original message is held behind `indirect`.
public indirect enum Repost: Sendable, Equatable {
    case message(Message)

    /// The reposted original.
    public var original: Message {
        switch self {
        case .message(let message): return message
        }
    }
}

// MARK: - ScheduledDestinations (GitHub #55)

/// Which networks a queued scheduled post will publish to when it fires.
///
/// The domain projection of `ScheduledCrossPostConfigDTO`. Where the DTO has
/// four independent optionals (the server omits keys for unselected networks),
/// this resolves them to definite values so the UI never branches on `nil`:
/// an absent key means "not a destination".
///
/// Deliberately *not* the same type as `CrossPostLocation`: that models where a
/// published message actually landed and always carries a live permalink. This
/// models a stated intent for a post that has not gone anywhere yet, so it has
/// no URLs to offer — only names.
public struct ScheduledDestinations: Sendable, Equatable {
    /// The Mastodon provider ids selected. Empty when Mastodon is not a
    /// destination. Kept as ids (not names) because resolving an id to an
    /// instance name needs the account's linked-identity list, which the
    /// message payload does not carry.
    public let mastodonProviderIds: [String]
    public let bluesky: Bool
    public let linkedIn: Bool
    /// X / Twitter. See `ScheduledCrossPostConfigDTO.crossPostToTwitter` — the
    /// server accepts this on create but is not confirmed to echo it back, so in
    /// practice this is usually `false` even for a post scheduled with X
    /// selected. Modelled so the value is carried the moment the server does
    /// send it.
    public let twitter: Bool

    public init(
        mastodonProviderIds: [String] = [],
        bluesky: Bool = false,
        linkedIn: Bool = false,
        twitter: Bool = false
    ) {
        self.mastodonProviderIds = mastodonProviderIds
        self.bluesky = bluesky
        self.linkedIn = linkedIn
        self.twitter = twitter
    }

    /// No network selected — the post publishes to InterlinedList only.
    public static let none = ScheduledDestinations()

    /// True when the post fans out nowhere beyond InterlinedList. The UI shows
    /// "InterlinedList only" rather than an empty chip row, so a reader can tell
    /// "no destinations" apart from "destinations not loaded yet".
    public var isEmpty: Bool {
        mastodonProviderIds.isEmpty && !bluesky && !linkedIn && !twitter
    }

    /// Human-facing destination labels, in the order the web lists them
    /// (Mastodon, Bluesky, LinkedIn, X). Mastodon collapses to a single label
    /// regardless of how many provider ids are selected — matching the web
    /// badge, which draws one Mastodon icon per config, not one per id.
    public var displayNames: [String] {
        var names: [String] = []
        if !mastodonProviderIds.isEmpty { names.append("Mastodon") }
        if bluesky { names.append("Bluesky") }
        if linkedIn { names.append("LinkedIn") }
        if twitter { names.append("X") }
        return names
    }
}

// MARK: - CrossPostResult (NW-2)

/// The per-platform cross-post outcome attached to a published message.
/// Maps from `CrossPostResultDTO`; the wire status string is narrowed to a
/// typed enum with a forward-compatible `.unknown` case.
public struct CrossPostResult: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case ok
        case failed(String?)
        case pending
        case unknown(String)
    }

    public let platform: String
    public let providerId: String?
    public let status: Status
    public let externalURL: URL?

    public init(
        platform: String,
        providerId: String? = nil,
        status: Status,
        externalURL: URL? = nil
    ) {
        self.platform = platform
        self.providerId = providerId
        self.status = status
        self.externalURL = externalURL
    }
}

// MARK: - CrossPostLocation

/// A persisted destination a published message was cross-posted to — the
/// permalink of the copy that landed on an external platform (X, Bluesky,
/// Mastodon, LinkedIn, …).
///
/// Maps from `CrossPostURLDTO` (the message's own `crossPostUrls`). The wire
/// `url` string is coerced to a `URL` during mapping and entries whose `url`
/// will not parse are dropped, so a `CrossPostLocation` always carries a usable
/// link the UI can open. Distinct from `CrossPostResult`, which models the
/// write-time fan-out *outcome* (status / error); this models the durable
/// "where it landed" link shown on every row that reads the message back.
public struct CrossPostLocation: Sendable, Equatable, Identifiable {
    /// The permalink to the cross-posted copy. Doubles as the stable identity
    /// for `ForEach`.
    public let url: URL
    /// The platform slug the server attached (e.g. "twitter", "bluesky",
    /// "mastodon"). Kept raw so the client stays forward-compatible; see
    /// `displayName` for the human-facing label.
    public let platform: String
    /// The specific instance/account name when the server supplied one (e.g. a
    /// Mastodon instance). Preferred over the platform label in the UI.
    public let instanceName: String?

    public var id: URL { url }

    public init(url: URL, platform: String, instanceName: String? = nil) {
        self.url = url
        self.platform = platform
        self.instanceName = instanceName
    }

    /// Human-facing label for the destination chip. Prefers a specific instance
    /// name when the server supplied one, otherwise a friendly name for the
    /// platforms the client recognises, falling back to the capitalized raw
    /// slug so an unknown-but-new platform still reads sensibly.
    public var displayName: String {
        if let instanceName = instanceName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !instanceName.isEmpty {
            return instanceName
        }
        switch platform.lowercased() {
        case "twitter", "x": return "X"
        case "bluesky":      return "Bluesky"
        case "mastodon":     return "Mastodon"
        case "linkedin":     return "LinkedIn"
        case "threads":      return "Threads"
        default:             return platform.capitalized
        }
    }
}

// MARK: - LinkPreview (feature-gaps §1.5)

/// A server-rendered rich link preview attached to a message.
///
/// Maps from `LinkPreviewDTO`. The wire `url` string is coerced to a `URL`
/// during mapping and entries whose `url` will not parse are dropped, so a
/// `LinkPreview` always carries a usable `url`. The remaining fields mirror the
/// server's Open Graph resolution and stay optional because the server may not
/// have finished (or succeeded at) fetching them.
public struct LinkPreview: Sendable, Equatable, Identifiable {
    /// The resolved link. Doubles as the stable identity for `ForEach`.
    public let url: URL
    /// Source platform label the server attached (e.g. "youtube", "github"),
    /// when it recognised one.
    public let platform: String?
    /// The server's fetch-state string for this preview.
    ///
    /// Vocabulary **confirmed live 2026-09-07** (G21 probe, closing the P3-F
    /// "value set the client guessed" question): `"success"` when the fetch
    /// resolved, `"failed"` when the server could not reach the URL. Kept as
    /// the raw string so an unrecognised future value loses no information —
    /// see `isFetchStatusReady` and `didFetchFail`.
    public let fetchStatus: String?
    public let title: String?
    public let description: String?
    public let imageURL: URL?

    public var id: URL { url }

    public init(
        url: URL,
        platform: String? = nil,
        fetchStatus: String? = nil,
        title: String? = nil,
        description: String? = nil,
        imageURL: URL? = nil
    ) {
        self.url = url
        self.platform = platform
        self.fetchStatus = fetchStatus
        self.title = title
        self.description = description
        self.imageURL = imageURL
    }

    /// Whether `fetchStatus` names a state the client recognises as a completed,
    /// successful fetch.
    ///
    /// The live server sends `"success"` (confirmed 2026-09-07). The remaining
    /// tokens are kept as forward-compatible synonyms: matching a superset costs
    /// nothing and protects against a server-side rename. Deliberately **not**
    /// the sole gate on rendering — `isRenderable` also passes on a title or
    /// image — so an unknown-but-successful status never hides a complete card.
    public var isFetchStatusReady: Bool {
        guard let status = fetchStatus?.lowercased() else { return false }
        return ["ready", "success", "succeeded", "ok", "complete", "completed", "fetched"].contains(status)
    }

    /// Whether this preview carries enough resolved metadata to be worth
    /// rendering as a card. True when the server reports a ready fetch status
    /// OR when a human-meaningful field (title or image) is present. A bare URL
    /// with no resolved metadata returns `false` — the UI degrades to nothing
    /// (or a minimal chip) rather than an empty card.
    public var isRenderable: Bool {
        // A ready status alone is NOT enough. Before G21 it was, and because the
        // DTO decoded the server's nested metadata to all-nil, every link on the
        // timeline rendered as a bordered card containing nothing but its host.
        // Require something a human can actually read.
        hasDisplayableContent
    }

    /// Whether the preview carries a field worth putting on screen — a
    /// non-blank title, a description, or an image. This is the real gate:
    /// a preview with a ready status but no resolved fields renders nothing.
    public var hasDisplayableContent: Bool {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return imageURL != nil
    }

    /// Whether the server tried to resolve this link and could not. Drives the
    /// "Retry link previews" affordance, which calls
    /// `POST /api/messages/{id}/metadata` to re-fetch.
    public var didFetchFail: Bool {
        guard let status = fetchStatus?.lowercased() else { return false }
        return ["failed", "failure", "error"].contains(status)
    }

    /// Whether `imageURL` must be loaded through `GET /api/images/proxy` rather
    /// than fetched directly.
    ///
    /// The proxy is **not** a general-purpose image fetcher: the live route
    /// answers `403 {"error":"Only Instagram image URLs are allowed"}` for any
    /// other host (verified 2026-09-07). It exists because Instagram's CDN
    /// blocks hotlinking, so route Instagram thumbnails through it and load
    /// everything else directly — sending a non-Instagram URL there would turn
    /// a working thumbnail into a 403.
    public var needsImageProxy: Bool {
        guard let host = imageURL?.host?.lowercased() else { return false }
        return host == "cdninstagram.com"
            || host.hasSuffix(".cdninstagram.com")
            || host == "fbcdn.net"
            || host.hasSuffix(".fbcdn.net")
    }

    /// The host component shown as the card subtitle (e.g. "github.com"),
    /// stripped of a leading `www.`. Falls back to the full URL string when the
    /// URL has no host.
    public var displayHost: String {
        guard let host = url.host else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// One page of a timeline read: the messages plus the cursor needed to ask for
/// the next page. Maps the kit's `PaginationInfo` envelope into the two values
/// the UI's infinite scroll actually needs.
public struct TimelinePage: Sendable, Equatable {
    public let messages: [Message]
    /// Whether the server reports more messages beyond this page.
    public let hasMore: Bool
    /// The `offset` to pass for the next page. `nil` when `hasMore` is false.
    public let nextOffset: Int?

    public init(messages: [Message], hasMore: Bool, nextOffset: Int?) {
        self.messages = messages
        self.hasMore = hasMore
        self.nextOffset = nextOffset
    }

    /// An empty page with no further results — the boundary value used when a
    /// scope has no messages.
    public static let empty = TimelinePage(messages: [], hasMore: false, nextOffset: nil)
}
