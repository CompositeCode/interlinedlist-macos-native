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

    /// `POST /api/organizations`
    public static func create(_ body: CreateOrganizationRequest) -> Request<OrganizationDTO> {
        Request(method: .post, path: "/api/organizations", body: .json(body), auth: .bearer)
    }

    /// `GET /api/organizations/[id]`
    public static func get(id: String) -> Request<OrganizationDTO> {
        Request(method: .get, path: "/api/organizations/\(id)", auth: .bearer)
    }

    /// `PATCH /api/organizations/[id]`
    public static func update(id: String, _ body: UpdateOrganizationRequest) -> Request<OrganizationDTO> {
        Request(method: .patch, path: "/api/organizations/\(id)", body: .json(body), auth: .bearer)
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
            paginationKey: "data"
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
