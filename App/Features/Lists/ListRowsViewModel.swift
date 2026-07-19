// ListRowsViewModel
//
// Drives `ListRowsView` — the M3 typed-rows table for an owned list
// (PLAN.md §6 M3 rows table). Owns the loaded schema, the loaded
// rows, the current view mode (table vs. card), selection, paging,
// and row CRUD. Reads through `ListsServicing` only.
//
// The Wave 3 optimistic-UI pattern applies to row mutations: insert
// a temporary row immediately, call the service, then replace the
// optimistic copy with the service's authoritative return (id and
// all). On failure, restore the snapshot and surface the error.
//
// Schema changes (from the schema editor in another window) and
// row writes (from a different open instance of the rows table)
// arrive via the `ListsEventBus` subscription.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ListRowsViewModel {

    enum ViewMode: Sendable, Equatable, Hashable {
        case table
        case cards
    }

    // MARK: - Configuration

    static let pageSize: Int = 50

    private let lists: ListsServicing
    private let eventBus: ListsEventBus
    let listId: String

    // MARK: - Observable state

    private(set) var schema: ListSchema = .empty
    private(set) var rows: [ListRow] = []
    var selectedRowID: String?
    var viewMode: ViewMode = .table
    private(set) var isLoading: Bool = false
    private(set) var error: Error?
    private(set) var hasMore: Bool = false
    private(set) var nextOffset: Int?
    /// Set of row IDs whose writes are in flight. De-bounces rapid edits.
    private var pendingWrites: Set<String> = []

    /// The columns the table renders. Driven by `schema.fields` when
    /// non-empty; falls back to the union of observed row keys when
    /// the list has no schema yet (so the table still shows something
    /// useful for schema-less lists).
    var columns: [String] {
        if !schema.fields.isEmpty { return schema.fields.map(\.name) }
        var seen: Set<String> = []
        var ordered: [String] = []
        for row in rows {
            for key in row.fields.keys where seen.insert(key).inserted {
                ordered.append(key)
            }
        }
        return ordered.sorted()
    }

    /// Currently selected row, if any.
    var selectedRow: ListRow? {
        guard let selectedRowID else { return nil }
        return rows.first { $0.id == selectedRowID }
    }

    // MARK: - Init

    init(lists: ListsServicing, eventBus: ListsEventBus, listId: String) {
        self.lists = lists
        self.eventBus = eventBus
        self.listId = listId
    }

    // MARK: - Loading

    /// First-time load: fetch the schema and the first page of rows.
    /// Schema failures degrade to an empty schema (the columns will
    /// fall back to observed-row keys) so the rows still render.
    func initialLoad() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            schema = try await lists.schema(of: listId)
        } catch {
            // Tolerate malformed-schema errors: log via the error
            // surface but keep the empty schema so rows render.
            self.error = error
            schema = .empty
        }
        do {
            let page = try await lists.rows(of: listId, limit: Self.pageSize, offset: 0)
            rows = page.rows
            hasMore = page.hasMore
            nextOffset = page.nextOffset
            error = nil
        } catch {
            self.error = error
        }
    }

    /// Appends the next page when one exists.
    func loadMore() async {
        guard !isLoading, hasMore, let offset = nextOffset else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await lists.rows(of: listId, limit: Self.pageSize, offset: offset)
            rows.append(contentsOf: page.rows)
            hasMore = page.hasMore
            nextOffset = page.nextOffset
            error = nil
        } catch {
            self.error = error
        }
    }

    // MARK: - Row CRUD

    /// Adds a new empty row. Optimistic-insert with a placeholder id,
    /// then replace with the server's row.
    func addRow() async {
        let placeholderID = "tmp-" + UUID().uuidString
        let snapshot = rows
        let optimistic = ListRow(id: placeholderID, listID: listId, fields: [:])
        rows.append(optimistic)
        pendingWrites.insert(placeholderID)
        defer { pendingWrites.remove(placeholderID) }

        do {
            let saved = try await lists.createRow(listId: listId, data: [:])
            // Replace optimistic with confirmed.
            if let index = rows.firstIndex(where: { $0.id == placeholderID }) {
                rows[index] = saved
            }
            selectedRowID = saved.id
            eventBus.post(.rowCreated(listId: listId, row: saved))
            error = nil
        } catch {
            rows = snapshot
            self.error = error
        }
    }

    /// Patches a row's field values. Optimistic-replace with the new
    /// fields, then replace with the service's authoritative return.
    func updateRow(id: String, fields: [String: ListCellValue]) async {
        guard !pendingWrites.contains(id),
              let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let original = rows[index]
        let optimistic = ListRow(
            id: id,
            listID: original.listID,
            fields: fields,
            createdAt: original.createdAt,
            updatedAt: original.updatedAt
        )
        rows[index] = optimistic
        pendingWrites.insert(id)
        defer { pendingWrites.remove(id) }
        do {
            let saved = try await lists.updateRow(listId: listId, rowId: id, data: fields)
            if let currentIndex = rows.firstIndex(where: { $0.id == id }) {
                rows[currentIndex] = saved
            }
            eventBus.post(.rowUpdated(listId: listId, row: saved))
            error = nil
        } catch {
            if let rollbackIndex = rows.firstIndex(where: { $0.id == id }) {
                rows[rollbackIndex] = original
            }
            self.error = error
        }
    }

    /// Deletes the rows whose ids are in `ids`. Optimistic-remove,
    /// then call the service; on failure restore the snapshot.
    func deleteRows(ids: Set<String>) async {
        guard !ids.isEmpty else { return }
        let snapshot = rows
        rows.removeAll { ids.contains($0.id) }
        if let selectedRowID, ids.contains(selectedRowID) {
            self.selectedRowID = nil
        }
        do {
            for id in ids {
                try await lists.deleteRow(listId: listId, rowId: id)
                eventBus.post(.rowDeleted(listId: listId, rowId: id))
            }
            error = nil
        } catch {
            rows = snapshot
            self.error = error
        }
    }

    // MARK: - Cell parsing helpers

    /// Parses a user-typed string into a typed `ListCellValue` based on
    /// the column's declared type. Boundary inputs (empty / whitespace)
    /// always project as `.null` so a cleared cell stays cleared. Invalid
    /// input for typed cells falls back to `.string` (the wire shape
    /// the API will accept regardless) — the inline error UI on the cell
    /// surfaces the parse failure to the user.
    static func parse(_ input: String, as type: SchemaFieldType) -> ListCellValue {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .null }
        switch type {
        case .text, .url, .email, .date, .select, .markdown:
            // `select` stores the chosen option's raw text; `markdown`
            // stores raw Markdown source. Both are string-valued cells —
            // the option-set constraint is enforced by the picker UI, not
            // here (this helper also drives free-text entry).
            return .string(trimmed)
        case .number:
            if let intValue = Int(trimmed) { return .int(intValue) }
            if let doubleValue = Double(trimmed) { return .double(doubleValue) }
            return .string(trimmed)
        case .boolean:
            switch trimmed.lowercased() {
            case "true", "yes", "1": return .bool(true)
            case "false", "no", "0": return .bool(false)
            default: return .string(trimmed)
            }
        }
    }

    // MARK: - Event-bus consumption

    /// Applies a `ListsEvent`. Pure local mutation.
    func apply(event: ListsEvent) {
        switch event {
        case .schemaChanged(let id, let schema) where id == listId:
            self.schema = schema
        case .rowCreated(let id, let row) where id == listId:
            if !rows.contains(where: { $0.id == row.id }) {
                rows.append(row)
            }
        case .rowUpdated(let id, let row) where id == listId:
            if let index = rows.firstIndex(where: { $0.id == row.id }) {
                rows[index] = row
            }
        case .rowDeleted(let id, let rowId) where id == listId:
            rows.removeAll { $0.id == rowId }
            if selectedRowID == rowId { selectedRowID = nil }
        case .listDeleted(let id) where id == listId:
            rows = []
            schema = .empty
            selectedRowID = nil
        default:
            break
        }
    }
}
