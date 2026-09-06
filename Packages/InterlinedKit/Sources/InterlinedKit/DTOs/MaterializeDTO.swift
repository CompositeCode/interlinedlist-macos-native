import Foundation

/// What a materialize call is built **from** (work-consolidation.md G16).
///
/// Shapes captured from the web client's own `sourceRef` construction and
/// confirmed against the live route 2026-09-05 (a well-formed ref with unknown
/// ids answers `404 "One or more messages are unavailable"` / `"Document is
/// unavailable"`, which proves the shape parsed and that nothing was created).
public enum MaterializeSource: Encodable, Sendable, Equatable {
    /// One or many timeline messages.
    case messages(ids: [String])
    /// One or many of the caller's lists.
    case lists(ids: [String])
    /// Selected rows within a single list.
    case rows(listId: String, rowIds: [String])
    /// A whole document.
    case document(id: String)
    /// A highlighted markdown selection inside a document.
    case documentElements(documentId: String, markdown: String)

    private enum CodingKeys: String, CodingKey {
        case kind, messageIds, listIds, listId, rowIds, documentId, markdown
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .messages(let ids):
            try c.encode("messages", forKey: .kind)
            try c.encode(ids, forKey: .messageIds)
        case .lists(let ids):
            try c.encode("lists", forKey: .kind)
            try c.encode(ids, forKey: .listIds)
        case .rows(let listId, let rowIds):
            try c.encode("rows", forKey: .kind)
            try c.encode(listId, forKey: .listId)
            try c.encode(rowIds, forKey: .rowIds)
        case .document(let id):
            try c.encode("document", forKey: .kind)
            try c.encode(id, forKey: .documentId)
        case .documentElements(let documentId, let markdown):
            try c.encode("docElements", forKey: .kind)
            try c.encode(documentId, forKey: .documentId)
            try c.encode(markdown, forKey: .markdown)
        }
    }
}

/// What to create. Verified live 2026-09-05: any other value answers
/// `400 "Invalid target"`.
public enum MaterializeTarget: String, Encodable, Sendable, Equatable, CaseIterable {
    case list
    case doc
    case both
}

/// How list rows are rendered into the generated document.
public enum MaterializeRowDataStyle: String, Encodable, Sendable, Equatable, CaseIterable {
    case table
    case inline
    case paragraph
}

/// How list items are bulleted in the generated document.
public enum MaterializeListStyle: String, Encodable, Sendable, Equatable, CaseIterable {
    case bulleted
    case numbered
}

/// The `listConfig` half of the request — present when the target is `.list` or `.both`.
///
/// ⚠️ **`fields` is UNRESOLVED — see the note on `Materialize.create`.** The live
/// route rejects every field descriptor tried so far, including ones that carry
/// the `key` string its own error message asks for.
public struct MaterializeListConfig: Encodable, Sendable, Equatable {
    public let title: String
    public let description: String?
    public let isPublic: Bool
    public let fields: [MaterializeField]
    public let includeData: Bool

    public init(
        title: String,
        description: String? = nil,
        isPublic: Bool = false,
        fields: [MaterializeField],
        includeData: Bool = true
    ) {
        self.title = title
        self.description = description
        self.isPublic = isPublic
        self.fields = fields
        self.includeData = includeData
    }
}

/// One column of the list a materialize call will create.
public struct MaterializeField: Encodable, Sendable, Equatable {
    public let key: String
    public let label: String?
    public let type: String?

    public init(key: String, label: String? = nil, type: String? = nil) {
        self.key = key
        self.label = label
        self.type = type
    }
}

/// The `docConfig` half of the request — present when the target is `.doc` or `.both`.
public struct MaterializeDocConfig: Encodable, Sendable, Equatable {
    public let title: String
    public let relativePath: String?
    public let isPublic: Bool
    public let listStyle: MaterializeListStyle
    public let rowDataStyle: MaterializeRowDataStyle

    public init(
        title: String,
        relativePath: String? = nil,
        isPublic: Bool = false,
        listStyle: MaterializeListStyle = .bulleted,
        rowDataStyle: MaterializeRowDataStyle = .table
    ) {
        self.title = title
        self.relativePath = relativePath
        self.isPublic = isPublic
        self.listStyle = listStyle
        self.rowDataStyle = rowDataStyle
    }
}

/// `POST /api/materialize` request body.
public struct MaterializeRequest: Encodable, Sendable, Equatable {
    public let target: MaterializeTarget
    public let source: MaterializeSource
    public let listConfig: MaterializeListConfig?
    public let docConfig: MaterializeDocConfig?

    public init(
        target: MaterializeTarget,
        source: MaterializeSource,
        listConfig: MaterializeListConfig? = nil,
        docConfig: MaterializeDocConfig? = nil
    ) {
        self.target = target
        self.source = source
        self.listConfig = listConfig
        self.docConfig = docConfig
    }
}

/// `POST /api/materialize` response. Members are optional because which ones
/// come back depends on the target; the ids are what the UI navigates to.
public struct MaterializeResponse: Decodable, Sendable, Equatable {
    public let listId: String?
    public let documentId: String?
    public let listUrl: String?
    public let documentUrl: String?

    public init(
        listId: String? = nil,
        documentId: String? = nil,
        listUrl: String? = nil,
        documentUrl: String? = nil
    ) {
        self.listId = listId
        self.documentId = documentId
        self.listUrl = listUrl
        self.documentUrl = documentUrl
    }
}
