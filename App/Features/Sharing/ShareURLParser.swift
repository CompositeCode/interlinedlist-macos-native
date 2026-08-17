// ShareURLParser
//
// Pure parser that turns a pasted share URL or an `interlinedlist://`
// deep link into a typed `ParsedShare` (work-consolidation.md G3). Recognizes both
// resource shapes:
//   • lists:      …/lists/shared/{token}
//   • documents:  …/documents/shared/{token}
// across three URL forms:
//   • https://interlinedlist.com/lists/shared/{token}
//   • interlinedlist://lists/shared/{token}      (host = "lists")
//   • interlinedlist://share/lists/shared/{token} (host = "share")
//
// The App's deep-link handler and the "paste a share link" field both call
// `ShareURLParser.parse(_:)`; keeping the logic here (pure, string-only)
// means it is exhaustively unit-testable without a live URL round-trip and
// the two call sites can't drift.
//
// Per decision 0003, this type lives in the App layer and depends on
// `InterlinedDomain` only (in fact only Foundation).

import Foundation

/// A share reference extracted from a URL — which resource kind, and the
/// opaque token to resolve.
struct ParsedShare: Equatable {
    enum Kind: Equatable { case list, document }
    let kind: Kind
    let token: String
}

enum ShareURLParser {

    /// The `interlinedlist://` custom scheme the app registers for deep
    /// links (matches the OAuth-callback scheme already handled in
    /// `InterlinedListApp`).
    static let scheme = "interlinedlist"

    /// Parses a URL into a `ParsedShare`, or returns `nil` when it is not a
    /// share link. Accepts both `https` web URLs and the custom scheme; the
    /// host is ignored for `https` (any interlinedlist host works) and
    /// tolerated for the custom scheme (`lists`/`documents`/`share` may
    /// appear as the host depending on how the OS composed the URL).
    static func parse(_ url: URL) -> ParsedShare? {
        // Normalize into path segments regardless of whether the resource
        // words landed in the host or the path. `interlinedlist://lists/…`
        // parses "lists" as the host, so fold host + path segments into one
        // ordered list and match the trailing `<resource>/shared/<token>`.
        var segments: [String] = []
        if let host = url.host, !host.isEmpty, host != "interlinedlist.com", host != "www.interlinedlist.com" {
            segments.append(host)
        }
        segments.append(contentsOf: url.pathComponents.filter { $0 != "/" && !$0.isEmpty })

        return match(segments)
    }

    /// Parses a raw string (e.g. from the paste field) into a
    /// `ParsedShare`. Trims surrounding whitespace first so a pasted line
    /// with trailing newline still parses.
    static func parse(string: String) -> ParsedShare? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return parse(url)
    }

    /// Builds the canonical web share URL for a resource + token, used by
    /// the share panel's copy affordance when the server did not return a
    /// pre-built `ShareLink.url`.
    static func webURL(base: URL, kind: ParsedShare.Kind, token: String) -> URL? {
        let resource = kind == .list ? "lists" : "documents"
        return base
            .appendingPathComponent(resource)
            .appendingPathComponent("shared")
            .appendingPathComponent(token)
    }

    // MARK: - Matching

    /// Matches `[… , <resource>, "shared", <token>]` at the tail of the
    /// segment list. Anything else returns `nil`.
    private static func match(_ segments: [String]) -> ParsedShare? {
        // Ignore a leading "share" router segment if present.
        let cleaned = segments.filter { $0.lowercased() != "share" }
        guard cleaned.count >= 3 else { return nil }
        let tail = Array(cleaned.suffix(3))
        let resource = tail[0].lowercased()
        let sharedMarker = tail[1].lowercased()
        let token = tail[2]
        guard sharedMarker == "shared", !token.isEmpty else { return nil }
        switch resource {
        case "lists": return ParsedShare(kind: .list, token: token)
        case "documents": return ParsedShare(kind: .document, token: token)
        default: return nil
        }
    }
}
