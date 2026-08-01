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
        var name: String
        var type: SchemaFieldType
        var nullable: Bool
        /// Ordered option set for `select` columns. Ignored for every other
        /// type. Kept as `[String]` (not `Set`) so declaration order — which
        /// the picker preserves — is authoritative.
        var options: [String]

        init(
            id: UUID = UUID(),
            name: String,
            type: SchemaFieldType,
            nullable: Bool = false,
            options: [String] = []
        ) {
            self.id = id
            self.name = name
            self.type = type
            self.nullable = nullable
            self.options = options
        }
    }

    /// Editable fields, in display order.
    var fields: [EditableField] = []

    /// True while a save round-trip is in flight.
    private(set) var isSaving: Bool = false

    /// Surfaced error from the most recent failed save.
    private(set) var error: Error?

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
        self.fields = initialSchema.fields.map {
            EditableField(
                name: $0.name,
                type: $0.type,
                nullable: $0.nullable ?? false,
                options: $0.enumValues ?? []
            )
        }
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

        let schema = ListSchema(fields: fields.map { field in
            SchemaField(
                name: field.name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: field.type,
                nullable: field.nullable,
                // Only `select` carries options into the DSL; every other
                // type serializes as a bare token.
                enumValues: field.type.carriesOptions
                    ? field.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    : nil
            )
        })
        do {
            let saved = try await lists.updateSchema(of: listId, schema: schema)
            eventBus.post(.schemaChanged(listId: listId, schema: saved))
            didFinish = true
        } catch {
            self.error = error
        }
    }
}
