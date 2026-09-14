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
/// surface). The old note here also listed `/api/user/organizations` as
/// session-only; that was wrong and is corrected in `UserEndpoint.swift` —
/// a raw `Authorization: Bearer` request to it returns HTTP 200 (verified
/// 2026-09-09), and `GET /api/openapi.json` marks it `x-auth-type: sync-token`.
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

    /// `DELETE /api/organizations/[id]` — delete an organization (owner only).
    ///
    /// VERIFIED live 2026-09-09 (read-only): `OPTIONS` reports
    /// `Allow: DELETE, GET, HEAD, OPTIONS, PUT`, and `GET /api/openapi.json`
    /// declares `deleteOrganizationsById` with `x-auth-type: sync-token`. The
    /// verb was confirmed **without** issuing a real delete — the test account
    /// is shared, and deleting an org is not reversible.
    ///
    /// The response body is not modelled by the spec, so callers use
    /// `sendVoid` and ignore it; only the status matters.
    public static func delete(id: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/organizations/\(id)", auth: .bearer)
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

    // MARK: - Organization LinkedIn (work-consolidation.md G25)
    //
    // The shared-credential half of LinkedIn. All four verbs verified live
    // 2026-09-09 by `OPTIONS`, and cross-checked against `GET
    // /api/openapi.json`, which marks each `x-auth-type: sync-token`.
    //
    // Note the asymmetry: `status` is the only readable route. `GET` on
    // `sync-pages` and on `assignments` — both documented on
    // `/help/api/organizations` — answer **405** live and are absent from the
    // OpenAPI document, so the discovered pages and current assignments have
    // to come back through `status`. See `OrgLinkedInDTO.swift`.

    /// `GET /api/organizations/[id]/linkedin/status` — the org's shared
    /// LinkedIn credential status, the caller's role, and (when connected) the
    /// discovered company pages.
    ///
    /// Observed live: `{"credential":null,"role":"member"}`.
    public static func linkedInStatus(id: String) -> Request<OrgLinkedInStatusResponse> {
        Request(method: .get, path: "/api/organizations/\(id)/linkedin/status", auth: .bearer)
    }

    /// `POST /api/organizations/[id]/linkedin/sync-pages` — re-discover the
    /// org's LinkedIn company pages.
    ///
    /// Takes no request body (the OpenAPI operation declares none). The 201
    /// response body is unmodelled and was never observed, so this is typed
    /// `EmptyResponse` and callers `sendVoid` it, then re-read `status` for the
    /// refreshed page list. That keeps a sync from failing at the decoder on a
    /// shape the client has not seen.
    public static func syncLinkedInPages(id: String) -> Request<EmptyResponse> {
        Request(method: .post, path: "/api/organizations/\(id)/linkedin/sync-pages", auth: .bearer)
    }

    /// `PUT /api/organizations/[id]/linkedin/assignments` — assign one member
    /// to one company page (or clear their assignment with a nil `pageId`).
    ///
    /// One assignment per call, per the OpenAPI body schema (`userId` +
    /// `pageId`). See `UpdateOrgLinkedInAssignmentRequest` for why this differs
    /// from the help page's "assignment map".
    public static func assignLinkedInPage(
        id: String,
        _ body: UpdateOrgLinkedInAssignmentRequest
    ) -> Request<EmptyResponse> {
        Request(
            method: .put,
            path: "/api/organizations/\(id)/linkedin/assignments",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `DELETE /api/organizations/[id]/linkedin/credential` — disconnect the
    /// org's shared LinkedIn credential.
    ///
    /// Destructive for every assigned member: the server clears assignments,
    /// and each assigned member silently falls back to their personal LinkedIn
    /// identity. The UI must say so before calling this.
    public static func disconnectLinkedIn(id: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/organizations/\(id)/linkedin/credential", auth: .bearer)
    }
}

