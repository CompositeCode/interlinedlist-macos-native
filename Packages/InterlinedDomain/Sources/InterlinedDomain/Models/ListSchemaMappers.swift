import Foundation
import InterlinedKit

// MARK: - Schema DSL object ⇄ domain
//
// The one place the wire's schema object and the domain's `ListSchema` meet
// (GitHub #85). Everything about the two-spellings problem is contained here:
// the server sends a column as `{key, type, label, …}` on the schema routes and
// as `{propertyKey, propertyType, propertyName, validationRules, …}` on the
// property projection, and `ListPropertyDTO.asSchemaField` funnels the second
// into the first so this file only ever sees one shape.

extension SchemaFieldValidation {

    /// Projects the wire's validation object, dropping `options` — those live
    /// on `SchemaField.enumValues` because they are a type-level fact about a
    /// `select` column, not a constraint the user edits alongside min/max.
    init?(dto: ListFieldValidationDTO?) {
        guard let dto else { return nil }
        let projected = SchemaFieldValidation(
            min: dto.min,
            max: dto.max,
            minLength: dto.minLength,
            maxLength: dto.maxLength,
            pattern: dto.pattern
        )
        // An object carrying nothing but `options` is not a validation rule set;
        // returning it would make every select column look constrained.
        if projected.isEmpty { return nil }
        self = projected
    }

    /// The wire form. `options` is supplied by the caller, which is the only
    /// place that knows whether the column is a `select`.
    func asDTO(options: [String]?) -> ListFieldValidationDTO? {
        let dto = ListFieldValidationDTO(
            min: min,
            max: max,
            minLength: minLength,
            maxLength: maxLength,
            pattern: pattern,
            options: options
        )
        // Never encode an empty rules object: the server reads it as "clear the
        // rules", so sending one on an untouched column would quietly erase
        // rules that were authored on the web.
        return dto.isEmpty ? nil : dto
    }
}

extension SchemaField {

    /// Projects one wire column.
    ///
    /// An unrecognised `type` token is **not** a decode failure — it maps to
    /// `.text`, the type whose editor can display any value without lying about
    /// it. Failing the whole schema because the server added a column type the
    /// client does not know yet would take out the entire list.
    init(dto: ListSchemaFieldDTO) {
        self.init(
            key: dto.key,
            label: dto.label ?? dto.key,
            type: SchemaFieldType(rawValue: dto.type) ?? .text,
            isRequired: dto.required,
            isVisible: dto.visible,
            displayOrder: dto.displayOrder,
            helpText: dto.helpText,
            placeholder: dto.placeholder,
            defaultValue: dto.defaultValue.map { ListCellValue(from: $0) },
            validation: SchemaFieldValidation(dto: dto.validation),
            enumValues: dto.resolvedOptions
        )
    }

    /// The wire form of this column.
    var asDTO: ListSchemaFieldDTO {
        // An empty string is not the same as an absent hint: sending `""` sets
        // the column's help text to an empty string, where omitting the key
        // leaves whatever is stored alone.
        let trimmedHelp = helpText.flatMap { $0.isEmpty ? nil : $0 }
        let trimmedPlaceholder = placeholder.flatMap { $0.isEmpty ? nil : $0 }
        // Spelled out rather than `.map(ListJSONValue.init(from:))`: that
        // reference is ambiguous against `Decodable.init(from:)`.
        let wireDefault: ListJSONValue? = defaultValue.map { ListJSONValue(from: $0) }

        return ListSchemaFieldDTO(
            key: key,
            type: type.rawValue,
            label: label,
            displayOrder: displayOrder,
            required: isRequired,
            visible: isVisible,
            helpText: trimmedHelp,
            placeholder: trimmedPlaceholder,
            defaultValue: wireDefault,
            validation: validation?.asDTO(options: enumValues),
            options: enumValues
        )
    }
}

extension ListSchema {

    /// Projects the schema object returned by `GET /api/lists/[id]/schema`.
    init(dto: ListSchemaDSLDTO) {
        self.init(fields: dto.fields.map(SchemaField.init(dto:)))
    }

    /// The wire form, for a create or a schema rebuild.
    ///
    /// - Parameter name: the schema's own `name`. The server accepts it and
    ///   uses it as the list description's sibling; passing the list title is
    ///   what the web does.
    func asDTO(name: String?, description: String? = nil) -> ListSchemaDSLDTO {
        ListSchemaDSLDTO(
            name: name,
            description: description,
            fields: orderedFields.map(\.asDTO)
        )
    }

    /// A one-line rendering of the columns, for the places that show a list's
    /// shape without opening the editor (the detail header, the Markdown
    /// export). Uses the client DSL spelling because that is what those surfaces
    /// already display.
    var dslDescription: String {
        SchemaDSL.serialize(self)
    }
}
