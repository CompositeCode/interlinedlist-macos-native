import Foundation

/// Request builders for the **Sharing / Share Links** API group (the-gaps.md
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
}
