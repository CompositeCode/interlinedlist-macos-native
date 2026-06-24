import Foundation

// MARK: - DocumentBody

/// Typed wrapper around the Markdown source of a document.
///
/// Today this is a thin wrapper over `String`, but the wrapper exists so the
/// domain layer can grow richer body types (attributed content, structured
/// blocks, attachments) without changing every call site. Treat `Document.body`
/// as opaque — go through `.markdown` to read or initialise.
public struct DocumentBody: Sendable, Equatable, Hashable {

    /// The raw Markdown source.
    public let markdown: String

    public init(markdown: String) {
        self.markdown = markdown
    }

    /// Convenience: the empty body.
    public static let empty = DocumentBody(markdown: "")
}

// MARK: - Document

/// A Markdown document the M4 Documents UI consumes (PLAN.md §1, §6 M4).
///
/// Domain projection of `DocumentDTO`. The wire body field (`content`) is
/// optional on the sync delta envelope and required on detail/create
/// responses; the domain collapses that nuance into a non-optional
/// `DocumentBody` defaulting to `.empty`, and surfaces `deleted` as a plain
/// `Bool` (`false` when the field is absent or `null`).
///
/// `version` is a passthrough for the etag/version field on the document
/// object that the API does not yet expose (tracked as backend ask 3.1).
/// When absent it is `nil`; when present the sync engine routes it into
/// the conflict path.
public struct Document: Sendable, Equatable, Hashable, Identifiable {

    public let id: String
    public let folderId: String?
    public let title: String
    public let body: DocumentBody
    public let updatedAt: Date
    public let createdAt: Date?
    public let isPublic: Bool
    public let deleted: Bool
    /// Server-supplied version / etag for optimistic-concurrency conflict
    /// detection on PATCH. `nil` when the API omits the field — backend ask
    /// 3.1 covers adding it. The sync engine falls back to `updatedAt`
    /// comparisons when this is `nil`.
    public let version: String?

    public init(
        id: String,
        folderId: String? = nil,
        title: String,
        body: DocumentBody = .empty,
        updatedAt: Date,
        createdAt: Date? = nil,
        isPublic: Bool = false,
        deleted: Bool = false,
        version: String? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.isPublic = isPublic
        self.deleted = deleted
        self.version = version
    }
}
