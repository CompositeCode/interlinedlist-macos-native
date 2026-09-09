import Foundation

// MARK: - ListJSONValue

/// A flexible, type-erased JSON value used to model **dynamic-schema list row
/// data**.
///
/// List rows are not fixed structs: each list defines its own schema DSL
/// (`"Title:text, Year:number, Read:boolean"`), so the `rowData` payload is a
/// `[fieldName: value]` map whose value types vary per column and per list.
/// Modelling `rowData` as `[String: ListJSONValue]` lets the kit decode and
/// re-encode any row losslessly without knowing the schema ahead of time —
/// the Domain layer interprets the values against the parsed schema.
///
/// Named with a `List` prefix to avoid clashing with the kit-private
/// `JSONValue` used by `PaginatedDecoder` and with any other group's helper.
public enum ListJSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([ListJSONValue])
    case object([String: ListJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([ListJSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: ListJSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value in list row data"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

public extension ListJSONValue {
    /// Convenience reader for the common case of a string-valued cell.
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

// MARK: - ListDTO

/// A structured list. Fields are modelled `1:1` against the API response
/// (`https://interlinedlist.com/help/api`). Optional where the API only
/// returns the field on some routes (e.g. `schema`/`description` come back on
/// detail/create responses but not the lightweight collection rows).
public struct ListDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let description: String?
    public let isPublic: Bool?
    /// The schema DSL string (e.g. `"Title:text, Year:number"`). Present on
    /// detail and create responses.
    public let schema: String?
    /// Parent list id for nested lists.
    public let parentId: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    // MARK: Shared-list projection (work-consolidation.md G23 / issue #48)
    //
    // `GET /api/lists/watching` answers rows that are a **superset** of the
    // owned-list shape: the same list fields plus the caller's `role`, the
    // owner under `user`, and a `parent` projection. Rather than fork a second
    // list DTO, the extra keys land here as optionals — absent on every other
    // list route, so `nil` there and every existing fixture decodes unchanged.
    //
    // VERIFIED live 2026-09-09 against the test account:
    //   {"lists":[{ …list…, "userId":…, "folderId":null, "source":"local",
    //               "githubRepo":null, "githubRepoPrivate":null,
    //               "user":{"id","username","displayName"},
    //               "parent":{"id","title"}, "children":[], "role":"collaborator" }],
    //    "pagination":{ total, limit, offset, hasMore }}

    /// The owning user's id. Present on the authenticated list routes; on
    /// `/api/lists/watching` it identifies the *other* user who shared the list.
    public let userId: String?
    /// The list-folder this list is filed under, or `nil` for the root.
    public let folderId: String?
    /// Row origin marker (`"local"`, `"github"`, …) when the route returns it.
    public let source: String?
    /// The `"owner/repo"` slug for a GitHub-backed list.
    public let githubRepo: String?
    /// Whether the backing GitHub repository is private.
    public let githubRepoPrivate: Bool?
    /// The **caller's** role on this list (`watcher` / `collaborator` /
    /// `manager`). Only `/api/lists/watching` returns it.
    public let role: String?
    /// The list's owner. Only `/api/lists/watching` returns it.
    public let user: ListUserDTO?
    /// A lightweight projection of the parent list (id + title only).
    ///
    /// - Important: the presence of `parent` says nothing about whether the
    ///   caller can *open* the parent — a watched child whose parent was not
    ///   shared still carries this projection. Treat it as a label, not a link.
    public let parent: ListParentDTO?

    public init(
        id: String,
        title: String,
        description: String? = nil,
        isPublic: Bool? = nil,
        schema: String? = nil,
        parentId: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        userId: String? = nil,
        folderId: String? = nil,
        source: String? = nil,
        githubRepo: String? = nil,
        githubRepoPrivate: Bool? = nil,
        role: String? = nil,
        user: ListUserDTO? = nil,
        parent: ListParentDTO? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.isPublic = isPublic
        self.schema = schema
        self.parentId = parentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
        self.folderId = folderId
        self.source = source
        self.githubRepo = githubRepo
        self.githubRepoPrivate = githubRepoPrivate
        self.role = role
        self.user = user
        self.parent = parent
    }
}

/// A user embedded in a list payload — the owner on `/api/lists/watching`, the
/// candidate rows on `/api/lists/[id]/watchers/users`, and the nested `user`
/// on a watcher row. Only `id` is guaranteed by every route.
public struct ListUserDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let username: String?
    public let displayName: String?
    public let email: String?
    public let avatar: String?

    public init(
        id: String,
        username: String? = nil,
        displayName: String? = nil,
        email: String? = nil,
        avatar: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.avatar = avatar
    }
}

/// The `parent` projection on a watched list — id + title, nothing else.
public struct ListParentDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

// MARK: - List schema

/// Response of `GET /api/lists/[id]/schema` and `PUT /api/lists/[id]/schema`:
/// `{ "schema": "<DSL>" }`.
public struct ListSchemaDTO: Codable, Sendable, Equatable {
    public let schema: String

    public init(schema: String) {
        self.schema = schema
    }
}

// MARK: - List rows

/// A single dynamic-schema list row. `rowData` is the flexible field map keyed
/// by the schema's column names; its value types are list-defined.
public struct ListRowDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let listId: String?
    public let rowData: [String: ListJSONValue]
    /// The row's origin marker when the row was synced from an external source
    /// rather than authored in-app (e.g. `"github"`). `nil` for native rows.
    ///
    /// A list becomes "GitHub-backed" at the row level — the live API attaches
    /// `source`/`githubRepo` to synced rows (see `work-consolidation.md` P3-C:
    /// "rows carry `source`/`githubRepo` live") while a stable **list-level**
    /// `githubSource` object on create/read is still unconfirmed upstream. Both
    /// fields are optional so a native row (and every existing fixture) decodes
    /// unchanged; a row that carries them lets the client recognise the backing
    /// and route row-creation to the GitHub issue flow instead of a native row.
    public let source: String?
    /// The `"owner/repo"` slug a GitHub-synced row belongs to. `nil` for native
    /// rows. Paired with `source`; either may appear alone depending on the
    /// route, so the client treats a non-nil `githubRepo` as the authoritative
    /// backing signal.
    public let githubRepo: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        listId: String? = nil,
        rowData: [String: ListJSONValue],
        source: String? = nil,
        githubRepo: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.listId = listId
        self.rowData = rowData
        self.source = source
        self.githubRepo = githubRepo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - List watchers

/// A watcher / access entry on a shared list. Role is a free string from the
/// API (`"watcher"`, `"collaborator"`, `"manager"`); the Domain layer maps it
/// to a typed role. Fields beyond `userId`/`role` are optional because the API
/// does not pin them down on every watcher route.
///
/// The route nests the person under `user` (`/help/api/lists`: `{ watchers: [
/// { id, userId, role, createdAt, user } ] }`); the flat `username` is kept
/// for older fixtures and is read as a fallback by the domain mapper.
public struct ListWatcherDTO: Codable, Sendable, Equatable {
    /// The watcher-row id (distinct from `userId`). Not returned by every route.
    public let id: String?
    public let userId: String
    public let role: String?
    public let username: String?
    /// The nested person object the live route returns.
    public let user: ListUserDTO?
    public let createdAt: Date?

    public init(
        id: String? = nil,
        userId: String,
        role: String? = nil,
        username: String? = nil,
        user: ListUserDTO? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.role = role
        self.username = username
        self.user = user
        self.createdAt = createdAt
    }
}

/// `GET /api/lists/[id]/watchers` — `{ watchers: [...], pagination? }`.
///
/// VERIFIED live 2026-09-09: the route answers this envelope, **not** a bare
/// `[ListWatcherDTO]` array. The builder previously declared the bare array, so
/// every watcher read failed at the decoder and the sharing panel could never
/// list anyone (issue #48 / G23 recon).
public struct ListWatchersResponse: Codable, Sendable, Equatable {
    public let watchers: [ListWatcherDTO]

    public init(watchers: [ListWatcherDTO]) {
        self.watchers = watchers
    }
}

/// Response of `GET /api/lists/[id]/watchers/me` — the caller's own watcher
/// status on a list.
///
/// VERIFIED live 2026-09-09: the wire key is **`watching`**, not `isWatching`.
/// The Swift property keeps the `isWatching` name (it reads as a Bool) and
/// `CodingKeys` maps it; before this the flag decoded to `nil` on every call,
/// so the client believed the caller was never watching anything.
public struct ListWatcherStatusDTO: Codable, Sendable, Equatable {
    public let isWatching: Bool?
    public let role: String?

    private enum CodingKeys: String, CodingKey {
        case isWatching = "watching"
        case role
    }

    public init(isWatching: Bool? = nil, role: String? = nil) {
        self.isWatching = isWatching
        self.role = role
    }
}

/// `GET /api/lists/[id]/watchers/users?search=…` — the **candidate** search
/// (people the owner could add), not the current watcher list.
///
/// VERIFIED live 2026-09-09: `{ "users": [ { id, username, displayName, email,
/// avatar } ], "total": 18, "pagination": { limit, offset, hasMore } }`. The
/// builder previously declared `[ListWatcherDTO]`, which cannot decode this at
/// all — the rows carry no `userId` and no `role`.
public struct ListWatcherCandidatesResponse: Codable, Sendable, Equatable {
    public let users: [ListUserDTO]
    public let total: Int?

    public init(users: [ListUserDTO], total: Int? = nil) {
        self.users = users
        self.total = total
    }
}

/// `PUT /api/lists/[id]/watchers/[userId]` — `{ "role": "<role>" }`.
///
/// Documented on `/help/api/lists` and **not** the full watcher row the builder
/// previously decoded, so a role change failed at the decoder even when the
/// server applied it.
public struct SetListWatcherRoleResponse: Codable, Sendable, Equatable {
    public let role: String?

    public init(role: String? = nil) {
        self.role = role
    }
}

/// `POST /api/lists/[id]/watchers` — add a watcher (work-consolidation.md G23).
///
/// Two documented modes share one body (`/help/api/lists`):
/// - **Owner grants a named user** — `userId` set; adds that user at `role`
///   (default `watcher`). Subscriber-gated: a free owner gets `403`.
/// - **Self-subscribe** — `userId` omitted; the caller watches a public list
///   that is not their own. Free, and `notify` is ignored.
///
/// `notify` defaults to `true` server-side; pass `false` to grant access
/// without sending the recipient an email.
public struct AddListWatcherRequest: Codable, Sendable, Equatable {
    public let userId: String?
    public let role: String?
    public let notify: Bool?

    public init(userId: String? = nil, role: String? = nil, notify: Bool? = nil) {
        self.userId = userId
        self.role = role
        self.notify = notify
    }
}

/// `POST /api/lists/[id]/watchers` response. Documented as `{ watching: true }`
/// for the self-subscribe branch; the owner-grant branch was not re-probed live
/// (it is a write, and the recon account is shared), so every field is optional
/// and any of them signals success. `201` means a new grant, `200` an
/// idempotent re-add.
public struct AddListWatcherResponse: Codable, Sendable, Equatable {
    public let watching: Bool?
    public let role: String?
    public let userId: String?
    public let watcher: ListWatcherDTO?

    public init(
        watching: Bool? = nil,
        role: String? = nil,
        userId: String? = nil,
        watcher: ListWatcherDTO? = nil
    ) {
        self.watching = watching
        self.role = role
        self.userId = userId
        self.watcher = watcher
    }
}

// MARK: - List contributors

/// One ranked contributor to a list (`GET /api/lists/[id]/contributors`).
///
/// VERIFIED live 2026-09-09:
/// `{"contributors":[{"id","username","displayName","avatar","addedCount",
///   "editedCount","score"}],"totalContributors":1}`.
public struct ListContributorDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let username: String?
    public let displayName: String?
    public let avatar: String?
    /// Rows this person added.
    public let addedCount: Int?
    /// Rows this person edited.
    public let editedCount: Int?
    /// The server's ranking score (`addedCount + editedCount` in the observed
    /// payload, but treated as opaque — the client only sorts by it).
    public let score: Int?

    public init(
        id: String,
        username: String? = nil,
        displayName: String? = nil,
        avatar: String? = nil,
        addedCount: Int? = nil,
        editedCount: Int? = nil,
        score: Int? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
        self.addedCount = addedCount
        self.editedCount = editedCount
        self.score = score
    }
}

/// `GET /api/lists/[id]/contributors` — `{ contributors: [...], totalContributors }`.
/// The route is documented as unpaged ("no server paging").
public struct ListContributorsResponse: Codable, Sendable, Equatable {
    public let contributors: [ListContributorDTO]
    public let totalContributors: Int?

    public init(contributors: [ListContributorDTO], totalContributors: Int? = nil) {
        self.contributors = contributors
        self.totalContributors = totalContributors
    }
}

// MARK: - List email-invite landing

/// `GET /api/lists/invite/{token}` — the email-invite landing payload.
///
/// Shape from `/help/api/sharing`:
/// `{ role, needsAuth, canClaim, wrongAccount, accepted, resourceTitle }`.
/// The invited email address is deliberately never returned.
///
/// - Note: the **accept** half (`POST /api/lists/invite/{token}`) is declared
///   `x-auth-type: session` in the live OpenAPI spec, so a Bearer-only client
///   cannot claim an invite. This DTO backs a landing view only.
public struct ResolvedListInviteDTO: Codable, Sendable, Equatable {
    public let role: String?
    /// `true` when nobody is signed in — prompt sign-in.
    public let needsAuth: Bool?
    /// `true` when the signed-in user's verified email matches the invite.
    public let canClaim: Bool?
    /// `true` when someone is signed in but under a different email.
    public let wrongAccount: Bool?
    /// `true` once the invite has already been claimed.
    public let accepted: Bool?
    /// The title of the list the invite grants access to.
    public let resourceTitle: String?

    public init(
        role: String? = nil,
        needsAuth: Bool? = nil,
        canClaim: Bool? = nil,
        wrongAccount: Bool? = nil,
        accepted: Bool? = nil,
        resourceTitle: String? = nil
    ) {
        self.role = role
        self.needsAuth = needsAuth
        self.canClaim = canClaim
        self.wrongAccount = wrongAccount
        self.accepted = accepted
        self.resourceTitle = resourceTitle
    }
}

// MARK: - List connections

/// A directed connection between two lists (powers the ERD / graph canvas).
public struct ListConnectionDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let fromListId: String
    public let toListId: String
    public let label: String?
    public let createdAt: Date?

    public init(
        id: String,
        fromListId: String,
        toListId: String,
        label: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.fromListId = fromListId
        self.toListId = toListId
        self.label = label
        self.createdAt = createdAt
    }
}

/// `GET /api/lists/connections` wraps its array under `"connections"`.
public struct ListConnectionsResponse: Codable, Sendable, Equatable {
    public let connections: [ListConnectionDTO]

    public init(connections: [ListConnectionDTO]) {
        self.connections = connections
    }
}

/// Envelope returned by `POST /api/lists/[id]/data` and
/// `PUT /api/lists/[id]/data/[rowId]`.
///
/// VERIFIED live 2026-09-06: both answer
/// `{ "message": "Row <created|updated> successfully", "data": { …row… } }` —
/// **not** a bare `ListRowDTO`. The builders previously decoded the bare row,
/// so even a request that reached the server failed at the decoder
/// (work-consolidation.md §1c · V3).
public struct ListRowWriteResponse: Codable, Sendable, Equatable {
    public let message: String?
    public let data: ListRowDTO

    public init(message: String? = nil, data: ListRowDTO) {
        self.message = message
        self.data = data
    }
}

// MARK: - Request bodies

/// `POST /api/lists` body.
public struct CreateListRequest: Codable, Sendable, Equatable {
    public let title: String
    public let description: String?
    public let schema: String?
    public let parentId: String?
    public let isPublic: Bool?

    public init(
        title: String,
        description: String? = nil,
        schema: String? = nil,
        parentId: String? = nil,
        isPublic: Bool? = nil
    ) {
        self.title = title
        self.description = description
        self.schema = schema
        self.parentId = parentId
        self.isPublic = isPublic
    }
}

/// `PUT /api/lists/[id]` body. All fields optional — metadata partial update.
public struct UpdateListRequest: Codable, Sendable, Equatable {
    public let title: String?
    public let description: String?
    public let isPublic: Bool?
    public let parentId: String?

    public init(
        title: String? = nil,
        description: String? = nil,
        isPublic: Bool? = nil,
        parentId: String? = nil
    ) {
        self.title = title
        self.description = description
        self.isPublic = isPublic
        self.parentId = parentId
    }
}

/// `PUT /api/lists/[id]/schema` body: `{ "schema": "<DSL>" }`.
public struct UpdateListSchemaRequest: Codable, Sendable, Equatable {
    public let schema: String

    public init(schema: String) {
        self.schema = schema
    }
}

/// `POST /api/lists/[id]/data` body: `{ "data": { ... } }`.
///
/// VERIFIED live 2026-09-06 (work-consolidation.md §1c · V3): the wire field is
/// **`data`**, not `rowData`. Sending `rowData` returns
/// `400 {"error":"Data is required","code":"bad_request"}`, so row creation
/// never worked against production. The Swift property keeps the `rowData` name
/// — it matches `ListRowDTO.rowData`, which the *response* really does nest
/// under that key — and `CodingKeys` maps it to the wire name.
public struct CreateListRowRequest: Codable, Sendable, Equatable {
    public let rowData: [String: ListJSONValue]

    private enum CodingKeys: String, CodingKey {
        case rowData = "data"
    }

    public init(rowData: [String: ListJSONValue]) {
        self.rowData = rowData
    }
}

/// `PUT /api/lists/[id]/data/[rowId]` body: `{ "data": { ... } }`.
///
/// VERIFIED live 2026-09-06 (work-consolidation.md §1c · V3): same `data`
/// wire-name correction as `CreateListRowRequest` — a `rowData` body is
/// rejected with `400 "Data is required"` even once the verb is right.
public struct UpdateListRowRequest: Codable, Sendable, Equatable {
    public let rowData: [String: ListJSONValue]

    private enum CodingKeys: String, CodingKey {
        case rowData = "data"
    }

    public init(rowData: [String: ListJSONValue]) {
        self.rowData = rowData
    }
}

/// `PUT /api/lists/[id]/watchers/[userId]` body: `{ "role", "notify"? }`.
///
/// `role` must be one of `watcher` / `collaborator` / `manager` — an invalid or
/// missing value is a `400`. `notify` defaults to `true` server-side and only
/// fires when the role actually changes (`/help/api/lists`).
public struct UpdateListWatcherRequest: Codable, Sendable, Equatable {
    public let role: String
    public let notify: Bool?

    public init(role: String, notify: Bool? = nil) {
        self.role = role
        self.notify = notify
    }
}

/// `POST /api/lists/connections` body.
public struct CreateListConnectionRequest: Codable, Sendable, Equatable {
    public let fromListId: String
    public let toListId: String
    public let label: String?

    public init(fromListId: String, toListId: String, label: String? = nil) {
        self.fromListId = fromListId
        self.toListId = toListId
        self.label = label
    }
}
