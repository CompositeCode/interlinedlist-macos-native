// ListDetailViewModel
//
// Drives `ListDetailView`: loads a single public list's metadata plus
// paged rows. Reads through `ListsServicing` only — no direct API or
// cache access — so unit tests substitute a stub service (PLAN.md §3,
// §7).
//
// M1 keeps the row shape loose (`[String: ListCellValue]`). The
// typed-per-column schema editor and full Table-with-typed-columns
// land in M3 alongside the schema DSL parser (PLAN.md §6 M3, §7
// "Schema DSL parser").

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ListDetailViewModel {

    // MARK: - Configuration

    /// Page size for both the initial row load and infinite scroll.
    /// Larger than the timeline default because rows are denser than
    /// messages and a typical list fits a few dozen rows per fetch.
    static let pageSize: Int = 50

    private let lists: ListsServicing
    private let username: String
    private let slug: String

    // MARK: - Observable state

    /// The list's metadata (title, description, schema string). `nil`
    /// before the first successful load.
    private(set) var detail: ListDetail?

    /// Rows loaded so far, in display order.
    private(set) var rows: [ListRow] = []

    /// True while a network round-trip is in flight (initial load,
    /// refresh, or load-more).
    private(set) var isLoading: Bool = false

    /// Surfaced error from the most recent failed load. Cleared on the
    /// next successful round-trip.
    private(set) var error: Error?

    /// Whether the server reports more pages beyond what's loaded.
    private(set) var hasMore: Bool = false

    /// The `offset` to pass on the next `loadMore` call. `nil` when
    /// `hasMore` is false.
    private(set) var nextOffset: Int?

    // MARK: - Init

    init(lists: ListsServicing, username: String, slug: String) {
        self.lists = lists
        self.username = username
        self.slug = slug
    }

    // MARK: - Intents

    /// Loads the list metadata and the first page of rows in parallel.
    /// Either failure surfaces as `error` and the other half is still
    /// populated when it succeeds — partial results beat an empty
    /// detail screen.
    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        async let detailResult = loadDetail()
        async let rowsResult = loadFirstRowsPage()

        let (loadedDetail, loadedPage) = await (detailResult, rowsResult)

        if let loadedDetail { self.detail = loadedDetail }
        if let loadedPage {
            self.rows = loadedPage.rows
            self.hasMore = loadedPage.hasMore
            self.nextOffset = loadedPage.nextOffset
        }
    }

    /// Re-fetches both halves; bound to the detail view's
    /// `.refreshable` modifier.
    func refresh() async {
        await load()
    }

    /// Appends the next page of rows when one exists. No-op while a
    /// load is in flight or when `hasMore` is false.
    func loadMore() async {
        guard !isLoading, hasMore, let offset = nextOffset else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await lists.publicRows(
                username: username,
                slug: slug,
                limit: Self.pageSize,
                offset: offset
            )
            rows.append(contentsOf: page.rows)
            hasMore = page.hasMore
            nextOffset = page.nextOffset
            error = nil
        } catch {
            self.error = error
        }
    }

    // MARK: - Derived

    /// Stable column order derived from the loaded rows' field keys.
    /// We sort alphabetically so the rendering is deterministic across
    /// renders; the schema-defined column order lands in M3 with the
    /// DSL parser.
    var columns: [String] {
        guard !rows.isEmpty else { return [] }
        var seen = Set<String>()
        var ordered: [String] = []
        for row in rows {
            for key in row.fields.keys where !seen.contains(key) {
                seen.insert(key)
                ordered.append(key)
            }
        }
        return ordered.sorted()
    }

    // MARK: - Internals

    private func loadDetail() async -> ListDetail? {
        do {
            return try await lists.publicList(username: username, slug: slug)
        } catch {
            self.error = error
            return nil
        }
    }

    private func loadFirstRowsPage() async -> RowsPage? {
        do {
            return try await lists.publicRows(
                username: username,
                slug: slug,
                limit: Self.pageSize,
                offset: 0
            )
        } catch {
            // Don't clobber a detail-load error with a rows-load error
            // — the first failure is the more actionable one.
            if self.error == nil { self.error = error }
            return nil
        }
    }
}
