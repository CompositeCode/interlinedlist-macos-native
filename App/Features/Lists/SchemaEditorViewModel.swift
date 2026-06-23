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

        init(id: UUID = UUID(), name: String, type: SchemaFieldType, nullable: Bool = false) {
            self.id = id
            self.name = name
            self.type = type
            self.nullable = nullable
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
            EditableField(name: $0.name, type: $0.type, nullable: $0.nullable ?? false)
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
    /// view model.
    func setType(_ type: SchemaFieldType, forFieldID id: UUID) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        fields[index].type = type
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

        let schema = ListSchema(fields: fields.map {
            SchemaField(
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: $0.type,
                nullable: $0.nullable
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
