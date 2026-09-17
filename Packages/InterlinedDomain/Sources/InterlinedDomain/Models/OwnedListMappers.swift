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
        // `dto.properties` is the field that actually carries the columns;
        // `dto.schema` is a DSL string the server has never sent (GitHub #85).
        // Absent properties leave `schema` nil — "this route does not return
        // columns" — rather than collapsing to an empty schema.
        let columns = dto.schemaFields.map { fields in
            ListSchema(fields: fields.map(SchemaField.init(dto:)))
        }
        self.init(
            id: dto.id,
            title: dto.title,
            description: dto.description,
            visibility: Visibility(publiclyVisible: dto.isPublic ?? false),
            schemaDescription: nil,
            schema: columns,
            parentID: dto.parentId,
            // `githubRepo` and `githubRepoPrivate` have been on the wire since
            // the list routes shipped, and this mapper hard-coded `nil` past
            // them — so a GitHub-backed list looked like a plain one, and the
            // private-repository warning the help page describes had nothing to
            // render from (GitHub #50).
            //
            // Still `nil` for a list with no repository: an empty source object
            // would make every local list look GitHub-backed. `path`, `branch`
            // and the refresh metadata stay absent because they remain
            // unconfirmed on the wire (`work-consolidation.md` P3-C) — modelling
            // them from a guess is what this codebase keeps getting bitten by.
            gitHubSource: dto.githubRepo.map { repository in
                GitHubListSource(
                    repository: repository,
                    isRepositoryPrivate: dto.githubRepoPrivate
                )
            },
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
    /// Maps a watcher DTO. Missing role tokens collapse to `.viewer` — the
    /// least privileged role — so the share-sheet always has a renderable role
    /// and an unknown taxonomy never unlocks edit affordances; unknown tokens
    /// preserve under `.other` per `WatcherRole.init(wireToken:)`.
    ///
    /// The live route nests the person under `user`; the flat `username` is
    /// read as a fallback so older fixtures still map (work-consolidation.md G23).
    public init(from dto: ListWatcherDTO) {
        let role = dto.role.map(WatcherRole.init(wireToken:)) ?? .viewer
        self.init(
            userId: dto.userId,
            username: dto.user?.username ?? dto.username,
            displayName: dto.user?.displayName,
            avatarURL: dto.user?.avatar.flatMap(URL.init(string:)),
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
