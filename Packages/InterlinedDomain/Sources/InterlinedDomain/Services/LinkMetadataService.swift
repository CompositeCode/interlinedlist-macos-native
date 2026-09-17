import Foundation
import InterlinedKit

/// The link-metadata surface the App layer codes against
/// (work-consolidation.md G21).
public protocol LinkMetadataServicing: Sendable {
    /// Resolve one URL to a rich preview **without persisting anything** —
    /// safe to call while the user is still typing in the composer.
    /// Returns `nil` when the server could not resolve anything worth showing.
    func preview(for url: String) async throws -> LinkPreview?

    /// The link metadata already stored against a message.
    func stored(forMessage id: String) async throws -> [LinkPreview]

    /// Re-fetch and **persist** a message's link metadata, returning the
    /// refreshed set. Use for links whose `fetchStatus` came back `failed`.
    func refresh(forMessage id: String) async throws -> [LinkPreview]

    /// The URL to hand `AsyncImage` for a preview's thumbnail, routed through
    /// the server's Instagram proxy only when the host requires it.
    func displayImageURL(for preview: LinkPreview) -> URL?
}

/// Reads `/api/link-metadata` and `/api/messages/{id}/metadata`, and builds
/// `/api/images/proxy` URLs.
public final class LinkMetadataService: LinkMetadataServicing {

    private let api: APIClientProtocol
    private let baseURL: URL

    /// - Parameter baseURL: the API origin, needed to build absolute
    ///   `/api/images/proxy` URLs for `AsyncImage` (which takes a `URL`, not a
    ///   `Request`).
    public init(api: APIClientProtocol, baseURL: URL) {
        self.api = api
        self.baseURL = baseURL
    }

    public func preview(for url: String) async throws -> LinkPreview? {
        // A blank URL would earn a 400 ("Missing url"); short-circuit instead of
        // spending a round trip to learn that.
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let response = try await api.send(LinkMetadata.resolve(url: trimmed))
        guard let preview = LinkPreview(from: response.link) else { return nil }
        // An unreachable URL still answers 200 with `fetchStatus: "failed"` and
        // no metadata. That is a resolved *request* but not a showable preview,
        // so report nothing rather than an empty card.
        return preview.hasDisplayableContent ? preview : nil
    }

    public func stored(forMessage id: String) async throws -> [LinkPreview] {
        let dto = try await api.send(LinkMetadata.forMessage(id: id))
        return dto.links.compactMap(LinkPreview.init(from:))
    }

    public func refresh(forMessage id: String) async throws -> [LinkPreview] {
        let dto = try await api.send(LinkMetadata.refreshForMessage(id: id))
        return dto.links.compactMap(LinkPreview.init(from:))
    }

    public func displayImageURL(for preview: LinkPreview) -> URL? {
        guard let imageURL = preview.imageURL else { return nil }
        guard preview.needsImageProxy else { return imageURL }
        return LinkMetadata.imageProxyURL(
            baseURL: baseURL,
            imageURL: imageURL.absoluteString
        ) ?? imageURL
    }
}
