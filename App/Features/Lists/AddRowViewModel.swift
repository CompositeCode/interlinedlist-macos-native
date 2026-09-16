// AddRowViewModel
//
// Drives the Add Row sheet (GitHub #50).
//
// macOS had no add-row form at all: `ListRowsViewModel.addRow()` created an
// **empty** row and left the user to fill it in through the inspector. That is
// why the per-column metadata had nowhere to land — help text, placeholders and
// validation rules are about *entering* a value, and there was no entry point.
//
// Two behaviours the web documents explicitly, and both are easy to get wrong:
//
//  - **"Add another after saving" remembers your choice**, across lists and
//    across visits. The view owns that storage; this model just reads and
//    writes the flag.
//  - **A rejected save clears nothing.** The values stay in the form so the user
//    can fix and retry. That is the single most important rule here: a bulk
//    entry session that loses a row to a validation error is worse than one that
//    never offered the form.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class AddRowViewModel {

    private let lists: ListsServicing
    private let listId: String

    /// The columns to render, in the server's display order.
    let schema: ListSchema

    // MARK: - Observable state

    /// The working row. Keyed by column **key**, which is what the server
    /// expects and what `ListRow.fields` is subscripted by — not by label.
    private(set) var values: [String: ListCellValue] = [:]

    /// Client-side failures from the last save attempt, keyed by column key so
    /// each one renders against the field that caused it.
    private(set) var failures: [String: String] = [:]

    /// The surfaced error from a failed round-trip, as distinct from a local
    /// validation failure — one is the user's to fix, the other is not.
    private(set) var error: Error?

    private(set) var isSaving: Bool = false

    /// How many rows this session has added. The web shows a running
    /// confirmation, and it is the only feedback that a row went in when the
    /// form stays open.
    private(set) var savedCount: Int = 0

    /// Whether the sheet should stay open after a successful save.
    var addAnotherAfterSaving: Bool

    /// True once the caller should dismiss — a successful save with
    /// "add another" off.
    private(set) var didFinish: Bool = false

    /// Set when a row was just saved and the form was emptied for the next one,
    /// so the view can move focus back to the first field.
    private(set) var shouldRefocusFirstField: Bool = false

    // MARK: - Init

    init(
        lists: ListsServicing,
        listId: String,
        schema: ListSchema,
        addAnotherAfterSaving: Bool
    ) {
        self.lists = lists
        self.listId = listId
        self.schema = schema
        self.addAnotherAfterSaving = addAnotherAfterSaving
        self.values = Self.defaults(for: schema)
    }

    /// The starting values: a column's `defaultValue` where the server supplies
    /// one, nothing otherwise.
    ///
    /// Applying the defaults matters for a `select` with a `defaultValue` — the
    /// web opens on it, and a blank picker would make a required column look
    /// unfilled when the server would have filled it.
    private static func defaults(for schema: ListSchema) -> [String: ListCellValue] {
        var seeded: [String: ListCellValue] = [:]
        for field in schema.fields {
            if let value = field.defaultValue { seeded[field.key] = value }
        }
        return seeded
    }

    // MARK: - Intents

    func setValue(_ value: ListCellValue, forKey key: String) {
        values[key] = value
        // Clear this field's failure as soon as it is edited: leaving a stale
        // red message under a field the user has just fixed teaches them to
        // ignore it.
        failures[key] = nil
    }

    func value(forKey key: String) -> ListCellValue {
        values[key] ?? .null
    }

    /// Validates and saves.
    ///
    /// Local validation runs first and, on failure, **no service call is made** —
    /// the rules are the server's and it would reject the same row, so spending
    /// a round-trip to be told what we already know costs the user time and
    /// tells them less (a 400 cannot say which column was wrong).
    func save() async {
        guard !isSaving else { return }
        error = nil

        let localFailures = RowValueValidator.failures(forRow: values, schema: schema)
        guard localFailures.isEmpty else {
            failures = Dictionary(
                uniqueKeysWithValues: localFailures.map { ($0.key, $0.message) }
            )
            return
        }
        failures = [:]

        isSaving = true
        defer { isSaving = false }
        do {
            // Empty cells are omitted rather than sent as null: an absent key
            // lets the server apply its own default, where an explicit null
            // asks it to store nothing.
            let payload = values.filter { !isBlank($0.value) }
            _ = try await lists.createRow(listId: listId, data: payload)
            savedCount += 1

            if addAnotherAfterSaving {
                // The form empties and stays open. The values are discarded only
                // because the save *succeeded* — the failure path below keeps
                // every one of them.
                values = Self.defaults(for: schema)
                shouldRefocusFirstField = true
            } else {
                didFinish = true
            }
        } catch {
            // Deliberately does not touch `values`. A rejected save clearing the
            // form is the failure this whole sheet exists to avoid.
            self.error = error
        }
    }

    /// Acknowledges the refocus request, so it fires once per save rather than
    /// on every view update.
    func consumeRefocusRequest() {
        shouldRefocusFirstField = false
    }

    private func isBlank(_ value: ListCellValue) -> Bool {
        switch value {
        case .null: return true
        case .string(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return false
        }
    }
}
