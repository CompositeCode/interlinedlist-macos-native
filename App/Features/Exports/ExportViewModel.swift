// ExportViewModel
//
// View model for the M7 CSV Export sheet (PLAN.md §1 "Data Exports",
// §6 M7). Drives `ExportView`'s export-type list and the SwiftUI
// `.fileExporter` save-panel flow.
//
// Owned pattern: `export(_:)` is a fire-and-forget method that sets
// `isExporting` to gate rapid re-taps, calls the appropriate service
// method, and surfaces the result as `pendingExport` (non-nil → the
// view triggers the `.fileExporter` dialog). The view resets
// `pendingExport` to `nil` after the save panel resolves.
//
// Per Decision 0003 this file imports `InterlinedDomain` only.

import Foundation
import InterlinedDomain

@Observable @MainActor final class ExportViewModel {

    // MARK: - ExportType

    enum ExportType: String, CaseIterable, Identifiable {
        case messages    = "My Posts"
        case lists       = "My Lists"
        case listDataRows = "List Data Rows"
        case follows     = "Follows"

        var id: String { rawValue }

        /// Short description shown alongside the type name in the export row.
        var exportDescription: String {
            switch self {
            case .messages:     return "All posts you have created"
            case .lists:        return "All lists you own"
            case .listDataRows: return "Row data across all your lists"
            case .follows:      return "Your follower and following relationships"
            }
        }

        /// Default filename stem (no extension) for the save panel.
        var defaultFilename: String {
            switch self {
            case .messages:     return "interlinedlist-posts"
            case .lists:        return "interlinedlist-lists"
            case .listDataRows: return "interlinedlist-list-data-rows"
            case .follows:      return "interlinedlist-follows"
            }
        }
    }

    // MARK: - Published state

    /// `true` while an export network call is in flight. Gates re-tapping
    /// and drives the ProgressView overlay.
    var isExporting: Bool = false

    /// Set to the type whose export is currently in progress (or just
    /// completed). Used to supply the `defaultFilename` to `.fileExporter`.
    var activeExport: ExportType? = nil

    /// Non-nil when a completed export is waiting to be saved. The view
    /// presents the `.fileExporter` dialog while this is non-nil and
    /// clears it when the dialog resolves (success or cancel).
    var pendingExport: CSVExport? = nil

    /// A rendered Markdown export waiting to be saved (feature-gaps.md §1.3).
    /// The `/api/exports/*` endpoints are CSV-only, so Markdown is composed
    /// client-side from domain models via `MarkdownExporter` (see
    /// `feature-blockages.md` P2-F for the server-side ask). Drives a second
    /// `.fileExporter` in the view.
    var pendingMarkdownExport: MarkdownExport? = nil

    /// A rendered Markdown document plus the filename stem for the save panel.
    struct MarkdownExport: Equatable {
        let filename: String
        let text: String
    }

    /// Non-nil when a service call failed. Displayed as an amber-tinted
    /// banner in `ExportView`. Cleared at the start of the next export
    /// attempt.
    var errorMessage: String? = nil

    // MARK: - Init

    private let exportsService: ExportsServicing
    private let lists: ListsServicing
    private let markdownExporter = MarkdownExporter()

    /// Page sizes for the bulk Markdown-lists fetch. Kept modest so a large
    /// account paginates rather than requesting everything at once.
    private static let listsPageSize = 50
    private static let rowsPageSize = 100

    init(exportsService: ExportsServicing, lists: ListsServicing) {
        self.exportsService = exportsService
        self.lists = lists
    }

    // MARK: - Intent

    /// Kicks off an export for `type`. No-op while another export is
    /// already in flight (`isExporting == true`).
    ///
    /// On success, `pendingExport` becomes non-nil and the view triggers
    /// the SwiftUI save panel. On failure, `errorMessage` is populated and
    /// `isExporting` is cleared.
    func export(_ type: ExportType) {
        guard !isExporting else { return }
        isExporting = true
        activeExport = type
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isExporting = false }
            do {
                let result: CSVExport
                switch type {
                case .messages:
                    result = try await exportsService.exportMessages()
                case .lists:
                    result = try await exportsService.exportLists()
                case .listDataRows:
                    result = try await exportsService.exportListDataRows()
                case .follows:
                    result = try await exportsService.exportFollows()
                }
                pendingExport = result
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Exports all of the user's owned lists as a single Markdown document
    /// ("structured table conversion" — feature-gaps.md §1.3). Fetches every
    /// owned list and its rows client-side (the export API is CSV-only), then
    /// renders them with `MarkdownExporter`. No-op while another export is in
    /// flight. On success `pendingMarkdownExport` becomes non-nil and the view
    /// triggers the save panel; on failure `errorMessage` is populated.
    func exportListsAsMarkdown() {
        guard !isExporting else { return }
        isExporting = true
        activeExport = .lists
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isExporting = false }
            do {
                let inputs = try await self.collectListInputs()
                let text = self.markdownExporter.markdown(forLists: inputs)
                self.pendingMarkdownExport = MarkdownExport(
                    filename: "interlinedlist-lists",
                    text: text
                )
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Pages through every owned list, pairing each with its fully-paginated
    /// rows, and projects them into `MarkdownExporter.ListInput` values.
    private func collectListInputs() async throws -> [MarkdownExporter.ListInput] {
        var inputs: [MarkdownExporter.ListInput] = []
        var offset = 0
        while true {
            let page = try await lists.myLists(limit: Self.listsPageSize, offset: offset)
            for list in page.lists {
                let rows = try await collectRows(listId: list.id)
                inputs.append(
                    MarkdownExporter.ListInput(
                        title: list.title,
                        description: list.description,
                        schemaDSL: list.schemaDescription,
                        rows: rows
                    )
                )
            }
            // Stop when the server reports no more pages, or when the cursor
            // fails to advance (defensive: never spin on a stuck offset).
            guard page.hasMore, let next = page.nextOffset, next > offset else { break }
            offset = next
        }
        return inputs
    }

    /// Pages through every row of one owned list.
    private func collectRows(listId: String) async throws -> [ListRow] {
        var rows: [ListRow] = []
        var offset = 0
        while true {
            let page = try await lists.rows(of: listId, limit: Self.rowsPageSize, offset: offset)
            rows.append(contentsOf: page.rows)
            guard page.hasMore, let next = page.nextOffset, next > offset else { break }
            offset = next
        }
        return rows
    }
}
