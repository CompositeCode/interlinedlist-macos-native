import Foundation

/// Request builders for the **Organizations** API group — org CRUD, member
/// management (with roles), and the users-with-roles listing.
///
/// Follows the `Request.swift` conventions: one `public enum` namespace,
/// factories returning `Request<DTO>`, `Paginated<T>` + `paginationKey`
/// (collection key `"data"`) for list envelopes, explicit `AuthRequirement`,
/// path-only URLs, nil-skipping query items, `RequestBody.json`, and never
/// throwing.
///
/// Auth: all `.bearer` (decision 0001 — Bearer works on the organizations
/// surface; only `/api/user/organizations` and `/api/exports/*` plus
/// `/api/user/identities` are session-only).
public enum Organizations {

    // MARK: - Org CRUD

    /// `GET /api/organizations`
    public static func list(
        isPublic: Bool? = nil,
        userId: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<Paginated<OrganizationDTO>> {
        Request(
            method: .get,
            path: "/api/organizations",
            query: [
                .bool("public", isPublic),
                .string("userId", userId),
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer,
            paginationKey: "data"
        )
    }

    /// `POST /api/organizations` — create an organization.
    ///
    /// VERIFIED live 2026-09-06: answers `{ "message": …, "organization": { … } }`,
    /// so this decodes `OrganizationWriteResponse`. It previously decoded a bare
    /// `OrganizationDTO` and therefore failed on every successful create.
    public static func create(_ body: CreateOrganizationRequest) -> Request<OrganizationWriteResponse> {
        Request(method: .post, path: "/api/organizations", body: .json(body), auth: .bearer)
    }

    /// `GET /api/organizations/[id]` — one organization.
    ///
    /// VERIFIED live 2026-09-06: answers `{ "organization": { … } }`, the same
    /// envelope as the write routes (no `message` key on the read). Was decoding
    /// a bare `OrganizationDTO`, so organization detail never loaded.
    public static func get(id: String) -> Request<OrganizationWriteResponse> {
        Request(method: .get, path: "/api/organizations/\(id)", auth: .bearer)
    }

    /// `PUT /api/organizations/[id]` — rename / re-describe / re-scope an org.
    ///
    /// VERIFIED live 2026-09-06 (work-consolidation.md §1c · V4): the verb is
    /// `PUT`. `OPTIONS` reports `Allow: DELETE, GET, HEAD, OPTIONS, PUT` and the
    /// `PATCH` this shipped with returns **405**. A live `PUT` renamed a probe
    /// organization and returned HTTP 200 with the `OrganizationWriteResponse`
    /// envelope — the response type is corrected here too, since fixing only the
    /// verb would have swapped a 405 for a decode failure.
    public static func update(id: String, _ body: UpdateOrganizationRequest) -> Request<OrganizationWriteResponse> {
        Request(method: .put, path: "/api/organizations/\(id)", body: .json(body), auth: .bearer)
    }

    // MARK: - Members

    /// `GET /api/organizations/[id]/members`
    public static func members(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<Paginated<OrganizationMemberDTO>> {
        Request(
            method: .get,
            path: "/api/organizations/\(id)/members",
            query: [
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer,
            paginationKey: "members"
        )
    }

    /// `POST /api/organizations/[id]/members`
    public static func addMember(
        id: String,
        _ body: AddOrganizationMemberRequest
    ) -> Request<OrganizationMembershipResponse> {
        Request(method: .post, path: "/api/organizations/\(id)/members", body: .json(body), auth: .bearer)
    }

    /// `PUT /api/organizations/[id]/members/[userId]`
    public static func updateMember(
        id: String,
        userId: String,
        _ body: UpdateOrganizationMemberRequest
    ) -> Request<OrganizationMembershipResponse> {
        Request(
            method: .put,
            path: "/api/organizations/\(id)/members/\(userId)",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `DELETE /api/organizations/[id]/members/[userId]`
    public static func removeMember(id: String, userId: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/organizations/\(id)/members/\(userId)", auth: .bearer)
    }

    // MARK: - Users with roles

    /// `GET /api/organizations/[id]/users`
    public static func users(id: String) -> Request<[OrganizationUserDTO]> {
        Request(method: .get, path: "/api/organizations/\(id)/users", auth: .bearer)
    }
}
