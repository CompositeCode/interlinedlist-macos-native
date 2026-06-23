import Foundation

/// GitHub-backed list metadata (PLAN.md §1 "GitHub-backed lists", §6 M3).
///
/// The kit's `ListDTO` does not pin specific GitHub-source fields yet — the
/// upstream API has not documented a stable shape (see
/// `/API-backend-prompts-to-build.md` item 2.3 — `lastRefreshedAt` /
/// `refreshStatus`). This struct is the placeholder domain projection that
/// the M3 refresh toolbar and auto-refresh option will fill in once the API
/// settles: `lastRefreshedAt`, the optional `refreshStatus`, and the source
/// repo / path metadata. For now it ships with `nil` defaults so a list can
/// declare itself "GitHub-backed" without yet exposing per-source detail.
///
/// `init(from dto:)` is intentionally **not** auto-applied — `OwnedList`
/// constructs `nil` until the kit DTO carries enough fields to populate this.
/// Tests instantiate it directly with the fields they need.
public struct GitHubListSource: Sendable, Equatable, Hashable {

    /// The GitHub repo path (`"owner/repo"`), when the API surfaces it.
    public let repository: String?

    /// The path within the repo (`"data/books.csv"`), when the API surfaces it.
    public let path: String?

    /// The branch (`"main"`), when the API surfaces it.
    public let branch: String?

    /// When the list was last refreshed against its GitHub source. `nil`
    /// when never refreshed or when the API omits the field.
    public let lastRefreshedAt: Date?

    /// Last refresh status (`"ok"`, `"error"`, …) when the API surfaces one.
    /// Open string by design — the upstream taxonomy is undocumented.
    public let refreshStatus: String?

    public init(
        repository: String? = nil,
        path: String? = nil,
        branch: String? = nil,
        lastRefreshedAt: Date? = nil,
        refreshStatus: String? = nil
    ) {
        self.repository = repository
        self.path = path
        self.branch = branch
        self.lastRefreshedAt = lastRefreshedAt
        self.refreshStatus = refreshStatus
    }
}
