import Foundation
import InterlinedKit

// MARK: - Source

/// What a "Create from…" is built from (work-consolidation.md G16).
public enum MaterializeSourceRef: Sendable, Equatable {
    case messages(ids: [String])
    case lists(ids: [String])
    case rows(listId: String, rowIds: [String])
    case document(id: String)
    /// A highlighted markdown selection inside a document.
    case documentSelection(documentId: String, markdown: String)

    var wireSource: MaterializeSource {
        switch self {
        case .messages(let ids): return .messages(ids: ids)
        case .lists(let ids): return .lists(ids: ids)
        case .rows(let listId, let rowIds): return .rows(listId: listId, rowIds: rowIds)
        case .document(let id): return .document(id: id)
        case .documentSelection(let documentId, let markdown):
            return .documentElements(documentId: documentId, markdown: markdown)
        }
    }

    /// A default title for the thing being created, matching the web app's own
    /// phrasing closely enough that the two clients feel like one product.
    public func defaultTitle(authorHandle: String?) -> String {
        switch self {
        case .messages(let ids):
            if ids.count > 1 { return "\(ids.count) messages" }
            return authorHandle.map { "Message by @\($0)" } ?? "Message"
        case .lists(let ids):
            return ids.count > 1 ? "\(ids.count) lists" : "List"
        case .rows(_, let rowIds):
            return rowIds.count > 1 ? "\(rowIds.count) rows" : "Row"
        case .document:
            return "Document"
        case .documentSelection:
            return "Selection"
        }
    }
}

// MARK: - Target

/// What to create.
public enum MaterializeOutput: String, Sendable, Equatable, CaseIterable, Identifiable {
    case list
    case document
    case both

    public var id: String { rawValue }

    /// The web app's own menu labels.
    public var label: String {
        switch self {
        case .list: return "To List"
        case .document: return "To Doc"
        case .both: return "To List & Doc"
        }
    }

    public var createsList: Bool { self != .document }
    public var createsDocument: Bool { self != .list }

    var wireTarget: MaterializeTarget {
        switch self {
        case .list: return .list
        case .document: return .doc
        case .both: return .both
        }
    }
}

// MARK: - Column

/// One column of the list a Create-from will produce.
///
/// The wire names for these are `propertyKey` / `propertyName` / `propertyType` /
/// `sourceKey` — deliberately *not* the `key`/`label`/`type` used elsewhere in the
/// schema API. That asymmetry lives in the kit; this type reads the way the rest
/// of the domain does.
public struct MaterializeColumn: Sendable, Equatable, Identifiable {
    public let key: String
    public var name: String
    public var type: MaterializeColumnType
    /// The source attribute this column is filled from. Defaults to `key`.
    public var sourceKey: String

    public var id: String { key }

    public init(key: String, name: String, type: MaterializeColumnType = .text, sourceKey: String? = nil) {
        self.key = key
        self.name = name
        self.type = type
        self.sourceKey = sourceKey ?? key
    }

    var wireField: MaterializeField {
        MaterializeField(
            propertyKey: key,
            propertyName: name,
            propertyType: type.wireType,
            sourceKey: sourceKey
        )
    }
}

/// Column types the Create-from editor offers, in the web app's own order.
public enum MaterializeColumnType: String, Sendable, Equatable, CaseIterable, Identifiable {
    case text, textarea, number, date, datetime, boolean, select, multiselect, email, url, tel, priority

    public var id: String { rawValue }

    /// Title-cased for a picker.
    public var label: String {
        switch self {
        case .textarea: return "Long text"
        case .datetime: return "Date & time"
        case .multiselect: return "Multi-select"
        case .url: return "URL"
        case .tel: return "Phone"
        default: return rawValue.capitalized
        }
    }

    var wireType: MaterializeFieldType {
        MaterializeFieldType(rawValue: rawValue) ?? .text
    }
}

// MARK: - Spec

/// A fully-specified Create-from, ready to send.
public struct MaterializeSpec: Sendable, Equatable {
    public let source: MaterializeSourceRef
    public let output: MaterializeOutput
    public var list: ListSpec?
    public var document: DocumentSpec?

    public init(
        source: MaterializeSourceRef,
        output: MaterializeOutput,
        list: ListSpec? = nil,
        document: DocumentSpec? = nil
    ) {
        self.source = source
        self.output = output
        self.list = list
        self.document = document
    }

    public struct ListSpec: Sendable, Equatable {
        public var title: String
        public var description: String?
        public var isPublic: Bool
        public var columns: [MaterializeColumn]
        /// Copy the source content in as rows, rather than creating an empty list.
        public var includeSourceData: Bool

        public init(
            title: String,
            description: String? = nil,
            isPublic: Bool = false,
            columns: [MaterializeColumn],
            includeSourceData: Bool = true
        ) {
            self.title = title
            self.description = description
            self.isPublic = isPublic
            self.columns = columns
            self.includeSourceData = includeSourceData
        }
    }

    public struct DocumentSpec: Sendable, Equatable {
        public var title: String
        public var folderPath: String?
        public var isPublic: Bool
        public var listStyle: MaterializeBulletStyle
        public var rowDataStyle: MaterializeRowStyle

        public init(
            title: String,
            folderPath: String? = nil,
            isPublic: Bool = false,
            listStyle: MaterializeBulletStyle = .bulleted,
            rowDataStyle: MaterializeRowStyle = .table
        ) {
            self.title = title
            self.folderPath = folderPath
            self.isPublic = isPublic
            self.listStyle = listStyle
            self.rowDataStyle = rowDataStyle
        }
    }

    /// Whether the spec has everything the server requires. Mirrors the web app's
    /// own submit gate so the button disables rather than the request 400-ing.
    public var isComplete: Bool {
        if output.createsList {
            guard let list, !list.title.trimmed.isEmpty, !list.columns.isEmpty else { return false }
        }
        if output.createsDocument {
            guard let document, !document.title.trimmed.isEmpty else { return false }
        }
        return true
    }
}

/// How list items are bulleted in a generated document.
public enum MaterializeBulletStyle: String, Sendable, Equatable, CaseIterable, Identifiable {
    case bulleted, numbered
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    var wireStyle: MaterializeListStyle { self == .numbered ? .numbered : .bulleted }
}

/// How list rows are rendered in a generated document.
public enum MaterializeRowStyle: String, Sendable, Equatable, CaseIterable, Identifiable {
    case table, inline, paragraph
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    var wireStyle: MaterializeRowDataStyle {
        switch self {
        case .table: return .table
        case .inline: return .inline
        case .paragraph: return .paragraph
        }
    }
}

// MARK: - Outcome

/// What a Create-from produced.
public struct MaterializeOutcome: Sendable, Equatable {
    public let listId: String?
    public let listTitle: String?
    public let documentId: String?
    public let documentTitle: String?

    public init(
        listId: String? = nil,
        listTitle: String? = nil,
        documentId: String? = nil,
        documentTitle: String? = nil
    ) {
        self.listId = listId
        self.listTitle = listTitle
        self.documentId = documentId
        self.documentTitle = documentTitle
    }

    public init(from dto: MaterializeResponse) {
        self.init(
            listId: dto.listId,
            listTitle: dto.list?.title,
            documentId: dto.documentId,
            documentTitle: dto.document?.title
        )
    }

    /// True when the server acknowledged without an id this client recognises.
    public var isEmpty: Bool { listId == nil && documentId == nil }
}

// MARK: - Default columns

public extension MaterializeColumn {

    /// The default columns the web app offers per source kind, so a native
    /// Create-from opens on the same starting point as the web one.
    static func defaults(for source: MaterializeSourceRef) -> [MaterializeColumn] {
        switch source {
        case .messages:
            return [
                MaterializeColumn(key: "content", name: "Content", type: .textarea),
                MaterializeColumn(key: "author", name: "Author", type: .text),
                MaterializeColumn(key: "posted", name: "Posted", type: .text),
                MaterializeColumn(key: "links", name: "Links", type: .textarea),
                MaterializeColumn(key: "tags", name: "Tags", type: .text)
            ]
        case .lists:
            return [
                MaterializeColumn(key: "title", name: "Title", type: .text),
                MaterializeColumn(key: "description", name: "Description", type: .textarea),
                MaterializeColumn(key: "updated", name: "Updated", type: .text)
            ]
        case .rows:
            return [
                MaterializeColumn(key: "content", name: "Content", type: .textarea)
            ]
        case .document, .documentSelection:
            return [
                MaterializeColumn(key: "title", name: "Title", type: .text),
                MaterializeColumn(key: "content", name: "Content", type: .textarea)
            ]
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
