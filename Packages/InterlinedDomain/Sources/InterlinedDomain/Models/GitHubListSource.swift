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

    /// Whether the backing repository is private.
    ///
    /// `githubRepoPrivate` has been on the wire since the list routes shipped
    /// and the client never read it (GitHub #50). It matters for one specific
    /// reason the help page names: a repository link a visitor cannot open
    /// sends them to a GitHub sign-in or a "not found" page, and the list has to
    /// warn them before they follow it.
    ///
    /// `nil` when the route did not say — which is not the same as "public",
    /// and the UI shows no tag rather than claiming either way.
    public let isRepositoryPrivate: Bool?

    public init(
        repository: String? = nil,
        path: String? = nil,
        branch: String? = nil,
        lastRefreshedAt: Date? = nil,
        refreshStatus: String? = nil,
        isRepositoryPrivate: Bool? = nil
    ) {
        self.repository = repository
        self.path = path
        self.branch = branch
        self.lastRefreshedAt = lastRefreshedAt
        self.refreshStatus = refreshStatus
        self.isRepositoryPrivate = isRepositoryPrivate
    }

    /// The `owner/repo` slug's URL on github.com, when the repository is named.
    ///
    /// Built here rather than in the view so there is one place that knows the
    /// slug is a github.com path — and one place to change if a list ever points
    /// at an enterprise host.
    public var repositoryURL: URL? {
        guard let repository, !repository.isEmpty else { return nil }
        return URL(string: "https://github.com/\(repository)")
    }
}
