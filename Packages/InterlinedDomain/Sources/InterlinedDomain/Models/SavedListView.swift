import Foundation
import InterlinedKit

// MARK: - SavedListViewScope

/// Who a saved view belongs to (work-consolidation.md G40 / issue #81).
///
/// This is the collaboration model the feature exists for: a `shared` view
/// belongs to the *list*, so everyone with access sees it; a `personal` view
/// belongs to the *caller*. `GET …/views` returns both in one array, so the
/// UI must render this discriminator — without it a collaborator cannot tell
/// the owner's arrangement from their own.
///
/// **No `.unknown` case, deliberately.** Unlike `mode` and `density`, `scope`
/// is validated server-side: a live `POST` with `"scope":"bogus_scope"`
/// answered `400 {"error":"scope must be \"personal\" or \"shared\"",
/// "code":"bad_request"}` (2026-09-15). Preserving an unrecognised token for
/// round-trip would therefore guarantee a 400 on the next write rather than
/// protect anything — the opposite of what the escape hatch on
/// `ViewingPreference.other` buys. An unreadable token collapses to
/// `.personal` in the mapper instead; see `SavedListView.init(from:)`.
public enum SavedListViewScope: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Visible only to the caller.
    case personal
    /// Belongs to the list; visible to everyone with access to it.
    case shared

    /// Human label for the scope badge.
    public var displayName: String {
        switch self {
        case .personal: return "Personal"
        case .shared:   return "Shared"
        }
    }
}

// MARK: - SavedListViewMode

/// How a saved view asks the list to be laid out.
///
/// **Only `records` was ever accepted.** A live probe sent `table`, `gallery`,
/// `kanban`, `board`, `grid`, `list` and `cards`; every one returned HTTP 200
/// and read back as `"records"` (2026-09-15). The server silently normalises
/// instead of rejecting, which is why `.unknown` is a real state and not
/// defensive padding: if a later server starts storing a mode this build does
/// not know, the only alternative to surfacing it is to overwrite the user's
/// choice with `records` on the next save.
public enum SavedListViewMode: Sendable, Equatable, Hashable {
    /// The one mode the server actually stores today.
    case records
    /// A token this build does not recognise, carried verbatim.
    case unknown(String)

    public init(wireToken: String) {
        switch wireToken.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "records": self = .records
        case let token: self = .unknown(token)
        }
    }

    public var wireToken: String {
        switch self {
        case .records:             return "records"
        case .unknown(let token):  return token
        }
    }

    public var displayName: String {
        switch self {
        case .records:            return "Records"
        case .unknown(let token): return token
        }
    }
}

// MARK: - SavedListViewDensity

/// Row spacing a saved view asks for.
///
/// **Accepted live: `comfortable` (the create default) and `compact`.**
/// `spacious`, `cozy`, `dense` and `comfy` each returned 200 and silently fell
/// back (2026-09-15). Same reasoning as `SavedListViewMode` for `.unknown`.
public enum SavedListViewDensity: Sendable, Equatable, Hashable {
    case comfortable
    case compact
    /// A token this build does not recognise, carried verbatim.
    case unknown(String)

    public init(wireToken: String) {
        switch wireToken.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "comfortable": self = .comfortable
        case "compact":     self = .compact
        case let token:     self = .unknown(token)
        }
    }

    public var wireToken: String {
        switch self {
        case .comfortable:        return "comfortable"
        case .compact:            return "compact"
        case .unknown(let token): return token
        }
    }

    public var displayName: String {
        switch self {
        case .comfortable:        return "Comfortable"
        case .compact:            return "Compact"
        case .unknown(let token): return token
        }
    }

    /// The two densities a user may pick. `.unknown` is never offered — it
    /// only ever arrives from the server.
    public static let selectable: [SavedListViewDensity] = [.comfortable, .compact]
}

// MARK: - SavedListViewConfig

/// The arrangement a saved view stores.
///
/// **Exactly four keys, because the server is a whitelist.** A live probe sent
/// `columns`, `visibleColumns`, `columnOrder`, `hiddenColumns`, `groupBy`,
/// `sort`, `sortBy`, `sortDirection`, `rowHeight` and a deliberate `bogusKey`;
/// all ten were stripped without an error (2026-09-15). Issue #81 presumed
/// `config` encoded column order / visibility / sort — it does not, and
/// modelling those would be modelling storage that does not exist.
///
/// A *value* type rather than a bag of optionals: because `PUT` replaces the
/// config whole (omitting `density` on a live PUT reset it from `compact` to
/// `comfortable`), every write must state the complete arrangement. Making
/// `mode` and `density` non-optional makes that structurally impossible to get
/// wrong — there is no way to construct a half-config and send it.
public struct SavedListViewConfig: Sendable, Equatable {

    public var mode: SavedListViewMode
    public var density: SavedListViewDensity

    /// Stored filters, **grammar unconfirmed**, carried as opaque JSON so
    /// whatever the web wrote survives a macOS round-trip untouched.
    ///
    /// The recon account's only list has an empty schema (zero columns), so
    /// every probe filter named a column that does not exist and was dropped —
    /// leaving a grammar failure and a column-not-found indistinguishable. The
    /// OpenAPI example's `{key, op, value}` shape is not evidence either: that
    /// exact object was sent live and came back `[]`. Until a populated list is
    /// available to probe, this client must not invent an element type and must
    /// not drop what it cannot parse.
    public var filters: [ListCellValue]

    /// A stored search string. Whitelisted by the server but never observed
    /// populated, so optional.
    public var search: String?

    public init(
        mode: SavedListViewMode = .records,
        density: SavedListViewDensity = .comfortable,
        filters: [ListCellValue] = [],
        search: String? = nil
    ) {
        self.mode = mode
        self.density = density
        self.filters = filters
        self.search = search
    }

    /// The arrangement the server applies when a create omits `config`
    /// entirely — verified live: `{"mode":"records","density":"comfortable",
    /// "filters":[]}`. Named rather than inlined so a UI default and the
    /// server default can never drift apart silently.
    public static let serverDefault = SavedListViewConfig()
}

// MARK: - SavedListView

/// One saved, named arrangement of a list.
///
/// Backed by `GET/POST/PUT/DELETE /api/lists/{id}/views*`. Free on every tier
/// and Bearer-reachable — see `Lists.views(listId:)` for why no entitlement
/// gate belongs here.
public struct SavedListView: Sendable, Equatable, Identifiable {

    public let id: String
    /// The list this view arranges.
    public let listID: String
    /// Whoever created the view. On a `shared` view that is not necessarily
    /// the caller, so never read this as "mine" — `scope` is the discriminator
    /// the UI renders.
    public let ownerID: String
    public let name: String
    public let scope: SavedListViewScope
    public let config: SavedListViewConfig
    /// **Per user.** Two people on the same shared list can each mark a
    /// different view as their default, which is why this rides on the view
    /// rather than on the list.
    public let isDefault: Bool
    /// The server's ordering hint within a scope bucket. A personal view and a
    /// shared view were both observed at `position: 0`, so it is not unique
    /// across a response — display order comes from the server's array order,
    /// never from sorting on this.
    public let position: Int

    public init(
        id: String,
        listID: String,
        ownerID: String,
        name: String,
        scope: SavedListViewScope,
        config: SavedListViewConfig,
        isDefault: Bool,
        position: Int
    ) {
        self.id = id
        self.listID = listID
        self.ownerID = ownerID
        self.name = name
        self.scope = scope
        self.config = config
        self.isDefault = isDefault
        self.position = position
    }

    /// Whether this view is the list's, not the caller's — drives the shared
    /// badge and the "fork it rather than edit it" affordance.
    public var isShared: Bool { scope == .shared }
}

// MARK: - DTO → domain mapping

extension SavedListViewConfig {
    public init(from dto: ListViewConfigDTO) {
        self.init(
            mode: SavedListViewMode(wireToken: dto.mode),
            density: SavedListViewDensity(wireToken: dto.density),
            filters: dto.filters.map(ListCellValue.init(from:)),
            search: dto.search
        )
    }

    /// Projects back to the wire shape. Always emits the complete object
    /// because `PUT` replaces rather than merges.
    public var wireValue: ListViewConfigDTO {
        ListViewConfigDTO(
            mode: mode.wireToken,
            density: density.wireToken,
            filters: filters.map(ListJSONValue.init(from:)),
            search: search
        )
    }
}

extension SavedListView {
    /// Maps one `ListViewDTO`.
    ///
    /// An unrecognised `scope` collapses to `.personal`: mislabelling someone's
    /// private arrangement as shared would tell the user their filters are
    /// visible to collaborators when they are not, and that is the more harmful
    /// of the two possible mistakes. The server validates the field on write,
    /// so this branch should be unreachable in practice.
    public init(from dto: ListViewDTO) {
        self.init(
            id: dto.id,
            listID: dto.listId,
            ownerID: dto.userId,
            name: dto.name,
            scope: SavedListViewScope(rawValue: dto.scope) ?? .personal,
            config: SavedListViewConfig(from: dto.config),
            isDefault: dto.isDefault,
            position: dto.position
        )
    }
}
