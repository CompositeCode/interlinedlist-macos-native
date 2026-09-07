import Foundation

/// Canonical web permalink for a message ("Link" in the web message actions).
///
/// The link is a pure client-side projection — there is no API route that
/// hands back a message URL — so the shape lives here in the domain rather
/// than being re-derived by each feature that needs it. Three App-layer
/// surfaces consume it: the message row's Link action, the "Push & Comment"
/// body, and `CreateIssueFromMessageViewModel`'s issue body, which previously
/// owned a private copy of this logic.
///
/// Shape: `<base>/messages/<id>` — matching the web app's own route.
public enum MessagePermalink {

    /// Production web front-end. Overridable at every call site so tests and
    /// a future staging build never hard-code the live host.
    public static let defaultWebBaseURL = URL(string: "https://interlinedlist.com")!

    /// Path-segment-safe character set: `urlPathAllowed` still permits `/`,
    /// which would let an id containing a slash silently forge extra path
    /// segments. Removing it forces such an id to percent-encode instead.
    private static let pathSegmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove("/")
        return set
    }()

    /// Builds the permalink for `id`, or `nil` when the id is empty / blank
    /// or cannot be encoded. Returning `nil` rather than a half-formed URL
    /// lets the UI hide the affordance instead of offering a broken link.
    public static func url(forMessageID id: String, base: URL = defaultWebBaseURL) -> URL? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) else {
            return nil
        }
        // Normalise the base so a caller-supplied trailing slash can't produce
        // a double slash in the middle of the path.
        var stem = base.absoluteString
        while stem.hasSuffix("/") { stem.removeLast() }
        return URL(string: "\(stem)/messages/\(encoded)")
    }
}

public extension Message {

    /// This message's canonical web permalink, or `nil` when the id can't
    /// form one. See `MessagePermalink`.
    func permalink(base: URL = MessagePermalink.defaultWebBaseURL) -> URL? {
        MessagePermalink.url(forMessageID: id, base: base)
    }
}
