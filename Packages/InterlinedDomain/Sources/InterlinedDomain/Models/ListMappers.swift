import Foundation
import InterlinedKit

// MARK: - List DTO → domain mapping
//
// Lives in its own file rather than `Mappers.swift` so the lists/profile
// surface added in M1 task 1B does not collide on the same file as the
// messages/user mappers added in task 1A. Same audit-in-one-place rule
// applies (PLAN.md §3 — DTOs never cross into the UI); this file is just the
// per-group slice.

extension ListSummary {
    /// Maps the lightweight list-row projection used by the public browse
    /// collection. The collection endpoint omits `schema` and (typically)
    /// `description` detail; this initializer only relies on the always-
    /// present `id` / `title` and treats `isPublic` as `true` by default
    /// because the public browse routes only ever return public lists.
    public init(from dto: ListDTO) {
        self.init(
            id: dto.id,
            title: dto.title,
            description: dto.description,
            visibility: Visibility(publiclyVisible: dto.isPublic ?? true),
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

extension ListsPage {
    /// Builds a page from the kit's `Paginated<ListDTO>` envelope, mapping
    /// each row and deriving the next-page cursor from the pagination block —
    /// the same shape `TimelinePage.init(from:)` uses.
    public init(from paginated: Paginated<ListDTO>) {
        let lists = paginated.items.map(ListSummary.init(from:))
        let info = paginated.pagination
        self.init(
            lists: lists,
            hasMore: info.hasMore,
            nextOffset: info.hasMore ? info.offset + info.limit : nil
        )
    }
}

extension ListDetail {
    /// Maps the detail response (`GET /api/users/[username]/lists/[slug]`).
    /// The schema DSL string is carried through verbatim — parsing is M3.
    public init(from dto: ListDTO) {
        self.init(
            summary: ListSummary(from: dto),
            schemaDescription: dto.schema,
            parentID: dto.parentId
        )
    }
}

// MARK: - Row mapping

extension ListCellValue {
    /// Recursive projection of the kit's wire-faithful `ListJSONValue` into
    /// the domain's loose cell type. Arrays and objects map recursively so the
    /// projection is total (every DTO value has exactly one domain value).
    public init(from value: ListJSONValue) {
        switch value {
        case .null: self = .null
        case .bool(let v): self = .bool(v)
        case .int(let v): self = .int(v)
        case .double(let v): self = .double(v)
        case .string(let v): self = .string(v)
        case .array(let items): self = .array(items.map(ListCellValue.init(from:)))
        case .object(let dict):
            self = .object(dict.mapValues(ListCellValue.init(from:)))
        }
    }
}

extension ListRow {
    /// Maps one row DTO, projecting every cell through `ListCellValue` so the
    /// view layer never touches `ListJSONValue` directly.
    public init(from dto: ListRowDTO) {
        self.init(
            id: dto.id,
            listID: dto.listId,
            fields: dto.rowData.mapValues(ListCellValue.init(from:)),
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

extension RowsPage {
    /// Builds a page from the paginated row envelope, deriving the cursor the
    /// same way the other `*Page` initializers do.
    public init(from paginated: Paginated<ListRowDTO>) {
        let rows = paginated.items.map(ListRow.init(from:))
        let info = paginated.pagination
        self.init(
            rows: rows,
            hasMore: info.hasMore,
            nextOffset: info.hasMore ? info.offset + info.limit : nil
        )
    }
}
