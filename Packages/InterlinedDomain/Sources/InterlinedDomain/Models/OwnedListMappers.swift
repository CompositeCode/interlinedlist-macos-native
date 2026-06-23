import Foundation
import InterlinedKit

// MARK: - Owned-list DTO → domain mapping
//
// The M3 owned-list slice maps the `/api/lists*` authenticated routes into
// the domain's `OwnedList` / `ListWatcher` / `ListConnection` types. Same
// "DTOs never cross into the UI" rule that applies to every mapper file in
// this folder (PLAN.md §3, decision 0003).

extension OwnedList {
    /// Maps an authenticated list DTO. `isPublic` defaults to `false` when
    /// the API omits the flag — the authenticated routes return private
    /// lists by default, so the safe-default is `.private`.
    public init(from dto: ListDTO) {
        self.init(
            id: dto.id,
            title: dto.title,
            description: dto.description,
            visibility: Visibility(publiclyVisible: dto.isPublic ?? false),
            schemaDescription: dto.schema,
            parentID: dto.parentId,
            // The kit's `ListDTO` does not yet carry GitHub-source fields
            // (prompts file item 2.3); leave the field `nil` and let the
            // refresh path populate it once the kit DTO grows.
            gitHubSource: nil,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

extension OwnedListsPage {
    /// Builds a page from the kit's `Paginated<ListDTO>` envelope.
    public init(from paginated: Paginated<ListDTO>) {
        let lists = paginated.items.map(OwnedList.init(from:))
        let info = paginated.pagination
        self.init(
            lists: lists,
            hasMore: info.hasMore,
            nextOffset: info.hasMore ? info.offset + info.limit : nil
        )
    }
}

// MARK: - Watcher mapping

extension ListWatcher {
    /// Maps a watcher DTO. Missing role tokens collapse to `.viewer` so the
    /// share-sheet always has a renderable role; unknown tokens preserve
    /// under `.other` per `WatcherRole.init(wireToken:)`.
    public init(from dto: ListWatcherDTO) {
        let role = dto.role.map(WatcherRole.init(wireToken:)) ?? .viewer
        self.init(
            userId: dto.userId,
            username: dto.username,
            role: role,
            createdAt: dto.createdAt
        )
    }
}

extension WatcherStatus {
    /// Maps the `GET /watchers/me` response. `isWatching` defaults to `false`
    /// when the API omits it; the role is parsed when present, otherwise `nil`.
    public init(from dto: ListWatcherStatusDTO) {
        let isWatching = dto.isWatching ?? false
        let role = dto.role.map(WatcherRole.init(wireToken:))
        self.init(isWatching: isWatching, role: role)
    }
}

// MARK: - Connection mapping

extension ListConnection {
    /// Maps a connection DTO.
    public init(from dto: ListConnectionDTO) {
        self.init(
            id: dto.id,
            fromListId: dto.fromListId,
            toListId: dto.toListId,
            label: dto.label,
            createdAt: dto.createdAt
        )
    }
}
