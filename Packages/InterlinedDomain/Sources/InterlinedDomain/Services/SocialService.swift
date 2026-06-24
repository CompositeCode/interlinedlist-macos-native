import Foundation
import InterlinedKit

// MARK: - SocialError

/// Domain-level errors surfaced by `SocialService`.
///
/// Kept separate from `APIError` because these failures originate in the
/// domain layer's stitching/derivation logic, not in the HTTP boundary. Any
/// transport / decode / status failure from the kit propagates as `APIError`
/// unchanged — callers should `catch` both types.
public enum SocialError: Error, Sendable, Equatable {

    /// The username has no public-facing data the M1 fallback can read from.
    ///
    /// Background (decision 0002 — public-profile fallback): the API does not
    /// expose `GET /api/users/[username]`. `SocialService.profile(username:)`
    /// derives identity from the embedded author on the user's public messages
    /// (`GET /api/user/[username]/messages`). When that list is empty there is
    /// no embedded author to project, so the profile cannot be built. This
    /// case will go away in a later milestone once an upstream profile
    /// endpoint exists.
    case profileUnavailable(username: String)
}

extension SocialError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .profileUnavailable(let username):
            return "No public profile data available for @\(username)."
        }
    }
}

// MARK: - SocialServicing

/// The read-only social surface the App layer codes against for the M1
/// profile UI (PLAN.md §1 "Follow system", §6 M1).
///
/// M1 scope is strictly **read-only**: profile reads, follower/following
/// reads, follow-status reads. The follow/unfollow + request-approval write
/// surface lands in M5 (PLAN.md §6 M5) — those methods are deliberately
/// omitted here and gated with `// M5:` markers at the protocol level so the
/// next milestone has a clear extension point.
///
/// ## Kit-endpoint gap (decision 0002)
///
/// The upstream API does not expose `GET /api/users/[username]` (verified by
/// live probe — 404, not in docs). The only cross-user identity source today
/// is the embedded author on a user's public messages. `profile(username:)`
/// is implemented as a reduced-scope read backed by that embedded user, and
/// the richer profile (bio, joinedAt, isPrivate, follower counts) ships in
/// a later milestone once the upstream API exposes a profile endpoint.
public protocol SocialServicing: Sendable {

    /// Loads a public profile by username.
    ///
    /// **M1 reduced scope (decision 0002):** identity (`id`, `username`,
    /// `displayName`, `avatarURL`) is derived from the embedded author on
    /// the user's most recent public message. Bio, joined-at, private-account
    /// flag, follower and following counts are **not available** from this
    /// fallback path and will be `nil` / `false`. The caller is expected to
    /// fetch follower / following counts separately via `counts(of:)` when
    /// the userId is known.
    ///
    /// - Throws:
    ///   - `SocialError.profileUnavailable(username:)` when the user has zero
    ///     public messages — there is no embedded author to project from in
    ///     that case. Removed in a later milestone once a true profile
    ///     endpoint exists.
    ///   - `APIError` (e.g. `.notFound`) propagated from the kit when the
    ///     username does not exist or the request otherwise fails.
    func profile(username: String) async throws -> UserProfile

    /// Loads the relationship status between the signed-in user and `userId`.
    /// Used by the profile UI to render the follow button state without
    /// performing any write.
    func status(of userId: String) async throws -> FollowStatusDTO

    /// Loads follower / following counts for `userId`. Cheap call that powers
    /// the header stats on a profile.
    ///
    /// Returns the domain `FollowCounts` (not the underlying
    /// `InterlinedKit.FollowCountsDTO`) per decision 0003 — App-layer files
    /// must not need `import InterlinedKit` to render counts.
    func counts(of userId: String) async throws -> FollowCounts

    /// Loads the followers list for `userId`. Bare-array shape today (see
    /// `FollowEndpoint.swift` note); the `UsersPage.hasMore` is always
    /// `false` until the kit switches this endpoint to the paginated envelope.
    func followers(of userId: String, limit: Int, offset: Int) async throws -> UsersPage

    /// Loads the following list for `userId`. Same bare-array caveat as
    /// `followers`.
    func following(of userId: String, limit: Int, offset: Int) async throws -> UsersPage

    // MARK: - M5 write surface (PLAN.md §6 M5)

    /// Sends a follow request for `userId`. Returns a typed `FollowAction`
    /// that distinguishes "now following (public account)" from "pending
    /// approval (private account)" so the UI can render the right
    /// confirmation copy without re-fetching.
    ///
    /// The wire response (`FollowActionResponse`) does not reliably carry
    /// this distinction in a switchable form, so the implementation infers
    /// the result by reading the relationship state immediately after the
    /// call. One follow-up round-trip; acceptable for an action that is
    /// already user-initiated.
    func follow(userId: String) async throws -> FollowAction

    /// Reverses a follow on `userId`. No typed outcome — either the call
    /// succeeds (relationship cleared) or it throws.
    func unfollow(userId: String) async throws

    /// Approves a pending follow request from `userId` (the requester).
    /// Used by the M5 requests inbox.
    func approve(userId: String) async throws

    /// Rejects a pending follow request from `userId`.
    func reject(userId: String) async throws

    /// Removes a follower (kicks `userId` off the caller's follower list).
    /// The verb mirrors `Follow.remove` in the kit.
    func removeFollower(userId: String) async throws

    /// Loads the mutual-follow counts for `userId` (PLAN.md §1 "Follow
    /// system / mutuals"). Returns the domain `MutualCounts`, not the
    /// underlying `InterlinedKit.FollowMutualCountsDTO`, per decision 0003.
    func mutual(of userId: String) async throws -> MutualCounts

    /// Loads the pending inbound follow requests inbox. Returns mapped
    /// domain `FollowRequest` values; the wire envelope (`{ requests: [...] }`)
    /// is internal.
    func requests() async throws -> [FollowRequest]
}

// MARK: - SocialService

public final class SocialService: SocialServicing {

    private let api: APIClientProtocol
    private let decoder: JSONDecoder

    public init(
        api: APIClientProtocol,
        decoder: JSONDecoder = JSONCoders.makeDecoder()
    ) {
        self.api = api
        self.decoder = decoder
    }

    // MARK: Profile

    public func profile(username: String) async throws -> UserProfile {
        // Decision 0002: no `GET /api/users/[username]` endpoint exists. The
        // public-messages endpoint embeds the author user object on every
        // `MessageDTO`, which is the only cross-user identity source today.
        // Pull a single message (limit 1, offset 0) and project from the
        // embedded user — we deliberately do not fan out into a full feed.
        let request = Messages.userMessages(username: username, limit: 1, offset: 0)
        let (data, _) = try await api.sendRaw(request)
        let key = request.paginationKey ?? "messages"
        let paginated = try PaginatedDecoder.decode(
            MessageDTO.self,
            collectionKey: key,
            from: data,
            decoder: decoder
        )
        guard let first = paginated.items.first else {
            // Empty path: no message means no embedded author to derive from.
            // Documented M1 limitation — see `SocialError.profileUnavailable`.
            throw SocialError.profileUnavailable(username: username)
        }
        return UserProfile(fromEmbeddedAuthorOf: first)
    }

    // MARK: Relationship reads

    public func status(of userId: String) async throws -> FollowStatusDTO {
        try await api.send(Follow.status(userId: userId))
    }

    public func counts(of userId: String) async throws -> FollowCounts {
        let dto = try await api.send(Follow.counts(userId: userId))
        return FollowCounts(from: dto)
    }

    // MARK: Follower / following lists

    public func followers(
        of userId: String,
        limit: Int,
        offset: Int
    ) async throws -> UsersPage {
        let request = Follow.followers(userId: userId, limit: limit, offset: offset)
        return try await fetchUsersPage(request: request)
    }

    public func following(
        of userId: String,
        limit: Int,
        offset: Int
    ) async throws -> UsersPage {
        let request = Follow.following(userId: userId, limit: limit, offset: offset)
        return try await fetchUsersPage(request: request)
    }

    // MARK: - M5 write surface (PLAN.md §6 M5)

    public func follow(userId: String) async throws -> FollowAction {
        _ = try await api.send(Follow.follow(userId: userId))
        // The action endpoint returns a small `{ success?, message? }`
        // envelope that is not reliably switchable across deployments. To
        // distinguish "now following" from "request pending", re-read the
        // relationship state and project from the typed flags.
        //
        // This is one extra round-trip per follow tap; acceptable because
        // (a) the action is user-initiated and not on a hot path, and
        // (b) the App layer also needs the relationship state to re-render
        // the follow button, so the cost is shared.
        let statusDTO = try await api.send(Follow.status(userId: userId))
        let relationship = FollowRelationship(from: statusDTO)
        if relationship.isFollowing { return .approved }
        if relationship.hasPendingRequest { return .pending }
        // Defensive fallback: the server accepted the action but the
        // relationship state lags. Treat as pending — the M5 UI shows
        // "Requested" until the next refresh, which is a safe over-cautious
        // default (and survives a slow eventual-consistency window).
        return .pending
    }

    public func unfollow(userId: String) async throws {
        _ = try await api.send(Follow.unfollow(userId: userId))
    }

    public func approve(userId: String) async throws {
        _ = try await api.send(Follow.approve(userId: userId))
    }

    public func reject(userId: String) async throws {
        _ = try await api.send(Follow.reject(userId: userId))
    }

    public func removeFollower(userId: String) async throws {
        _ = try await api.send(Follow.remove(userId: userId))
    }

    public func mutual(of userId: String) async throws -> MutualCounts {
        let dto = try await api.send(Follow.mutual(userId: userId))
        return MutualCounts(from: dto)
    }

    public func requests() async throws -> [FollowRequest] {
        let envelope = try await api.send(Follow.requests())
        return envelope.requests.map(FollowRequest.init(from:))
    }

    // MARK: - Paginated consumption

    /// Mirrors `MessagesService.fetchTimelinePage`: `Paginated<T>` is not
    /// `Decodable` directly (its collection key is runtime-known via
    /// `Request.paginationKey`), so we read raw bytes and decode with
    /// `PaginatedDecoder` against the builder's own key.
    private func fetchUsersPage(
        request: Request<Paginated<FollowUserDTO>>
    ) async throws -> UsersPage {
        let (data, _) = try await api.sendRaw(request)
        guard let key = request.paginationKey else {
            throw APIError.decoding(
                type: "Paginated<FollowUserDTO>",
                message: "Follow paginated request missing paginationKey"
            )
        }
        let paginated = try PaginatedDecoder.decode(
            FollowUserDTO.self,
            collectionKey: key,
            from: data,
            decoder: decoder
        )
        return UsersPage(from: paginated)
    }
}
