import Foundation

/// Canonical public web permalink for a message, plus the embed snippet that
/// sits beside it in the web's Share menu ("Copy link" / "Get embed code").
///
/// Both are pure client-side projections — there is no API route that hands
/// back a message URL or an embed blob — so the shapes live here in the domain
/// rather than being re-derived by each feature that needs them. Three
/// App-layer surfaces consume them: the message row's Share menu, the same
/// menu mirrored into the row's context menu, and
/// `CreateIssueFromMessageViewModel`'s issue body.
///
/// Shape: `<base>/user/<username>/status/<id>`.
///
/// GitHub #38 — this used to build `<base>/messages/<id>`, which is an
/// **authenticated** route: anonymous visitors are redirected to `/login`, so
/// every link the app handed out (including the one pasted into GitHub issues)
/// landed strangers on a sign-in page. Verified live on 2026-09-09:
///
///     GET /messages/d05faf17-…              -> 200, final URL /login
///     GET /user/hubcity/status/d05faf17-…   -> 200, serves the message
///
/// The shapes below mirror the web's own share component verbatim.
public enum MessagePermalink {

    /// Production web front-end. Overridable at every call site so tests and
    /// a future staging build never hard-code the live host.
    public static let defaultWebBaseURL = URL(string: "https://interlinedlist.com")!

    /// Path-segment-safe character set: `urlPathAllowed` still permits `/`,
    /// which would let an id or username containing a slash silently forge
    /// extra path segments. Removing it forces such a value to percent-encode.
    private static let pathSegmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove("/")
        return set
    }()

    /// Builds the public permalink for `id` authored by `authorUsername`, or
    /// `nil` when either component is empty / blank or cannot be encoded.
    ///
    /// The author handle is a **required** input rather than an optional with a
    /// fallback: without it there is no valid public route at all, and
    /// returning `nil` lets the UI hide the affordance instead of offering a
    /// link that 404s.
    ///
    /// Note: the web encodes only the username and interpolates the id raw. We
    /// encode both — for every server-issued id (a UUID) the result is
    /// identical, and encoding closes the path-forging hole for a malformed one.
    public static func url(
        forMessageID id: String,
        authorUsername: String,
        base: URL = defaultWebBaseURL
    ) -> URL? {
        guard
            let encodedID = encodedSegment(id),
            let encodedUsername = encodedSegment(authorUsername)
        else { return nil }
        return URL(string: "\(normalizedOrigin(base))/user/\(encodedUsername)/status/\(encodedID)")
    }

    /// Builds the HTML snippet the web's "Get embed code" action copies, or
    /// `nil` when the permalink itself cannot be formed.
    ///
    /// The markup is **transcribed from the web's own share component**, not
    /// invented: a `blockquote.il-embed` carrying the raw message id, a
    /// fallback anchor for readers whose page never runs the script, and the
    /// async `/embed/widgets.js` loader that upgrades the blockquote into the
    /// rendered card. `/embed/widgets.js` was confirmed live (200,
    /// `application/javascript`) on 2026-09-09.
    ///
    /// Every interpolated value is HTML-escaped exactly as the web escapes it
    /// (`&` first, so an already-escaped entity can't be produced), because the
    /// id, the URL and the origin all land inside double-quoted attributes.
    public static func embedHTML(
        forMessageID id: String,
        authorUsername: String,
        base: URL = defaultWebBaseURL
    ) -> String? {
        guard let canonical = url(forMessageID: id, authorUsername: authorUsername, base: base) else {
            return nil
        }
        // The web writes the *raw* (trimmed) id into `data-message-id`, not the
        // percent-encoded path segment — the widget matches on the id it was
        // given, so keep them identical.
        let escapedID = htmlEscaped(id.trimmingCharacters(in: .whitespacesAndNewlines))
        let escapedURL = htmlEscaped(canonical.absoluteString)
        let escapedOrigin = htmlEscaped(normalizedOrigin(base))
        return """
        <blockquote class="il-embed" data-message-id="\(escapedID)">
          <a href="\(escapedURL)" target="_blank" rel="noopener">View this message on InterlinedList</a>
        </blockquote>
        <script async src="\(escapedOrigin)/embed/widgets.js"></script>
        """
    }

    // MARK: - Helpers

    /// Trims, rejects blank, then percent-encodes one path segment.
    private static func encodedSegment(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed)
    }

    /// Strips trailing slashes from the base so a caller-supplied one can't
    /// produce a double slash in the middle of the path. Mirrors the web's
    /// own `origin.replace(/\/+$/, "")`.
    private static func normalizedOrigin(_ base: URL) -> String {
        var stem = base.absoluteString
        while stem.hasSuffix("/") { stem.removeLast() }
        return stem
    }

    /// The web's escape function, character-for-character and in the same
    /// order — `&` must be replaced first or the later entities get mangled.
    private static func htmlEscaped(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

public extension Message {

    /// This message's **shareable** public permalink, or `nil` when it cannot
    /// be handed to anyone else.
    ///
    /// `nil` in two cases, and both are deliberate (GitHub #38):
    ///
    /// - the author handle or the id is missing / blank, so no valid route
    ///   exists;
    /// - the message is **private**. Only public messages resolve for a
    ///   signed-out visitor, so a copy action on a private post would produce a
    ///   link nobody else can open — worse than offering no action at all.
    ///
    /// Every caller therefore gets the visibility gate for free, including the
    /// GitHub-issue body, which must not embed a link that 404s for a reader.
    func permalink(base: URL = MessagePermalink.defaultWebBaseURL) -> URL? {
        guard visibility == .public else { return nil }
        return MessagePermalink.url(forMessageID: id, authorUsername: author.username, base: base)
    }

    /// The HTML snippet for embedding this message in a page, or `nil` under
    /// exactly the same conditions as `permalink(base:)`. See
    /// `MessagePermalink.embedHTML(forMessageID:authorUsername:base:)`.
    func embedHTML(base: URL = MessagePermalink.defaultWebBaseURL) -> String? {
        guard visibility == .public else { return nil }
        return MessagePermalink.embedHTML(forMessageID: id, authorUsername: author.username, base: base)
    }
}
