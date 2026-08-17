// GitHubIssuesViewModel
//
// Drives `GitHubIssuesView` — the issue browser for a GitHub-backed list
// (work-consolidation.md G4). Given the list's `"owner/repo"` slug it lists
// issues (filtered by state), creates new issues, and posts comments, all via
// the domain `GitHubServicing` surface.
//
// The unlinked-account state is first-class: when `GitHubServicing` reports
// `GitHubServiceError.notLinked`, the view model flips `linkState` to
// `.notLinked` so the view can show a "Link GitHub" CTA (which reuses the
// existing `LinkedAccountsViewModel` native OAuth flow) instead of a raw error.
//
// Depends only on `GitHubServicing`, so it is trivially substitutable in tests
// with `StubGitHubService`; the linking flow lives in the view, reusing the
// already-tested `LinkedAccountsViewModel`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class GitHubIssuesViewModel {

    /// Whether the account can reach GitHub. `.unknown` before the first load;
    /// `.notLinked` drives the "Link GitHub" CTA.
    enum LinkState: Equatable {
        case unknown
        case linked
        case notLinked
    }

    // MARK: - Dependencies

    private let github: GitHubServicing

    /// The `"owner/repo"` slug this browser is scoped to.
    let repo: String

    // MARK: - Observable state

    private(set) var issues: [GitHubIssue] = []
    private(set) var filter: GitHubIssueFilter = .open
    private(set) var isLoading: Bool = false
    private(set) var error: Error?
    private(set) var linkState: LinkState = .unknown

    /// New-issue composer fields (bound by the view).
    var newIssueTitle: String = ""
    var newIssueBody: String = ""
    private(set) var isCreating: Bool = false

    /// True while a comment post is in flight.
    private(set) var isCommenting: Bool = false

    // MARK: - Init

    init(github: GitHubServicing, repo: String) {
        self.github = github
        self.repo = repo
    }

    // MARK: - Loading

    /// Loads issues for the current `filter`. Translates the unlinked state
    /// into `linkState = .notLinked`; ignores cooperative cancellation.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            issues = try await github.issues(repo: repo, state: filter)
            linkState = .linked
            error = nil
        } catch let error as GitHubServiceError {
            handle(error)
        } catch is CancellationError {
            // View teardown — not a failure.
        } catch {
            self.error = error
        }
    }

    /// Switches the state filter and reloads. No-op if unchanged.
    func setFilter(_ filter: GitHubIssueFilter) async {
        guard filter != self.filter else { return }
        self.filter = filter
        await load()
    }

    // MARK: - Create

    /// Whether the New Issue action should be enabled.
    var canCreateIssue: Bool {
        !newIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }

    /// Creates an issue from the composer fields. On success prepends it to the
    /// visible list (unless the filter is `.closed`, where a new open issue
    /// wouldn't belong) and clears the composer.
    func createIssue() async {
        let title = newIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        let body = newIssueBody.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let issue = try await github.createIssue(
                repo: repo,
                GitHubIssueDraft(title: title, body: body.isEmpty ? nil : body)
            )
            if filter != .closed {
                issues.insert(issue, at: 0)
            }
            newIssueTitle = ""
            newIssueBody = ""
            error = nil
        } catch let error as GitHubServiceError {
            handle(error)
        } catch {
            self.error = error
        }
    }

    // MARK: - Comment

    /// Posts a comment on `issue` and optimistically bumps its comment count.
    func addComment(to issue: GitHubIssue, body: String) async {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isCommenting else { return }
        isCommenting = true
        defer { isCommenting = false }
        do {
            _ = try await github.addComment(repo: repo, number: issue.number, body: text)
            bumpCommentCount(of: issue.number)
            error = nil
        } catch let error as GitHubServiceError {
            handle(error)
        } catch {
            self.error = error
        }
    }

    /// Called by the view after a successful "Link GitHub" flow to re-attempt
    /// the load now that an identity exists.
    func reloadAfterLink() async {
        linkState = .unknown
        await load()
    }

    // MARK: - Helpers

    private func handle(_ error: GitHubServiceError) {
        switch error {
        case .notLinked:
            linkState = .notLinked
        }
    }

    private func bumpCommentCount(of number: Int) {
        guard let index = issues.firstIndex(where: { $0.number == number }) else { return }
        let old = issues[index]
        issues[index] = GitHubIssue(
            number: old.number,
            title: old.title,
            body: old.body,
            state: old.state,
            url: old.url,
            author: old.author,
            labels: old.labels,
            assignees: old.assignees,
            commentCount: old.commentCount + 1,
            createdAt: old.createdAt,
            updatedAt: old.updatedAt
        )
    }
}
