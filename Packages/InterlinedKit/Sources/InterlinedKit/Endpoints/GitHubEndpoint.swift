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
///   • single-issue **update** and **comment** are FLAT too, but on a different
///     shape again — `/api/github/issues/{owner}/{repo}/{number}[/comments]`
///     (verified live 2026-09-06, work-consolidation.md §1c · V7). Note that
///     `updateIssue` only sets labels/assignees; see its doc comment.
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

    /// `PATCH /api/github/issues/{owner}/{repo}/{number}` — set an issue's
    /// **labels and/or assignees**.
    ///
    /// VERIFIED live 2026-09-06 (work-consolidation.md §1c · V7). The route is
    /// **flat** — `{owner}/{repo}/{number}` hang off `/api/github/issues`, they
    /// are not nested under `/api/github/repos`. `OPTIONS` reports
    /// `Allow: OPTIONS, PATCH`; the nested path this shipped with **404s**.
    ///
    /// - Important: despite the name, this is **not** a general issue editor.
    ///   The handler requires `labels` or `assignees` to be present and answers
    ///   `400 {"error":"labels or assignees required"}` to a body of `state`,
    ///   `title` or `body` alone. With `labels`/`assignees` present the request
    ///   is accepted and proxied to GitHub (the probe account got a
    ///   `403 "Must have admin rights to Repository."` from GitHub itself on a
    ///   repo it does not own — which confirms the route, the verb and the body
    ///   shape). **Close / reopen and title/body edits therefore still have no
    ///   live route**; `GitHubService.updateIssue` rejects those up front.
    ///   A 200 body could not be captured because the test account has no
    ///   admin-rights repository, so `GitHubIssueResponse` is left tolerant.
    public static func updateIssue(
        repo: String,
        number: Int,
        _ body: UpdateGitHubIssueRequest
    ) -> Request<GitHubIssueResponse> {
        Request(
            method: .patch,
            path: "/api/github/issues/\(repo)/\(number)",
            body: .json(body),
            auth: .bearer
        )
    }

    /// `POST /api/github/issues/{owner}/{repo}/{number}/comments` — comment on
    /// an issue.
    ///
    /// VERIFIED live 2026-09-06 (work-consolidation.md §1c · V7): the flat path
    /// is correct and `OPTIONS` reports `Allow: OPTIONS, POST`; the nested path
    /// this shipped with **404s**. A live `POST` reached GitHub's own comment
    /// logic (it came back `403 "Commenting is disabled on issues with more
    /// than 2500 comments"` for the public `octocat/hello-world#1`), proving the
    /// route, verb and `{ "body": … }` payload. As above, a 200 body was not
    /// capturable from the test account, so the decoder stays tolerant.
    public static func comment(
        repo: String,
        number: Int,
        _ body: CreateGitHubCommentRequest
    ) -> Request<GitHubCommentResponse> {
        Request(
            method: .post,
            path: "/api/github/issues/\(repo)/\(number)/comments",
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
