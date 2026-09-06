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
///
/// The member names are **not** the schema-field names used elsewhere in the
/// API (`key`/`label`/`type`). Captured 2026-09-05 from the web app's own
/// request: this route wants `propertyKey`/`propertyName`/`propertyType`, plus
/// `sourceKey` naming the source attribute the column is filled from.
///
/// The server's rejection message for a wrong shape is actively misleading —
/// it says a field "must have a 'key' property (string)" even when the payload
/// carries one — because it describes the *derived* internal schema, not the
/// request body. Do not chase that message; match this shape.
public struct MaterializeField: Encodable, Sendable, Equatable {
    /// Column key on the created list, e.g. `"content"`.
    public let propertyKey: String
    /// Human-readable column name, e.g. `"Content"`.
    public let propertyName: String
    /// One of `MaterializeFieldType`, sent as its raw value.
    public let propertyType: MaterializeFieldType
    /// The source attribute this column is filled from. Defaults to `propertyKey`,
    /// which is what the web app sends for every default column.
    public let sourceKey: String

    public init(
        propertyKey: String,
        propertyName: String,
        propertyType: MaterializeFieldType = .text,
        sourceKey: String? = nil
    ) {
        self.propertyKey = propertyKey
        self.propertyName = propertyName
        self.propertyType = propertyType
        self.sourceKey = sourceKey ?? propertyKey
    }
}

/// Column types the Create-from column editor offers, in its own order.
/// Captured 2026-09-05 from the modal's type `<select>`.
public enum MaterializeFieldType: String, Encodable, Sendable, Equatable, CaseIterable {
    case text
    case textarea
    case number
    case date
    case datetime
    case boolean
    case select
    case multiselect
    case email
    case url
    case tel
    case priority
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

/// `POST /api/materialize` response. Shape verified live 2026-09-05 by a real
/// create (since deleted): a list target answers `201`
/// `{"list":{"id":"…","title":"…"}}` — the created object is **nested**, not a
/// flat `listId`. The doc/both shapes are modelled the same way and tolerate a
/// flat form too, so a server that flattens later still decodes.
public struct MaterializeResponse: Decodable, Sendable, Equatable {
    public let list: CreatedDTO?
    public let document: CreatedDTO?

    /// The created list's id, whether the server nested it or sent it flat.
    public let listId: String?
    /// The created document's id, whether the server nested it or sent it flat.
    public let documentId: String?

    public struct CreatedDTO: Decodable, Sendable, Equatable {
        public let id: String?
        public let title: String?

        public init(id: String? = nil, title: String? = nil) {
            self.id = id
            self.title = title
        }
    }

    private enum CodingKeys: String, CodingKey {
        case list, document, listId, documentId
    }

    public init(
        list: CreatedDTO? = nil,
        document: CreatedDTO? = nil,
        listId: String? = nil,
        documentId: String? = nil
    ) {
        self.list = list
        self.document = document
        self.listId = listId ?? list?.id
        self.documentId = documentId ?? document?.id
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = try c.decodeIfPresent(CreatedDTO.self, forKey: .list)
        let document = try c.decodeIfPresent(CreatedDTO.self, forKey: .document)
        self.list = list
        self.document = document
        // Prefer the nested id the live route returns; fall back to a flat one.
        self.listId = try c.decodeIfPresent(String.self, forKey: .listId) ?? list?.id
        self.documentId = try c.decodeIfPresent(String.self, forKey: .documentId) ?? document?.id
    }
}
