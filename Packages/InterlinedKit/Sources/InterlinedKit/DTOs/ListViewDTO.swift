import Foundation

// MARK: - ListViewDTO

/// One **saved list view** — a named, reusable arrangement of a list that
/// either belongs to the caller (`personal`) or to the list itself and
/// therefore to everyone with access (`shared`). Backs the five
/// `/api/lists/{id}/views*` routes (work-consolidation.md G40 / issue #81).
///
/// **Modelled against a captured payload, not the spec.** The OpenAPI schema
/// for `ListView` disagrees with the live API in two ways that each cost a
/// silent defect if mirrored, so every field below is justified by a recorded
/// response from the test account on 2026-09-15 (envelope key re-confirmed by
/// a `GET` on 2026-09-16, which answered `{"views":[]}`):
///
/// ```json
/// {"view":{"id":"…","listId":"…","userId":"…","name":"Reading",
///          "scope":"personal",
///          "config":{"mode":"records","density":"comfortable","filters":[]},
///          "isDefault":false,"position":0}}
/// ```
///
/// **Trap 1 — the spec marks `createdAt` / `updatedAt` REQUIRED and the live
/// API never sends them.** POST, GET and PUT all omitted both. A `Decodable`
/// mirroring the schema throws `keyNotFound` on *every* row, so the two are
/// optional here. They are kept rather than deleted because the spec is the
/// stated intent and a server that starts sending them should decode without
/// a client release.
///
/// **Trap 2 — the spec's response example is not a real payload.** It shows
/// `config.filters: [{"key":"read","op":"eq","value":false}]`; a live POST
/// carrying exactly that filter answered `"filters": []`. Do not build a
/// fixture from the spec example — it describes a shape the server dropped.
///
/// Every other key is **non-optional on purpose**. All eight were present on
/// every observed response, and the issue's acceptance criterion is that a
/// renamed key must fail the decode rather than degrade to `nil` — the exact
/// failure mode that shipped broken link metadata (G21) and broken org members
/// (G25) behind green tests against fabricated fixtures.
public struct ListViewDTO: Codable, Sendable, Equatable, Identifiable {

    public let id: String
    /// The list this view arranges.
    public let listId: String
    /// The view's owner. On a `shared` view this is whoever created it, not
    /// the caller — do not read it as "mine".
    public let userId: String
    public let name: String
    /// `"personal"` or `"shared"`. **The server hard-fails anything else:**
    /// a live `POST` with `"scope":"bogus_scope"` answered
    /// `400 {"error":"scope must be \"personal\" or \"shared\"","code":"bad_request"}`.
    /// Unlike `config`, this key is validated, so the client must send a legal
    /// token rather than hoping for a silent default.
    public let scope: String
    public let config: ListViewConfigDTO
    /// Per-user default. Two people on the same shared list can each have a
    /// different default view, which is why this rides on the view row rather
    /// than the list.
    public let isDefault: Bool
    /// Ordering within a scope bucket. A personal view and a shared view were
    /// both observed at `position: 0`, so it is **not** unique across the
    /// response — never key on it.
    public let position: Int

    /// Absent from every live response (trap 1). Optional so the decode
    /// survives; see the type doc.
    public let createdAt: Date?
    /// Absent from every live response (trap 1). See `createdAt`.
    public let updatedAt: Date?

    public init(
        id: String,
        listId: String,
        userId: String,
        name: String,
        scope: String,
        config: ListViewConfigDTO,
        isDefault: Bool,
        position: Int,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.listId = listId
        self.userId = userId
        self.name = name
        self.scope = scope
        self.config = config
        self.isDefault = isDefault
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - ListViewConfigDTO

/// The arrangement a saved view encodes.
///
/// **`config` is a JSON object, not a string.** The OpenAPI *request body*
/// declares `"config": {"type": "string"}`; that is a generator artifact —
/// the `ListView` schema itself leaves `config` untyped, and a live `POST`
/// carrying a JSON object returned `201`. Issue #81 was filed on the
/// string reading; it is wrong.
///
/// **The server is a whitelist of exactly these four keys.** A live probe sent
/// `columns`, `visibleColumns`, `columnOrder`, `hiddenColumns`, `groupBy`,
/// `sort`, `sortBy`, `sortDirection`, `rowHeight` and a deliberate `bogusKey`
/// alongside them; every one was **stripped silently**, with no `400`. So this
/// is a closed struct rather than an opaque bag: an opaque bag would imply the
/// client can persist keys it cannot, and modelling column order / visibility /
/// sort — which issue #81 presumed `config` carried — would model storage that
/// does not exist.
///
/// **Values default silently where `scope` hard-fails.** Unknown `mode` and
/// `density` tokens return `200` and fall back to the server default rather
/// than erroring, so a client that sends a value it invented gets a view that
/// quietly is not what the user asked for. Both are therefore carried as raw
/// `String` here and projected onto unknown-tolerant domain enums, so an
/// unrecognised token stays visible instead of being rewritten.
public struct ListViewConfigDTO: Codable, Sendable, Equatable {

    /// Observed accepted: `"records"` only. `table`, `gallery`, `kanban`,
    /// `board`, `grid`, `list` and `cards` were each sent live and each came
    /// back as `"records"` with HTTP 200.
    public let mode: String

    /// Observed accepted: `"comfortable"` (the create default) and
    /// `"compact"`. `spacious`, `cozy`, `dense` and `comfy` silently fell back.
    public let density: String

    /// **Element grammar UNCONFIRMED.** Modelled as opaque JSON so whatever the
    /// web writes round-trips through this client untouched. The recon account's
    /// only list has an empty schema (zero columns), so every probe filter
    /// referenced a column key that does not exist and was dropped — which makes
    /// a grammar failure and a column-not-found indistinguishable. The spec's
    /// `{key, op, value}` example is **not** evidence: that exact object was
    /// sent live and dropped to `[]`.
    public let filters: [ListJSONValue]

    /// A stored search string. Whitelisted by the server, but never observed
    /// populated (the default config carries only `mode`, `density`,
    /// `filters`), so optional.
    public let search: String?

    public init(
        mode: String,
        density: String,
        filters: [ListJSONValue] = [],
        search: String? = nil
    ) {
        self.mode = mode
        self.density = density
        self.filters = filters
        self.search = search
    }
}

// MARK: - Response envelopes

/// `GET /api/lists/{id}/views` → `{"views":[…]}`.
///
/// The route's own summary describes the collection as "every shared view on
/// the list, plus this user's own personal views" — one flat array mixing both
/// scopes, which is why the UI must render the `scope` discriminator rather
/// than assuming ownership.
public struct ListViewsResponse: Codable, Sendable, Equatable {
    public let views: [ListViewDTO]

    public init(views: [ListViewDTO]) {
        self.views = views
    }
}

/// The single-view envelope shared by create (`201`), fork (`201`) and update
/// (`200`): `{"view":{…}}`. Matches the site-wide convention that
/// single-resource routes answer `{message?, <resource>}`.
public struct ListViewResponse: Codable, Sendable, Equatable {
    public let view: ListViewDTO
    /// Present on some writes; the live create/fork/update responses carried
    /// only `view`.
    public let message: String?

    public init(view: ListViewDTO, message: String? = nil) {
        self.view = view
        self.message = message
    }
}

// MARK: - Request bodies

/// `POST /api/lists/{id}/views`.
///
/// `scope` is required and validated — see `ListViewDTO.scope`. `config` and
/// `isDefault` are optional: omitting `config` produced the server default
/// `{"mode":"records","density":"comfortable","filters":[]}`.
public struct CreateListViewRequest: Codable, Sendable, Equatable {
    public let name: String
    public let scope: String
    public let config: ListViewConfigDTO?
    public let isDefault: Bool?

    public init(
        name: String,
        scope: String,
        config: ListViewConfigDTO? = nil,
        isDefault: Bool? = nil
    ) {
        self.name = name
        self.scope = scope
        self.config = config
        self.isDefault = isDefault
    }
}

/// `PUT /api/lists/{id}/views/{viewId}`.
///
/// - Important: **`config` is a whole-object REPLACE, not a merge.** A live
///   `PUT` that sent `config` without `density` reset the stored density from
///   `"compact"` back to `"comfortable"`. Callers must send the complete
///   config they want to end up with; the domain layer enforces this by only
///   ever writing a full `SavedListViewConfig`.
public struct UpdateListViewRequest: Codable, Sendable, Equatable {
    public let name: String?
    public let config: ListViewConfigDTO?
    public let isDefault: Bool?

    public init(
        name: String? = nil,
        config: ListViewConfigDTO? = nil,
        isDefault: Bool? = nil
    ) {
        self.name = name
        self.config = config
        self.isDefault = isDefault
    }
}

/// `POST /api/lists/{id}/views/{viewId}` — the fork body.
///
/// The spec calls fork "the escape hatch": it copies a view into a personal
/// copy owned by the caller. VERIFIED live 2026-09-15 that it works on a
/// **personal** source view too, not only a shared one — so the affordance is
/// "duplicate this view for me", not strictly "take it off the owner".
public struct ForkListViewRequest: Codable, Sendable, Equatable {
    /// The forked copy's name. Omitted, the server names it.
    public let name: String?

    public init(name: String? = nil) {
        self.name = name
    }
}
