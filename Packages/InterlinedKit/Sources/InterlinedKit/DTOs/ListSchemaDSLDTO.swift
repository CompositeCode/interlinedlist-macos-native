import Foundation

// MARK: - The List Schema DSL object
//
// The client used to model a list's schema as a **string** (`"Title:text,
// Year:number"`). The API models it as an **object**, and always has —
// `POST /api/lists` with a string schema answers a flat
// `400 {"error":"Invalid schema: DSL must be an object"}`. So creating a
// schema-bearing list from macOS was impossible, reading a schema could not
// decode, and saving one was rejected (GitHub #85, and #75 for the sibling
// envelope defect on `GET /api/lists/{id}`).
//
// Everything below is modelled against **captured** payloads, not against the
// OpenAPI examples — the spec's `PUT .../schema` 200 example shows a bare
// `{properties: […]}` where the live route answers `{message, data}`. Where the
// two disagree, the capture wins. Probe transcripts: `docs/spikes/list-schema-wire-shapes.md`.

/// The schema of a list, as `GET /api/lists/[id]/schema` returns it under
/// `data` and as `POST /api/lists` / `PUT /api/lists/[id]/schema` accept it
/// under `schema`.
///
/// Read and write use the **same** shape, which is why one type serves both.
public struct ListSchemaDSLDTO: Codable, Sendable, Equatable {

    /// The schema's own name. On a read this mirrors the list title; on a write
    /// the server accepts it and does not appear to use it to rename the list.
    public let name: String?

    /// Optional prose describing the schema. Round-trips; a write sets the
    /// list's `description`.
    public let description: String?

    /// The ordered columns. The server also returns `displayOrder` per field,
    /// so array order and `displayOrder` agree on a read — but `displayOrder`
    /// is the authority, because a future partial update could disagree.
    public let fields: [ListSchemaFieldDTO]

    public init(name: String? = nil, description: String? = nil, fields: [ListSchemaFieldDTO]) {
        self.name = name
        self.description = description
        self.fields = fields
    }
}

/// One column in the schema DSL object.
///
/// - Important: `key` and `label` are **different things**, and conflating them
///   is the trap this shape sets. Row data is keyed by `key`
///   (`"rowData":{"title":"Dune","year":1965}`), while `label` is only what the
///   header renders. A client that used one value for both would render every
///   cell empty for any column whose display name differs from its key.
public struct ListSchemaFieldDTO: Codable, Sendable, Equatable {

    /// The row-data key. This is what `ListRowDTO.rowData` is keyed by.
    public let key: String

    /// The column type token: `text`, `number`, `boolean`, `date`, `url`,
    /// `email`, `select`, `markdown`.
    public let type: String

    /// The display name shown in the column header.
    public let label: String?

    /// Zero-based column order. Returned on every read.
    public let displayOrder: Int?

    /// Whether a row must supply this column.
    public let required: Bool?

    /// Whether the column is shown. Distinct from deletion — a hidden column
    /// keeps its data.
    public let visible: Bool?

    /// Hint text shown under the field in the row form.
    public let helpText: String?

    /// Placeholder text for an empty field.
    public let placeholder: String?

    /// The column's default for a new row. Type-erased because it follows the
    /// column's own type: `false` for a boolean, `"todo"` for a select.
    public let defaultValue: ListJSONValue?

    /// Per-type validation rules. See `ListFieldValidationDTO`.
    public let validation: ListFieldValidationDTO?

    /// The option set for a `select` column.
    ///
    /// The server returns the options **twice** on a read — once here and once
    /// as `validation.options` — and accepts either on a write. Both are
    /// modelled rather than picking one, because dropping the redundant spelling
    /// would silently lose the options if the server ever stops sending the
    /// other. `ListSchemaFieldDTO.resolvedOptions` is the single reader.
    public let options: [String]?

    public init(
        key: String,
        type: String,
        label: String? = nil,
        displayOrder: Int? = nil,
        required: Bool? = nil,
        visible: Bool? = nil,
        helpText: String? = nil,
        placeholder: String? = nil,
        defaultValue: ListJSONValue? = nil,
        validation: ListFieldValidationDTO? = nil,
        options: [String]? = nil
    ) {
        self.key = key
        self.type = type
        self.label = label
        self.displayOrder = displayOrder
        self.required = required
        self.visible = visible
        self.helpText = helpText
        self.placeholder = placeholder
        self.defaultValue = defaultValue
        self.validation = validation
        self.options = options
    }

    /// The option set, from whichever of the two spellings the payload carried.
    public var resolvedOptions: [String]? {
        options ?? validation?.options
    }
}

/// The validation rules the server stores per column, as
/// `ListSchemaFieldDTO.validation` on a read/write and as
/// `ListPropertyDTO.validationRules` on the property projection.
///
/// Every rule is optional and they are not mutually exclusive: a `text` column
/// can carry `minLength`/`maxLength`/`pattern`, a `number` column `min`/`max`,
/// and a `select` column `options`. Captured live 2026-09-15.
public struct ListFieldValidationDTO: Codable, Sendable, Equatable {
    /// Minimum numeric value (`number` columns).
    public let min: Double?
    /// Maximum numeric value (`number` columns).
    public let max: Double?
    /// Minimum character count (`text`-family columns).
    public let minLength: Int?
    /// Maximum character count (`text`-family columns).
    public let maxLength: Int?
    /// A regular expression the value must match. Server-side grammar; treat as
    /// opaque and surface the server's rejection rather than pre-validating
    /// against a different regex engine.
    public let pattern: String?
    /// The allowed values for a `select` column.
    public let options: [String]?

    public init(
        min: Double? = nil,
        max: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        pattern: String? = nil,
        options: [String]? = nil
    ) {
        self.min = min
        self.max = max
        self.minLength = minLength
        self.maxLength = maxLength
        self.pattern = pattern
        self.options = options
    }

    /// `true` when no rule is set — used to avoid encoding an empty object on a
    /// write, which the server treats as "clear the rules".
    public var isEmpty: Bool {
        min == nil && max == nil && minLength == nil
            && maxLength == nil && pattern == nil && (options?.isEmpty ?? true)
    }
}

// MARK: - The property projection

/// A stored column as the server returns it alongside a list — under
/// `data.properties` on `GET /api/lists/[id]`, `POST /api/lists` and
/// `PUT /api/lists/[id]/schema`.
///
/// This is the **same** information as `ListSchemaFieldDTO` under different
/// key names (`propertyKey`/`propertyName` rather than `key`/`label`,
/// `validationRules` rather than `validation`). Both are modelled because both
/// are what the server sends; `ListPropertyDTO.asSchemaField` is the one place
/// that reconciles them, so no caller has to know there are two spellings.
public struct ListPropertyDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let listId: String?
    public let propertyKey: String
    public let propertyName: String?
    public let propertyType: String
    public let displayOrder: Int?
    public let isRequired: Bool?
    public let defaultValue: ListJSONValue?
    public let validationRules: ListFieldValidationDTO?
    public let helpText: String?
    public let placeholder: String?
    public let isVisible: Bool?
    /// A rule making this column's visibility depend on another column's value.
    /// Never non-null on any captured payload, so it is kept type-erased rather
    /// than guessed at — modelling an unseen shape is how the G21 and G25
    /// silent-decode defects happened.
    public let visibilityCondition: ListJSONValue?
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        listId: String? = nil,
        propertyKey: String,
        propertyName: String? = nil,
        propertyType: String,
        displayOrder: Int? = nil,
        isRequired: Bool? = nil,
        defaultValue: ListJSONValue? = nil,
        validationRules: ListFieldValidationDTO? = nil,
        helpText: String? = nil,
        placeholder: String? = nil,
        isVisible: Bool? = nil,
        visibilityCondition: ListJSONValue? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.listId = listId
        self.propertyKey = propertyKey
        self.propertyName = propertyName
        self.propertyType = propertyType
        self.displayOrder = displayOrder
        self.isRequired = isRequired
        self.defaultValue = defaultValue
        self.validationRules = validationRules
        self.helpText = helpText
        self.placeholder = placeholder
        self.isVisible = isVisible
        self.visibilityCondition = visibilityCondition
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The same column expressed in the DSL spelling, so a caller that has a
    /// `properties` array and a caller that has a `fields` array can share one
    /// mapping path.
    public var asSchemaField: ListSchemaFieldDTO {
        ListSchemaFieldDTO(
            key: propertyKey,
            type: propertyType,
            label: propertyName,
            displayOrder: displayOrder,
            required: isRequired,
            visible: isVisible,
            helpText: helpText,
            placeholder: placeholder,
            defaultValue: defaultValue,
            validation: validationRules,
            options: validationRules?.options
        )
    }
}

// MARK: - Envelopes

/// `GET /api/lists/[id]/schema` → `{ "data": { …schema DSL… } }`.
public struct ListSchemaResponse: Codable, Sendable, Equatable {
    public let data: ListSchemaDSLDTO

    public init(data: ListSchemaDSLDTO) {
        self.data = data
    }
}

/// The `{ message?, data }` envelope every single-list write answers:
/// `POST /api/lists` (201), `PUT /api/lists/[id]`, `PUT /api/lists/[id]/schema`
/// and `POST /api/lists/[id]/refresh`. `GET /api/lists/[id]` uses the same
/// shape with no `message`, which is why `message` is optional.
public struct ListResponse: Codable, Sendable, Equatable {
    public let message: String?
    public let data: ListDTO
    /// Present only for GitHub-backed lists, per the spec's `POST /api/lists`
    /// 201 description. Never observed populated on the test account, which has
    /// no accessible repositories (GitHub #51).
    public let refreshStatus: String?

    public init(message: String? = nil, data: ListDTO, refreshStatus: String? = nil) {
        self.message = message
        self.data = data
        self.refreshStatus = refreshStatus
    }
}

// MARK: - Write bodies

/// `PUT /api/lists/[id]/schema` body — the destructive whole-schema rebuild.
///
/// The route also accepts a `properties` array for a non-destructive per-column
/// update. Only the rebuild form is modelled here because it is the one the
/// schema editor performs; the per-column form is worth adding when a caller
/// needs it, and is noted rather than half-built.
///
/// - Important: the rebuild has a **destructive-change guard**. Dropping a
///   column that still holds row data is rejected with `400` and a
///   `propertiesWithData` array naming the columns; the caller must re-submit
///   with `force: true` to confirm the data loss. See `ListSchemaConflictDTO`.
public struct UpdateListSchemaRequest: Codable, Sendable, Equatable {
    public let schema: ListSchemaDSLDTO
    public let parentId: String?
    public let isPublic: Bool?

    public init(schema: ListSchemaDSLDTO, parentId: String? = nil, isPublic: Bool? = nil) {
        self.schema = schema
        self.parentId = parentId
        self.isPublic = isPublic
    }
}

/// The `400` body returned when a schema rebuild would drop a column that still
/// holds row data.
///
/// Modelled so the UI can name the columns and offer the confirmation, rather
/// than showing the user a bare "Bad Request" for what is really a question.
public struct ListSchemaConflictDTO: Codable, Sendable, Equatable {
    public let error: String?
    public let code: String?
    /// The column keys that still hold data.
    public let propertiesWithData: [String]?

    public init(error: String? = nil, code: String? = nil, propertiesWithData: [String]? = nil) {
        self.error = error
        self.code = code
        self.propertiesWithData = propertiesWithData
    }
}

// MARK: - Public browse

/// `GET /api/users/[username]/lists/[id]` → `{ "list": {…}, "ancestors": [] }`.
///
/// The `ancestors` array is the breadcrumb trail up the parent chain, which the
/// client has never had and which is the natural source for a "Lists ▸ Parent ▸
/// This" header on a public list page. It is modelled here so the information
/// stops being discarded at the wire; rendering it is a UI change for another
/// day.
public struct PublicListResponse: Codable, Sendable, Equatable {
    public let list: ListDTO
    public let ancestors: [ListParentDTO]?

    public init(list: ListDTO, ancestors: [ListParentDTO]? = nil) {
        self.list = list
        self.ancestors = ancestors
    }
}
