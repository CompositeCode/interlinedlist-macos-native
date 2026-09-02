import Foundation

/// Request builders for the **Sharing / Share Links** API group (work-consolidation.md
/// G3) — tokenized view/edit/admin links for lists and documents. Creating a
/// link is subscriber-gated server-side (the domain service checks too);
/// resolving/claiming/revoking are not.
///
/// Paths + shapes verified live 2026-07-31 (authorized create→capture→revoke).
/// Follows the `Request.swift` conventions.
public enum Sharing {

    // MARK: - Lists

    /// `GET /api/lists/{id}/share-links` — active links (owner only).
    public static func listShareLinks(listId: String) -> Request<ShareLinksResponse> {
        Request(method: .get, path: "/api/lists/\(listId)/share-links", auth: .bearer)
    }

    /// `POST /api/lists/{id}/share-links` — create a link (owner + subscriber).
    public static func createListShareLink(listId: String, _ body: CreateShareLinkRequest) -> Request<ShareLinkDTO> {
        Request(method: .post, path: "/api/lists/\(listId)/share-links", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/lists/{id}/share-links/{token}` — revoke a link.
    public static func revokeListShareLink(listId: String, token: String) -> Request<RevokeShareResponse> {
        Request(method: .delete, path: "/api/lists/\(listId)/share-links/\(token)", auth: .bearer)
    }

    /// `GET /api/lists/shared/{token}` — resolve a list share link.
    public static func resolveListShare(token: String) -> Request<ResolvedListShareDTO> {
        Request(method: .get, path: "/api/lists/shared/\(token)", auth: .bearer)
    }

    /// `POST /api/lists/shared/{token}` — claim an edit/admin list link.
    public static func claimListShare(token: String) -> Request<ClaimListShareResponse> {
        Request(method: .post, path: "/api/lists/shared/\(token)", auth: .bearer)
    }

    // MARK: - Documents

    /// `GET /api/documents/{id}/share-links` — active links (owner only).
    public static func documentShareLinks(documentId: String) -> Request<ShareLinksResponse> {
        Request(method: .get, path: "/api/documents/\(documentId)/share-links", auth: .bearer)
    }

    /// `POST /api/documents/{id}/share-links` — create a link (owner + subscriber).
    public static func createDocumentShareLink(documentId: String, _ body: CreateShareLinkRequest) -> Request<ShareLinkDTO> {
        Request(method: .post, path: "/api/documents/\(documentId)/share-links", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/documents/{id}/share-links/{token}` — revoke a link.
    public static func revokeDocumentShareLink(documentId: String, token: String) -> Request<RevokeShareResponse> {
        Request(method: .delete, path: "/api/documents/\(documentId)/share-links/\(token)", auth: .bearer)
    }

    /// `GET /api/documents/shared/{token}` — resolve a document share link.
    public static func resolveDocumentShare(token: String) -> Request<ResolvedDocumentShareDTO> {
        Request(method: .get, path: "/api/documents/shared/\(token)", auth: .bearer)
    }

    /// `POST /api/documents/shared/{token}` — claim an edit/admin document link.
    public static func claimDocumentShare(token: String) -> Request<ClaimDocumentShareResponse> {
        Request(method: .post, path: "/api/documents/shared/\(token)", auth: .bearer)
    }

    // MARK: - Document collaborators (G3 access & permissions)

    /// `GET /api/documents/{id}/collaborators` — people with per-person access.
    public static func documentCollaborators(documentId: String) -> Request<CollaboratorsResponse> {
        Request(method: .get, path: "/api/documents/\(documentId)/collaborators", auth: .bearer)
    }

    /// `POST /api/documents/{id}/collaborators` — grant a user access (owner + subscriber).
    public static func addDocumentCollaborator(documentId: String, _ body: AddCollaboratorRequest) -> Request<AddCollaboratorResponse> {
        Request(method: .post, path: "/api/documents/\(documentId)/collaborators", body: .json(body), auth: .bearer)
    }

    /// `PUT /api/documents/{id}/collaborators/{userId}` — change a collaborator's role.
    public static func setDocumentCollaboratorRole(documentId: String, userId: String, _ body: SetCollaboratorRoleRequest) -> Request<SetRoleResponse> {
        Request(method: .put, path: "/api/documents/\(documentId)/collaborators/\(userId)", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/documents/{id}/collaborators/{userId}` — revoke a collaborator's access.
    public static func removeDocumentCollaborator(documentId: String, userId: String) -> Request<RemoveCollaboratorResponse> {
        Request(method: .delete, path: "/api/documents/\(documentId)/collaborators/\(userId)", auth: .bearer)
    }

    /// `GET /api/documents/{id}/collaborators/users?search=…` — search users to invite.
    /// Sends both `search` (web route) and `q` (iOS client) so whichever the live
    /// route reads is present; the other is ignored server-side. See the ⚠️ note in `SharingDTO`.
    public static func searchDocumentCollaborators(
        documentId: String,
        query: String,
        limit: Int? = nil,
        offset: Int? = nil,
        excludeCollaborators: Bool? = nil
    ) -> Request<CollaboratorCandidatesResponse> {
        Request(
            method: .get,
            path: "/api/documents/\(documentId)/collaborators/users",
            query: [
                .string("search", query),
                .string("q", query),
                .int("limit", limit),
                .int("offset", offset),
                .bool("excludeCollaborators", excludeCollaborators)
            ],
            auth: .bearer
        )
    }

    // MARK: - Document email invites (G3 invite by email)

    /// `GET /api/documents/{id}/invites` — pending + accepted email invites.
    public static func documentInvites(documentId: String) -> Request<ShareInvitesResponse> {
        Request(method: .get, path: "/api/documents/\(documentId)/invites", auth: .bearer)
    }

    /// `POST /api/documents/{id}/invites` — send an email invite (owner + subscriber).
    public static func createDocumentInvite(documentId: String, _ body: CreateInviteRequest) -> Request<CreateInviteResponse> {
        Request(method: .post, path: "/api/documents/\(documentId)/invites", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/documents/{id}/invites/{token}` — revoke a pending invite.
    public static func revokeDocumentInvite(documentId: String, token: String) -> Request<RevokeShareResponse> {
        Request(method: .delete, path: "/api/documents/\(documentId)/invites/\(token)", auth: .bearer)
    }

    // MARK: - List email invites (G3 invite by email — Track 2)

    /// `GET /api/lists/{id}/invites` — pending + accepted email invites.
    public static func listInvites(listId: String) -> Request<ShareInvitesResponse> {
        Request(method: .get, path: "/api/lists/\(listId)/invites", auth: .bearer)
    }

    /// `POST /api/lists/{id}/invites` — send an email invite (owner + subscriber).
    public static func createListInvite(listId: String, _ body: CreateInviteRequest) -> Request<CreateInviteResponse> {
        Request(method: .post, path: "/api/lists/\(listId)/invites", body: .json(body), auth: .bearer)
    }

    /// `DELETE /api/lists/{id}/invites/{token}` — revoke a pending invite.
    public static func revokeListInvite(listId: String, token: String) -> Request<RevokeShareResponse> {
        Request(method: .delete, path: "/api/lists/\(listId)/invites/\(token)", auth: .bearer)
    }
}
