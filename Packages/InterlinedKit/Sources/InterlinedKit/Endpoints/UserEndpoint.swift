import Foundation

/// Request builders for the **User** (account) endpoint group.
///
/// Auth follows decision 0001: `.bearer` everywhere except the confirmed
/// session-only reads — `GET /api/user/identities` and
/// `GET /api/user/engagement` — which are `.session`.
///
/// `GET /api/user/organizations` used to be listed here as session-only. It is
/// not; see the builder below for the 2026-09-09 verification.
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
    ///
    /// **Corrected 2026-09-15 (GitHub #47): this route accepts Bearer.** A live
    /// probe with a valid sync-token returns `200` with the full identity list,
    /// so the `.session` annotation was wrong. It was not a hard failure — the
    /// kit has a cookie-session transport that lazily logs in — but it cost an
    /// extra credentialed round-trip on every load of the Identities pane and
    /// authenticated the same request a second way for no reason.
    ///
    /// This is the same class of error as the `send-verification-email`
    /// correction in PR #83, in the opposite direction: an annotation inferred
    /// from one observation rather than from a probe under the transport in
    /// question.
    public static func identities() -> Request<IdentitiesResponse> {
        Request(method: .get, path: "/api/user/identities", auth: .bearer)
    }

    /// `DELETE /api/user/identities` — unlink a provider.
    ///
    /// The provider token is instance-qualified for Mastodon
    /// (`"mastodon:techhub.social"`), because an account can link several
    /// instances and a bare `"mastodon"` would be ambiguous — the server could
    /// disconnect the wrong one. Callers should pass
    /// `LinkedIdentity.providerWireToken`, which is exactly that value.
    public static func unlinkIdentity(provider: String) -> Request<MessageResponse> {
        Request(
            method: .delete,
            path: "/api/user/identities",
            query: [.string("provider", provider)],
            auth: .bearer
        )
    }

    /// `POST /api/user/identities/verify` — re-check a connection is still live.
    ///
    /// The web's Verify action. Same instance-qualified token as unlink.
    public static func verifyIdentity(provider: String) -> Request<VerifyIdentityResponse> {
        Request(
            method: .post,
            path: "/api/user/identities/verify",
            body: .json(VerifyIdentityRequest(provider: provider)),
            auth: .bearer
        )
    }

    /// `GET /api/user/organizations` — organizations the user belongs to, with
    /// the caller's own role, joined-at, and the org's member count.
    ///
    /// **CORRECTED 2026-09-09 — this is a Bearer route, not a session route.**
    /// Decision 0001 recorded it as session-only, and it shipped as
    /// `auth: .session`. A raw `curl` carrying nothing but
    /// `Authorization: Bearer <sync token>` — no cookie jar at all — returns
    /// HTTP 200 with the full membership list, and `GET /api/openapi.json`
    /// marks the operation `x-auth-type: sync-token`. The same spec correctly
    /// reports `x-auth-type: session` for `/api/user/engagement`, which this
    /// repo independently confirmed is session-only, so the field is
    /// trustworthy on both sides.
    ///
    /// `role` narrows the result server-side (e.g. `"owner"`); `nil` returns
    /// every membership.
    public static func organizations(role: String? = nil) -> Request<UserOrganizationsResponse> {
        Request(
            method: .get,
            path: "/api/user/organizations",
            query: [.string("role", role)],
            auth: .bearer
        )
    }

    /// `POST /api/user/organizations` — **join** an organization.
    ///
    /// The join path. There is no `/api/organizations/{id}/join` route (it
    /// 404s); joining is a write against the caller's own membership
    /// collection. Confirmed 2026-09-09 without issuing a write, from the
    /// shipped web client (which posts `{ organizationId }` to this exact
    /// path) and from `GET /api/openapi.json` (`postUserOrganizations`,
    /// one body property `organizationId`, 201 response).
    ///
    /// The 201 body is unmodelled and was not observed, so this is typed
    /// `EmptyResponse` — callers `sendVoid` it and re-read the membership
    /// list rather than risking a decode failure on an unseen shape.
    public static func joinOrganization(organizationId: String) -> Request<EmptyResponse> {
        Request(
            method: .post,
            path: "/api/user/organizations",
            body: .json(JoinOrganizationRequest(organizationId: organizationId)),
            auth: .bearer
        )
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
