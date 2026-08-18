import Foundation

/// Request builders for the **GitHub issue integration** API group
/// (work-consolidation.md G4) — browse repos, list/create/edit issues, and
/// comment, for GitHub-backed lists and the "create issue from message" action.
///
/// The `/api/github/*` routes are deployed but undocumented for third-party
/// clients (work-consolidation.md §2 · P1-H): `GET /api/github/repos` returns
/// HTTP 400 `{ "error": "GitHub account not linked" }` until the account links
/// a GitHub identity. Linking already ships via the native OAuth flow, so the
/// unlinked 400 is a *state*, not a blocker — the domain `GitHubService`
/// translates it to `GitHubServiceError.notLinked` so the UI can deep-link the
/// linking flow.
///
/// Route surface **verified live 2026-08-17** (unlinked probes; success shapes
/// still pending a linked account). `repo` is the `"owner/repo"` slug matching
/// `GitHubListSource.repository`. The surface is **mixed**:
///   • issues **list/create** are FLAT — `GET`/`POST /api/github/issues?repo=…`
///     (the nested `/repos/{repo}/issues` form 404s);
///   • `repos`, `assignees`, `labels`, `next-issue-number` are NESTED under
///     `/api/github/repos/{repo}/…` (confirmed present).
///   • issue **update** (`updateIssue`) and **comment** routes are NOT the paths
///     below — see their ⚠️ notes and work-consolidation.md §2 · P1-H2.
/// Response shapes are decoded tolerantly (see `GitHubDTO.swift`). Auth: all `.bearer`.
public enum GitHub {

    /// `GET /api/github/repos` — repositories the linked account can access.
    public static func repos() -> Request<GitHubReposResponse> {
        Request(method: .get, path: "/api/github/repos", auth: .bearer)
    }

    /// `GET /api/github/issues?repo={owner/repo}` — issues for a repo, filtered
    /// by `state` (`"open"` / `"closed"` / `"all"`) when supplied.
    ///
    /// VERIFIED live 2026-08-17: the issues resource is **flat** — `repo` is a
    /// query param, NOT a nested path segment. The old
    /// `GET /api/github/repos/{repo}/issues` form 404s live; the flat form
    /// returns 400 "GitHub account not linked" (route exists). `OPTIONS` on it
    /// reports `Allow: GET, HEAD, OPTIONS, POST`.
    public static func issues(repo: String, state: String? = nil) -> Request<GitHubIssuesResponse> {
        Request(
            method: .get,
            path: "/api/github/issues",
            query: [.string("repo", repo), .string("state", state)],
            auth: .bearer
        )
    }

    /// `POST /api/github/issues?repo={owner/repo}` — create an issue.
    ///
    /// VERIFIED live 2026-08-17: an unlinked probe returned 400
    /// `{"error":"title is required"}`, confirming the flat path, the `POST`
    /// method, and that `title` is the required body field. (The old nested
    /// `POST /api/github/repos/{repo}/issues` form 404s.)
    public static func createIssue(
        repo: String,
        _ body: CreateGitHubIssueRequest
    ) -> Request<GitHubIssueResponse> {
        Request(
            method: .post,
            path: "/api/github/issues",
            query: [.string("repo", repo)],
            body: .json(body),
            auth: .bearer
        )
    }

    /// `PATCH /api/github/repos/{owner}/{repo}/issues/{number}` — edit an
    /// issue's title/body/state/labels/assignees (only the supplied fields).
    ///
    /// ⚠️ ROUTE UNVERIFIED — LIKELY BROKEN (2026-08-17). This nested path 404s
    /// live, and the flat `/api/github/issues` collection rejects `PATCH`/`PUT`
    /// (405; `Allow: GET, HEAD, OPTIONS, POST`). The correct update route/verb
    /// could not be found by probing (all obvious single-issue paths 404). Until
    /// backend confirmation (work-consolidation.md §2 · P1-H2), close/reopen and
    /// label/assignee editing will NOT work against the live API. Left as-is so
    /// the shape is documented rather than silently guessed.
    public static func updateIssue(
        repo: String,
        number: Int,
        _ body: UpdateGitHubIssueRequest
    ) -> Request<GitHubIssueResponse> {
        Request(
            method: .patch,
            path: "/api/github/repos/\(repo)/issues/\(number)",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `POST /api/github/repos/{owner}/{repo}/issues/{number}/comments`.
    ///
    /// ⚠️ ROUTE UNVERIFIED — LIKELY BROKEN (2026-08-17). This path 404s live and
    /// no comment route was found (`/api/github/issues/{n}/comments`,
    /// `/api/github/issues/comments`, `/api/github/comments` all 404). Needs
    /// backend confirmation (work-consolidation.md §2 · P1-H2).
    public static func comment(
        repo: String,
        number: Int,
        _ body: CreateGitHubCommentRequest
    ) -> Request<GitHubCommentResponse> {
        Request(
            method: .post,
            path: "/api/github/repos/\(repo)/issues/\(number)/comments",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `GET /api/github/repos/{owner}/{repo}/assignees` — assignable users.
    public static func assignees(repo: String) -> Request<GitHubAssigneesResponse> {
        Request(method: .get, path: "/api/github/repos/\(repo)/assignees", auth: .bearer)
    }

    /// `GET /api/github/repos/{owner}/{repo}/labels` — the repo's labels.
    public static func labels(repo: String) -> Request<GitHubLabelsResponse> {
        Request(method: .get, path: "/api/github/repos/\(repo)/labels", auth: .bearer)
    }

    /// `GET /api/github/repos/{owner}/{repo}/next-issue-number` — the number
    /// the next created issue will receive. Speculative route (P1-H — "if it
    /// exists"); callers tolerate a 404 at the service layer.
    public static func nextIssueNumber(repo: String) -> Request<GitHubNextIssueNumberResponse> {
        Request(method: .get, path: "/api/github/repos/\(repo)/next-issue-number", auth: .bearer)
    }
}
