import Foundation
import InterlinedKit

// MARK: - GitHubServicing

/// The GitHub issue-integration surface (work-consolidation.md G4) — browse the
/// linked account's repos, list/create/edit issues, comment, and read the label
/// and assignee catalogs for a repo.
///
/// **Linked-identity precondition.** Every call requires a linked GitHub
/// identity; the live API answers an unlinked account with 400 "GitHub account
/// not linked". The service translates that (and the equivalent 403) into
/// `GitHubServiceError.notLinked`, so the App can present a "Link GitHub" CTA
/// that deep-links the existing native OAuth flow rather than surfacing a raw
/// error. Every other failure propagates as the underlying `APIError`.
public protocol GitHubServicing: Sendable {
    /// Repositories the linked account can access.
    func repositories() async throws -> [GitHubRepo]

    /// Issues for `repo` (an `"owner/repo"` slug), filtered by `state`.
    func issues(repo: String, state: GitHubIssueFilter) async throws -> [GitHubIssue]

    /// Creates an issue in `repo` and returns the created issue.
    func createIssue(repo: String, _ draft: GitHubIssueDraft) async throws -> GitHubIssue

    /// Applies a partial edit to issue `number` in `repo` (labels/assignees/
    /// state/title/body) and returns the updated issue.
    func updateIssue(repo: String, number: Int, _ update: GitHubIssueUpdate) async throws -> GitHubIssue

    /// Posts a comment on issue `number` in `repo`.
    func addComment(repo: String, number: Int, body: String) async throws -> GitHubComment

    /// Users assignable to issues in `repo`.
    func assignableUsers(repo: String) async throws -> [GitHubActor]

    /// The label catalog for `repo`.
    func labels(repo: String) async throws -> [GitHubLabel]

    /// The number the next created issue will receive, or `nil` when the
    /// backend does not expose the (speculative, P1-H) route.
    func nextIssueNumber(repo: String) async throws -> Int?
}

extension GitHubServicing {
    /// Convenience: list open issues.
    public func issues(repo: String) async throws -> [GitHubIssue] {
        try await issues(repo: repo, state: .open)
    }
}

// MARK: - GitHubService

public final class GitHubService: GitHubServicing {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func repositories() async throws -> [GitHubRepo] {
        try await mappingNotLinked {
            let response = try await api.send(GitHub.repos())
            return response.repos.compactMap(GitHubRepo.init(from:))
        }
    }

    public func issues(repo: String, state: GitHubIssueFilter) async throws -> [GitHubIssue] {
        try await mappingNotLinked {
            let response = try await api.send(GitHub.issues(repo: repo, state: state.queryValue))
            return response.issues.compactMap(GitHubIssue.init(from:))
        }
    }

    public func createIssue(repo: String, _ draft: GitHubIssueDraft) async throws -> GitHubIssue {
        try await mappingNotLinked {
            let request = CreateGitHubIssueRequest(
                title: draft.title,
                body: draft.body,
                labels: draft.labels.isEmpty ? nil : draft.labels,
                assignees: draft.assignees.isEmpty ? nil : draft.assignees
            )
            let response = try await api.send(GitHub.createIssue(repo: repo, request))
            return try Self.require(GitHubIssue(from: response.issue), context: "created issue")
        }
    }

    public func updateIssue(repo: String, number: Int, _ update: GitHubIssueUpdate) async throws -> GitHubIssue {
        try await mappingNotLinked {
            let request = UpdateGitHubIssueRequest(
                title: update.title,
                body: update.body,
                state: update.state.flatMap(Self.stateValue),
                labels: update.labels,
                assignees: update.assignees
            )
            let response = try await api.send(GitHub.updateIssue(repo: repo, number: number, request))
            return try Self.require(GitHubIssue(from: response.issue), context: "updated issue")
        }
    }

    public func addComment(repo: String, number: Int, body: String) async throws -> GitHubComment {
        try await mappingNotLinked {
            let response = try await api.send(
                GitHub.comment(repo: repo, number: number, CreateGitHubCommentRequest(body: body))
            )
            return GitHubComment(from: response.comment)
        }
    }

    public func assignableUsers(repo: String) async throws -> [GitHubActor] {
        try await mappingNotLinked {
            let response = try await api.send(GitHub.assignees(repo: repo))
            return response.assignees.compactMap(GitHubActor.init(from:))
        }
    }

    public func labels(repo: String) async throws -> [GitHubLabel] {
        try await mappingNotLinked {
            let response = try await api.send(GitHub.labels(repo: repo))
            return response.labels.compactMap(GitHubLabel.init(from:))
        }
    }

    public func nextIssueNumber(repo: String) async throws -> Int? {
        do {
            return try await api.send(GitHub.nextIssueNumber(repo: repo)).number
        } catch let error as APIError {
            // The route is speculative (P1-H). Absence is not a failure.
            if case .notFound = error { return nil }
            if let notLinked = Self.notLinkedError(error) { throw notLinked }
            throw error
        }
    }

    // MARK: - Not-linked translation

    /// Runs `body`, translating the unlinked-account 400/403 into
    /// `GitHubServiceError.notLinked`. Every other error propagates unchanged.
    private func mappingNotLinked<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as APIError {
            if let notLinked = Self.notLinkedError(error) { throw notLinked }
            throw error
        }
    }

    /// Returns a `.notLinked` error when `error` is the unlinked-account state,
    /// else `nil`. The server phrases it "GitHub account not linked" on a 400;
    /// we match tolerantly (400/403 whose message mentions linking GitHub) so a
    /// minor wording change upstream still routes to the "Link GitHub" CTA.
    static func notLinkedError(_ error: APIError) -> GitHubServiceError? {
        let message: String?
        switch error {
        case .badRequest(let m), .forbidden(let m):
            message = m
        default:
            return nil
        }
        guard let lowered = message?.lowercased() else { return nil }
        let mentionsGitHub = lowered.contains("github")
        let mentionsUnlinked = lowered.contains("not linked")
            || lowered.contains("not connected")
            || lowered.contains("no linked")
            || (lowered.contains("link") && mentionsGitHub)
            || (lowered.contains("connect") && mentionsGitHub)
        guard mentionsUnlinked else { return nil }
        return .notLinked(message: message ?? "GitHub account not linked")
    }

    /// The wire `state` value for an issue update. `.other` (an unknown
    /// upstream state) is never sent back.
    private static func stateValue(_ state: GitHubIssueState) -> String? {
        switch state {
        case .open: return "open"
        case .closed: return "closed"
        case .other: return nil
        }
    }

    private static func require(_ issue: GitHubIssue?, context: String) throws -> GitHubIssue {
        guard let issue else {
            throw APIError.decoding(type: "GitHubIssue", message: "\(context) response had no issue number")
        }
        return issue
    }
}
