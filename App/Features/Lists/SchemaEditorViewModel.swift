// SchemaEditorViewModel
//
// Drives `SchemaEditorView` — the per-field form builder for a list's
// schema (PLAN.md §6 M3 schema editor, user's plan answer: per-field
// form builder, no DSL textarea). Owns the editable field array,
// per-row validation, reordering, and the save flow through
// `ListsServicing.updateSchema`.
//
// Save emits a `ListsEvent.schemaChanged` so any open rows table
// reloads its columns. The Wave 3 optimistic-UI pattern does not
// apply here: schemas are write-replace, not a small mutation, so
// the view shows a save spinner instead.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class SchemaEditorViewModel {

    private let lists: ListsServicing
    private let eventBus: ListsEventBus
    let listId: String
    /// The caller's role on this list (loaded by the parent view).
    /// `.owner` allows full editing; `.editor` is treated as read-only
    /// here because per the working role taxonomy assumption editors
    /// cannot edit schema (see `WatcherRole`'s file-level note and
    /// `/API-backend-prompts-to-build.md` item 1.2). Anything else
    /// is also read-only.
    let role: WatcherRole

    /// One editable row. Identity is by `UUID` so adding a new
    /// unnamed row does not clash with the schema's name-based id.
    struct EditableField: Identifiable, Equatable {
        let id: UUID

        /// The column's **key** — what `ListRow.fields` is subscripted by.
        ///
        /// Held separately from `name` because the server does
        /// (`propertyKey` vs `propertyName`). A schema authored on the web can
        /// have a key of `year` under a label of "Publication Year", and
        /// rewriting the key from the label on a macOS save would orphan every
        /// stored cell in that column.
        ///
        /// Empty for a field the user has just added — `SchemaEditorViewModel`
        /// derives a key from the name at save time, which is the DSL's own
        /// key-equals-label convention and the only sane default for a column
        /// that has never existed.
        var key: String

        /// The column's display label.
        var name: String
        var type: SchemaFieldType
        var nullable: Bool
        /// Ordered option set for `select` columns. Ignored for every other
        /// type. Kept as `[String]` (not `Set`) so declaration order — which
        /// the picker preserves — is authoritative.
        var options: [String]

        // MARK: Per-column metadata (GitHub #50)
        //
        // The server has stored all of this since the schema routes shipped; no
        // client ever read or wrote it. `work-consolidation.md` P2-G listed the
        // encoding as API-unconfirmed, which is what blocked this — it is
        // confirmed now, and it turned out not to be DSL syntax at all but
        // first-class fields (see docs/spikes/list-schema-wire-shapes.md).

        /// Hint shown under the field in the row form.
        var helpText: String

        /// Placeholder for an empty field.
        var placeholder: String

        /// Whether the column is shown. A hidden column keeps its data — this
        /// is emphatically not deletion, and the editor says so.
        var isVisible: Bool

        /// Minimum / maximum for `number` columns. Strings, not `Double?`, so a
        /// half-typed "-" or "1." does not evaporate under the user's cursor;
        /// parsed at validation time.
        var minValue: String
        var maxValue: String

        /// Minimum / maximum character count for text-family columns.
        var minLength: String
        var maxLength: String

        /// A regular expression the value must match.
        ///
        /// Sent verbatim and **never evaluated client-side**: it is a
        /// server-side expression, and pre-validating it against a different
        /// regex engine would let this client reject a value the server accepts.
        var pattern: String

        init(
            id: UUID = UUID(),
            key: String = "",
            name: String,
            type: SchemaFieldType,
            nullable: Bool = false,
            options: [String] = [],
            helpText: String = "",
            placeholder: String = "",
            isVisible: Bool = true,
            minValue: String = "",
            maxValue: String = "",
            minLength: String = "",
            maxLength: String = "",
            pattern: String = ""
        ) {
            self.id = id
            self.key = key
            self.name = name
            self.type = type
            self.nullable = nullable
            self.options = options
            self.helpText = helpText
            self.placeholder = placeholder
            self.isVisible = isVisible
            self.minValue = minValue
            self.maxValue = maxValue
            self.minLength = minLength
            self.maxLength = maxLength
            self.pattern = pattern
        }

        /// The key to send: the stored one when the column already exists,
        /// otherwise the label, which is the DSL's key-equals-label convention.
        var resolvedKey: String {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedKey.isEmpty else { return trimmedKey }
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// The validation rules as the domain models them, or `nil` when none
        /// are set.
        ///
        /// `nil` rather than an empty object matters: the server reads an empty
        /// rules object as *clear the rules*, so an untouched column must send
        /// nothing at all.
        var validation: SchemaFieldValidation? {
            let rules = SchemaFieldValidation(
                min: type == .number ? Double(minValue.trimmingCharacters(in: .whitespaces)) : nil,
                max: type == .number ? Double(maxValue.trimmingCharacters(in: .whitespaces)) : nil,
                minLength: type.acceptsLengthRules ? Int(minLength.trimmingCharacters(in: .whitespaces)) : nil,
                maxLength: type.acceptsLengthRules ? Int(maxLength.trimmingCharacters(in: .whitespaces)) : nil,
                pattern: {
                    let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }()
            )
            return rules.isEmpty ? nil : rules
        }
    }

    /// Editable fields, in display order.
    var fields: [EditableField] = []

    /// True while a save round-trip is in flight.
    private(set) var isSaving: Bool = false

    /// Surfaced error from the most recent failed save.
    private(set) var error: Error?

    /// The schema the server refused as destructive, held so the user can
    /// confirm it. Non-nil is what the view binds a confirmation dialog to.
    private(set) var pendingDestructiveSave: ListSchema?

    /// Set to `true` after a successful save; the view dismisses.
    private(set) var didFinish: Bool = false

    /// Whether the editor accepts edits. Hidden by the view when
    /// `false` so the user can still inspect the schema but not
    /// mutate it.
    var isEditable: Bool {
        role == .owner
    }

    init(
        lists: ListsServicing,
        eventBus: ListsEventBus,
        listId: String,
        role: WatcherRole,
        initialSchema: ListSchema
    ) {
        self.lists = lists
        self.eventBus = eventBus
        self.listId = listId
        self.role = role
        // Ordered by `displayOrder` when the server supplied it, so the editor
        // opens on the same column order the table renders.
        self.fields = initialSchema.orderedFields.map { field in
            EditableField(
                // The stored key is carried, not re-derived from the label. A
                // web-authored column can have a key of `year` under a label of
                // "Publication Year"; rewriting the key on a macOS save would
                // orphan every stored cell in that column.
                key: field.key,
                name: field.label,
                type: field.type,
                nullable: field.nullable ?? false,
                options: field.enumValues ?? [],
                helpText: field.helpText ?? "",
                placeholder: field.placeholder ?? "",
                isVisible: field.isVisible ?? true,
                minValue: field.validation?.min.map { Self.numberText($0) } ?? "",
                maxValue: field.validation?.max.map { Self.numberText($0) } ?? "",
                minLength: field.validation?.minLength.map(String.init) ?? "",
                maxLength: field.validation?.maxLength.map(String.init) ?? "",
                pattern: field.validation?.pattern ?? ""
            )
        }
    }

    /// Renders a numeric bound for a text field without a spurious ".0" on a
    /// whole number — the overwhelmingly common case for a min/max.
    static func numberText(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int(value))
            : String(value)
    }

    // MARK: - Intents

    /// Appends a new empty field. The view focuses the name input on
    /// the new row.
    func addField() {
        fields.append(EditableField(name: "", type: .text))
    }

    /// Removes a field by its row id.
    func removeField(id: UUID) {
        fields.removeAll { $0.id == id }
    }

    /// Moves a field from one index to another. Bound to SwiftUI's
    /// `List.onMove`. `IndexSet` source is the standard SwiftUI shape.
    func moveFields(from source: IndexSet, to destination: Int) {
        fields.move(fromOffsets: source, toOffset: destination)
    }

    /// Sets the type of a field by row id. Convenience used by the
    /// view's per-row Picker so the binding is one-way through the
    /// view model. Switching away from `select` discards its options so a
    /// later switch back starts clean and a non-select never carries a
    /// stale option set into `save()`.
    func setType(_ type: SchemaFieldType, forFieldID id: UUID) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        fields[index].type = type
        if !type.carriesOptions {
            fields[index].options = []
        }
    }

    /// Appends a new empty option to a `select` field. The view focuses the
    /// new option's text field for editing.
    func addOption(toFieldID id: UUID) {
        guard let index = fields.firstIndex(where: { $0.id == id }),
              fields[index].type.carriesOptions else { return }
        fields[index].options.append("")
    }

    /// Removes the option at `offset` from a `select` field.
    func removeOption(fromFieldID id: UUID, at offset: Int) {
        guard let index = fields.firstIndex(where: { $0.id == id }),
              fields[index].options.indices.contains(offset) else { return }
        fields[index].options.remove(at: offset)
    }

    /// Sets the text of a single option by index. Bound one-way from the
    /// per-option text field so the array stays owned by the view model.
    func setOption(_ value: String, forFieldID id: UUID, at offset: Int) {
        guard let index = fields.firstIndex(where: { $0.id == id }),
              fields[index].options.indices.contains(offset) else { return }
        fields[index].options[offset] = value
    }

    /// Validates a single field. Returns `nil` when valid, otherwise
    /// a short error string the view renders inline.
    func validationError(for field: EditableField) -> String? {
        let trimmed = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Name is required."
        }
        if trimmed.contains(",") || trimmed.contains(":") {
            return "Name cannot contain ‘,’ or ‘:’."
        }
        let duplicates = fields.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }
        if duplicates.count > 1 {
            return "Duplicate field name."
        }
        if field.type.carriesOptions {
            return selectOptionError(for: field)
        }
        return ruleError(for: field)
    }

    /// Validates the per-column rules (GitHub #50).
    ///
    /// Only rules that are **self-contradictory** are rejected. A bound the
    /// server might disagree with is not the client's business — the rules are
    /// enforced server-side, and second-guessing them here would refuse schemas
    /// the platform accepts.
    ///
    /// The `pattern` is deliberately not compiled or tested: it is a
    /// server-side regular expression, and validating it against
    /// `NSRegularExpression` would reject syntax the server's engine accepts.
    private func ruleError(for field: EditableField) -> String? {
        if field.type.acceptsRangeRules {
            let min = field.minValue.trimmingCharacters(in: .whitespaces)
            let max = field.maxValue.trimmingCharacters(in: .whitespaces)
            if !min.isEmpty, Double(min) == nil { return "Min must be a number." }
            if !max.isEmpty, Double(max) == nil { return "Max must be a number." }
            if let lower = Double(min), let upper = Double(max), lower > upper {
                return "Min can’t be greater than max."
            }
        }
        if field.type.acceptsLengthRules {
            let min = field.minLength.trimmingCharacters(in: .whitespaces)
            let max = field.maxLength.trimmingCharacters(in: .whitespaces)
            if !min.isEmpty, Int(min) == nil { return "Min length must be a whole number." }
            if !max.isEmpty, Int(max) == nil { return "Max length must be a whole number." }
            if let lower = Int(min), lower < 0 { return "Min length can’t be negative." }
            if let upper = Int(max), upper < 1 { return "Max length must be at least 1." }
            if let lower = Int(min), let upper = Int(max), lower > upper {
                return "Min length can’t be greater than max length."
            }
        }
        return nil
    }

    /// Validates a `select` field's option set, mirroring the DSL parser's
    /// `.emptySelectOptions` / `.duplicateSelectOption` rules so the editor
    /// rejects the same inputs the serializer would round-trip into an
    /// invalid schema. Returns `nil` when the options are valid.
    private func selectOptionError(for field: EditableField) -> String? {
        let trimmedOptions = field.options.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmedOptions.isEmpty || trimmedOptions.contains(where: \.isEmpty) {
            return "Select needs at least one non-empty option."
        }
        if Set(trimmedOptions).count != trimmedOptions.count {
            return "Select options must be unique."
        }
        return nil
    }

    /// Whether the whole form passes validation.
    var isValid: Bool {
        guard !fields.isEmpty else { return false }
        for field in fields where validationError(for: field) != nil {
            return false
        }
        return true
    }

    /// Saves the schema. Validates locally first; on `false` bails
    /// without calling the service so the gated entitlement error
    /// path is reserved for what it actually means.
    func save() async {
        guard isValid, !isSaving, isEditable else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }

        let schema = ListSchema(fields: fields.enumerated().map { index, field in
            SchemaField(
                key: field.resolvedKey,
                label: field.name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: field.type,
                isRequired: !field.nullable,
                isVisible: field.isVisible,
                // The editor's row order is the column order; sending it
                // explicitly means a reorder sticks rather than depending on the
                // server preserving array order.
                displayOrder: index,
                helpText: field.helpText.trimmingCharacters(in: .whitespacesAndNewlines),
                placeholder: field.placeholder.trimmingCharacters(in: .whitespacesAndNewlines),
                validation: field.validation,
                // Only `select` carries options; every other type sends none.
                enumValues: field.type.carriesOptions
                    ? field.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    : nil
            )
        })
        do {
            let saved = try await lists.updateSchema(
                of: listId,
                schema: schema,
                // Never force on the first attempt. Dropping a column that still
                // holds data is a question for the user, not a default — the
                // server asks it, and `confirmDestructiveSave()` is how the
                // answer gets back.
                force: false
            )
            eventBus.post(.schemaChanged(listId: listId, schema: saved))
            didFinish = true
        } catch let listsError as ListsError {
            if case .schemaChangeWouldLoseData = listsError {
                pendingDestructiveSave = schema
            }
            self.error = listsError
        } catch {
            self.error = error
        }
    }

    /// Re-submits the schema the server refused, confirming the data loss.
    ///
    /// Only reachable after `save()` has surfaced
    /// `ListsError.schemaChangeWouldLoseData`, so there is no path that forces a
    /// destructive change without the server having asked first.
    func confirmDestructiveSave() async {
        guard let schema = pendingDestructiveSave, !isSaving else { return }
        isSaving = true
        error = nil
        pendingDestructiveSave = nil
        defer { isSaving = false }

        do {
            let saved = try await lists.updateSchema(of: listId, schema: schema, force: true)
            eventBus.post(.schemaChanged(listId: listId, schema: saved))
            didFinish = true
        } catch {
            self.error = error
        }
    }
}
