import Foundation
import InterlinedKit

// MARK: - ListOwner

/// The person who owns a list someone else can see — the `user` object the
/// `/api/lists/watching` rows embed (work-consolidation.md G23).
///
/// Deliberately thinner than `UserSummary`: the watching route returns only
/// `id` / `username` / `displayName`, and modelling more would invite the UI
/// to render fields that are always `nil`.
public struct ListOwner: Sendable, Equatable, Hashable, Identifiable {

    public let id: String
    public let username: String?
    public let displayName: String?
    public let avatarURL: URL?

    /// Best available human label: display name, then `@username`, then a
    /// neutral fallback so a row never renders blank.
    public var displayLabel: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let username, !username.isEmpty { return username }
        return "Someone"
    }

    public init(
        id: String,
        username: String? = nil,
        displayName: String? = nil,
        avatarURL: URL? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}

// MARK: - WatchedList

/// A list **someone else owns** that the signed-in account has been granted
/// access to — the "shared with me" projection behind `GET /api/lists/watching`
/// (work-consolidation.md G23 / issue #48).
///
/// Composition over a second list type: the list itself is the existing
/// `OwnedList` (the wire rows are a strict superset of the owned-list shape),
/// and this type adds only what is genuinely new — who owns it, what the
/// caller may do with it, and the parent's title.
public struct WatchedList: Sendable, Equatable, Hashable, Identifiable {

    /// The list itself. Same type the owned-list sidebar renders, so a watched
    /// list drops straight into the existing rows/detail views.
    public let list: OwnedList

    /// The list's owner. `nil` when the route omitted the `user` object.
    public let owner: ListOwner?

    /// The **caller's** role on this list — what *you* may do, not what the
    /// owner may do.
    public let role: ShareRole

    /// The parent list's title, when the row carried a `parent` projection.
    ///
    /// - Important: a parent projection does **not** imply access to the
    ///   parent. A list can be shared without its parent being shared, so this
    ///   is a breadcrumb label only — never navigate off it.
    public let parentTitle: String?

    public var id: String { list.id }

    /// Convenience passthrough so sidebar rows can read `watched.title`.
    public var title: String { list.title }

    /// Whether the caller may change this list's rows. Read-only shares
    /// (`watcher`) must not render edit affordances.
    public var canEdit: Bool { role.canEdit }

    public init(
        list: OwnedList,
        owner: ListOwner? = nil,
        role: ShareRole,
        parentTitle: String? = nil
    ) {
        self.list = list
        self.owner = owner
        self.role = role
        self.parentTitle = parentTitle
    }
}

/// One page of watched lists — the same `*Page` shape every paginated read in
/// the domain layer uses (`OwnedListsPage`, `RowsPage`, `TimelinePage`).
public struct WatchedListsPage: Sendable, Equatable {

    public let lists: [WatchedList]
    public let hasMore: Bool
    public let nextOffset: Int?

    public init(lists: [WatchedList], hasMore: Bool, nextOffset: Int?) {
        self.lists = lists
        self.hasMore = hasMore
        self.nextOffset = nextOffset
    }

    /// The empty-page boundary value — used when nobody has shared a list.
    public static let empty = WatchedListsPage(lists: [], hasMore: false, nextOffset: nil)
}

// MARK: - ListContributor

/// One ranked contributor to a list (`GET /api/lists/[id]/contributors`).
///
/// The server ranks by an opaque `score`; the client preserves the server's
/// order rather than re-sorting, so a future change to the ranking formula
/// does not need a client release.
public struct ListContributor: Sendable, Equatable, Hashable, Identifiable {

    public let id: String
    public let username: String?
    public let displayName: String?
    public let avatarURL: URL?
    /// Rows this person added. `0` when the route omits the count.
    public let addedCount: Int
    /// Rows this person edited. `0` when the route omits the count.
    public let editedCount: Int
    /// The server's ranking score. Opaque — displayed, never recomputed.
    public let score: Int

    /// Best available human label, matching `ListOwner.displayLabel`.
    public var displayLabel: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let username, !username.isEmpty { return username }
        return "Contributor"
    }

    public init(
        id: String,
        username: String? = nil,
        displayName: String? = nil,
        avatarURL: URL? = nil,
        addedCount: Int = 0,
        editedCount: Int = 0,
        score: Int = 0
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.addedCount = addedCount
        self.editedCount = editedCount
        self.score = score
    }
}

// MARK: - ResolvedListInvite

/// The landing payload for an email invite (`GET /api/lists/invite/{token}`).
///
/// **The client cannot accept an invite.** `POST /api/lists/invite/{token}` is
/// declared `x-auth-type: session` in the live OpenAPI spec, so a Bearer-only
/// macOS client is locked out of the claim half. This type therefore backs a
/// *landing* experience only — show what the invite grants and hand the accept
/// step to the browser. Accepting is documented as always free, so no
/// entitlement gate belongs anywhere near it.
public struct ResolvedListInvite: Sendable, Equatable {

    /// The role the invite grants.
    public let role: ShareRole

    /// `true` when nobody is signed in — the landing prompts sign-in.
    public let needsAuth: Bool

    /// `true` when the signed-in account's verified email matches the invited
    /// address. Even then the claim must happen in the browser.
    public let canClaim: Bool

    /// `true` when someone is signed in under a *different* email than the one
    /// invited. The invited address is never returned, so this flag is the only
    /// signal the client gets.
    public let wrongAccount: Bool

    /// `true` once the invite has already been claimed.
    public let accepted: Bool

    /// The title of the list the invite grants access to.
    public let resourceTitle: String?

    public init(
        role: ShareRole,
        needsAuth: Bool,
        canClaim: Bool,
        wrongAccount: Bool,
        accepted: Bool,
        resourceTitle: String?
    ) {
        self.role = role
        self.needsAuth = needsAuth
        self.canClaim = canClaim
        self.wrongAccount = wrongAccount
        self.accepted = accepted
        self.resourceTitle = resourceTitle
    }
}

// MARK: - DTO → domain mapping

extension ListOwner {
    public init(from dto: ListUserDTO) {
        self.init(
            id: dto.id,
            username: dto.username,
            displayName: dto.displayName,
            avatarURL: dto.avatar.flatMap(URL.init(string:))
        )
    }
}

extension WatchedList {
    /// Maps one `/api/lists/watching` row.
    ///
    /// An absent or unrecognised `role` collapses to `.watcher` — the least
    /// privileged role — so a taxonomy the client does not know can never
    /// unlock edit affordances.
    public init(from dto: ListDTO) {
        self.init(
            list: OwnedList(from: dto),
            owner: dto.user.map(ListOwner.init(from:)),
            role: dto.role.flatMap(ShareRole.init(rawValue:)) ?? .watcher,
            parentTitle: dto.parent?.title
        )
    }
}

extension WatchedListsPage {
    /// Builds a page from the kit's `Paginated<ListDTO>` envelope.
    public init(from paginated: Paginated<ListDTO>) {
        let info = paginated.pagination
        self.init(
            lists: paginated.items.map(WatchedList.init(from:)),
            hasMore: info.hasMore,
            nextOffset: info.hasMore ? info.offset + info.limit : nil
        )
    }
}

extension ListContributor {
    public init(from dto: ListContributorDTO) {
        self.init(
            id: dto.id,
            username: dto.username,
            displayName: dto.displayName,
            avatarURL: dto.avatar.flatMap(URL.init(string:)),
            addedCount: dto.addedCount ?? 0,
            editedCount: dto.editedCount ?? 0,
            score: dto.score ?? 0
        )
    }
}

extension ResolvedListInvite {
    /// Maps the landing payload. Every flag defaults to the conservative
    /// value: an omitted `canClaim` means "not claimable", an omitted
    /// `accepted` means "still open".
    public init(from dto: ResolvedListInviteDTO) {
        self.init(
            role: dto.role.flatMap(ShareRole.init(rawValue:)) ?? .watcher,
            needsAuth: dto.needsAuth ?? false,
            canClaim: dto.canClaim ?? false,
            wrongAccount: dto.wrongAccount ?? false,
            accepted: dto.accepted ?? false,
            resourceTitle: dto.resourceTitle
        )
    }
}
