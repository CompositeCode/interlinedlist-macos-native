import Foundation

/// Request builders for the **User** (account) endpoint group.
///
/// Auth follows decision 0001: `.bearer` everywhere except the two confirmed
/// session-only reads — `GET /api/user/identities` and
/// `GET /api/user/organizations` — which are `.session`.
public enum User {

    // MARK: - Read

    /// `GET /api/user` — the authenticated account.
    ///
    /// Decodes the `{ "user": { ... } }` envelope. The nested `UserDTO`
    /// carries `customerStatus`, which the future `EntitlementsService` reads
    /// for subscriber gating.
    public static func current() -> Request<UserResponse> {
        Request(method: .get, path: "/api/user", auth: .bearer)
    }

    /// `GET /api/user/identities` — linked OAuth identities.
    /// **Session-only** per decision 0001 (Bearer is rejected here).
    public static func identities() -> Request<IdentitiesResponse> {
        Request(method: .get, path: "/api/user/identities", auth: .session)
    }

    /// `GET /api/user/organizations` — organizations the user belongs to.
    /// **Session-only** per decision 0001 (Bearer is rejected here).
    public static func organizations() -> Request<UserOrganizationsResponse> {
        Request(method: .get, path: "/api/user/organizations", auth: .session)
    }

    /// `GET /api/user/engagement` — lifetime dig/push totals on your own
    /// messages, plus a recent-events feed (work-consolidation.md G27).
    ///
    /// **Session-only, and that is now settled.** The 2026-09-05 pass saw a 401
    /// under Bearer and left it flagged "confirm before building". Re-probed
    /// 2026-09-06: `OPTIONS` reports `Allow: GET, HEAD, OPTIONS`, Bearer still
    /// returns `401 {"error":"Unauthorized","code":"unauthorized"}`, and the
    /// same request over a cookie session returns **HTTP 200** with the totals.
    /// So the route is real and reachable — it just does not accept the bearer
    /// token, hence `auth: .session` (the transport establishes the cookie
    /// lazily, per decision 0001).
    public static func engagement() -> Request<UserEngagementResponse> {
        Request(method: .get, path: "/api/user/engagement", auth: .session)
    }

    // MARK: - Write

    /// `PATCH /api/user/update` — patch profile / preference fields. Returns the
    /// updated account under the same `{ "user": { ... } }` envelope as
    /// `current()` (the live body is `{ "message": "User updated successfully",
    /// "user": { ... } }`; the extra `message` key is ignored).
    ///
    /// VERIFIED live 2026-09-06 (work-consolidation.md §1c · V2): the verb is
    /// `PATCH`. `OPTIONS` reports `Allow: OPTIONS, PATCH` and the `POST` this
    /// shipped with returns **405**, so Settings ▸ Preferences could never save
    /// against production. Confirmed end-to-end with a real `PATCH` on the test
    /// account, which returned HTTP 200 and the envelope above.
    public static func update(_ body: UpdateUserRequest) -> Request<UserResponse> {
        Request(method: .patch, path: "/api/user/update", body: .json(body), auth: .bearer)
    }

    /// `POST /api/user/avatar/upload` — upload avatar image bytes and receive
    /// the hosted URL. Uses `RequestBody.raw`.
    public static func uploadAvatar(_ data: Data, contentType: String) -> Request<MediaUploadResponse> {
        Request(
            method: .post,
            path: "/api/user/avatar/upload",
            body: .raw(data, contentType: contentType),
            auth: .bearer
        )
    }

    /// `POST /api/user/avatar/from-url` — set the avatar from a remote URL.
    public static func avatarFromURL(_ url: String) -> Request<MediaUploadResponse> {
        Request(
            method: .post,
            path: "/api/user/avatar/from-url",
            body: .json(AvatarFromURLRequest(url: url)),
            auth: .bearer
        )
    }

    /// `POST /api/user/change-email/request` — start the email-change flow
    /// (server emails a confirmation link to the new address).
    public static func requestEmailChange(_ body: ChangeEmailRequest) -> Request<MessageResponse> {
        Request(
            method: .post,
            path: "/api/user/change-email/request",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `POST /api/user/delete` — delete the account.
    public static func delete(_ body: DeleteAccountRequest = DeleteAccountRequest()) -> Request<MessageResponse> {
        Request(method: .post, path: "/api/user/delete", body: .json(body), auth: .bearer)
    }

    // MARK: - User search / lookup (NW-1)

    /// `GET /api/users/search?q=query&limit=limit` — prefix search for users.
    public static func search(query: String, limit: Int? = nil) -> Request<UserSearchResponse> {
        Request(
            method: .get,
            path: "/api/users/search",
            query: [
                .string("q", query),
                .int("limit", limit)
            ],
            auth: .bearer
        )
    }

    /// `GET /api/users/lookup?handle=handle` — exact handle lookup; 404 when not found.
    public static func lookup(handle: String) -> Request<UserSearchResultDTO> {
        Request(
            method: .get,
            path: "/api/users/lookup",
            query: [.string("handle", handle)],
            auth: .bearer
        )
    }

    /// `GET /api/users/{username}` — a public user profile by handle
    /// (work-consolidation.md D2). Bearer-authenticated so private/follow-aware
    /// visibility resolves for the signed-in viewer; 404 for unknown handles.
    public static func publicProfile(username: String) -> Request<PublicProfileDTO> {
        Request(method: .get, path: "/api/users/\(username)", auth: .bearer)
    }
}
