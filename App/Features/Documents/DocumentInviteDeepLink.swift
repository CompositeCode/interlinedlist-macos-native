// DocumentInviteDeepLink
//
// Turns an opened document-invite URL into a routed presentation of
// `DocumentInviteView` (work-consolidation.md G24). The address is the `url`
// the server puts in the invite email:
// `https://interlinedlist.com/documents/invite/{token}`.
//
// Deliberately separate from `ShareURLParser` / `ShareLinkDeepLink` in the
// Sharing feature rather than an extra case on them. A share link and an email
// invite are different objects with different routes, different response
// shapes and — critically — different capabilities: a share link can be
// claimed from this app, an invite cannot (see `DocumentInviteViewModel`).
// Folding them into one parser would put a claim button one boolean away from
// a surface that must never show one.
//
// Mirrors the project's deep-link convention: a `Notification.Name` colocated
// with the feature, a static poster so the URL handler in `InterlinedListApp`
// stays a one-liner, and `MainWindowView` owning the sheet presentation.
//
// Decision 0003: App-layer only; this file needs nothing but Foundation.

import Foundation

/// An invite reference extracted from a URL — the opaque token to resolve.
struct ParsedDocumentInvite: Equatable {
    let token: String
}

enum DocumentInviteURLParser {

    /// The `interlinedlist://` custom scheme the app registers, shared with
    /// the OAuth callback and the share-link handler.
    static let scheme = "interlinedlist"

    /// Parses a URL into a `ParsedDocumentInvite`, or `nil` when it is not a
    /// document invite link. Accepts the `https` web address the invite email
    /// carries and the custom scheme, and tolerates the resource word landing
    /// in the host (`interlinedlist://documents/invite/{token}` parses
    /// "documents" as the host, not a path segment).
    static func parse(_ url: URL) -> ParsedDocumentInvite? {
        var segments: [String] = []
        if let host = url.host,
           !host.isEmpty,
           host != "interlinedlist.com",
           host != "www.interlinedlist.com" {
            segments.append(host)
        }
        segments.append(contentsOf: url.pathComponents.filter { $0 != "/" && !$0.isEmpty })
        return match(segments)
    }

    /// Parses a raw string (e.g. pasted from an invite email). Trims first so
    /// a pasted line with a trailing newline still parses.
    static func parse(string: String) -> ParsedDocumentInvite? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return parse(url)
    }

    // MARK: - Matching

    /// Matches `[…, "documents", "invite", <token>]` at the tail.
    ///
    /// `documents` is required, not optional: `/lists/invite/{token}` is a
    /// *list* invite with its own route, and quietly treating it as a document
    /// invite would resolve the wrong resource.
    private static func match(_ segments: [String]) -> ParsedDocumentInvite? {
        let cleaned = segments.filter { $0.lowercased() != "share" }
        guard cleaned.count >= 3 else { return nil }
        let tail = Array(cleaned.suffix(3))
        guard tail[0].lowercased() == "documents",
              tail[1].lowercased() == "invite",
              !tail[2].isEmpty else { return nil }
        return ParsedDocumentInvite(token: tail[2])
    }
}

extension Foundation.Notification.Name {
    /// Posted when an opened URL resolves to a document invite. `object` is the
    /// `ParsedDocumentInvite`. Observed by `MainWindowView`, which presents
    /// `DocumentInviteView`.
    static let openDocumentInvite = Foundation.Notification.Name("InterlinedList.openDocumentInvite")
}

enum DocumentInviteDeepLink {

    /// Attempts to route `url` as a document invite. Returns `true` (and posts
    /// `.openDocumentInvite`) on a hit; `false` otherwise so the caller falls
    /// through to the share-link and OAuth handlers. `post` defaults to `nil`,
    /// in which case the parsed invite goes to `NotificationCenter.default`;
    /// tests pass a capturing closure to observe routing without the center.
    @discardableResult
    @MainActor
    static func handle(_ url: URL, post: ((ParsedDocumentInvite) -> Void)? = nil) -> Bool {
        guard let parsed = DocumentInviteURLParser.parse(url) else { return false }
        if let post {
            post(parsed)
        } else {
            NotificationCenter.default.post(name: .openDocumentInvite, object: parsed)
        }
        return true
    }
}
