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
/// Paths mirror the GitHub REST surface under the `/api/github` prefix
/// (`repo` is the `"owner/repo"` slug, matching `GitHubListSource.repository`).
/// Response shapes are decoded tolerantly (see `GitHubDTO.swift`) because they
/// are unverified against a live linked account. Auth: all `.bearer`.
public enum GitHub {

    /// `GET /api/github/repos` — repositories the linked account can access.
    public static func repos() -> Request<GitHubReposResponse> {
        Request(method: .get, path: "/api/github/repos", auth: .bearer)
    }

    /// `GET /api/github/repos/{owner}/{repo}/issues` — issues for a repo,
    /// filtered by `state` (`"open"` / `"closed"` / `"all"`) when supplied.
    public static func issues(repo: String, state: String? = nil) -> Request<GitHubIssuesResponse> {
        Request(
            method: .get,
            path: "/api/github/repos/\(repo)/issues",
            query: [.string("state", state)],
            auth: .bearer
        )
    }

    /// `POST /api/github/repos/{owner}/{repo}/issues` — create an issue.
    public static func createIssue(
        repo: String,
        _ body: CreateGitHubIssueRequest
    ) -> Request<GitHubIssueResponse> {
        Request(
            method: .post,
            path: "/api/github/repos/\(repo)/issues",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `PATCH /api/github/repos/{owner}/{repo}/issues/{number}` — edit an
    /// issue's title/body/state/labels/assignees (only the supplied fields).
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
