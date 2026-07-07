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

    // MARK: - Write

    /// `POST /api/user/update` — patch profile / preference fields. Returns the
    /// updated account under the same `{ "user": { ... } }` envelope as
    /// `current()`.
    public static func update(_ body: UpdateUserRequest) -> Request<UserResponse> {
        Request(method: .post, path: "/api/user/update", body: .json(body), auth: .bearer)
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
}
