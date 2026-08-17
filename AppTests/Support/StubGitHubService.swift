import Foundation
import InterlinedDomain

/// Programmable `GitHubServicing` double for App-layer tests (work-consolidation.md G4).
///
/// Each surface is backed by a `Result` the test sets; write actions default to
/// synthesizing a plausible value from their input so happy-path tests need
/// only set what they assert on. Every call is recorded for verification.
final class StubGitHubService: GitHubServicing, @unchecked Sendable {

    // MARK: - Programmable outcomes

    var reposResult: Result<[GitHubRepo], Error> = .success([])
    var issuesResult: Result<[GitHubIssue], Error> = .success([])
    var createResult: Result<GitHubIssue, Error>?
    var updateResult: Result<GitHubIssue, Error>?
    var commentResult: Result<GitHubComment, Error> = .success(GitHubComment(body: "ok"))
    var assigneesResult: Result<[GitHubActor], Error> = .success([])
    var labelsResult: Result<[GitHubLabel], Error> = .success([])
    var nextNumberResult: Result<Int?, Error> = .success(nil)

    // MARK: - Recording

    private(set) var requestedStates: [GitHubIssueFilter] = []
    private(set) var createdDrafts: [GitHubIssueDraft] = []
    private(set) var updates: [(number: Int, update: GitHubIssueUpdate)] = []
    private(set) var comments: [(number: Int, body: String)] = []

    // MARK: - GitHubServicing

    func repositories() async throws -> [GitHubRepo] {
        try reposResult.get()
    }

    func issues(repo: String, state: GitHubIssueFilter) async throws -> [GitHubIssue] {
        requestedStates.append(state)
        return try issuesResult.get()
    }

    func createIssue(repo: String, _ draft: GitHubIssueDraft) async throws -> GitHubIssue {
        createdDrafts.append(draft)
        if let createResult { return try createResult.get() }
        return GitHubIssue(number: 1, title: draft.title, body: draft.body, state: .open)
    }

    func updateIssue(repo: String, number: Int, _ update: GitHubIssueUpdate) async throws -> GitHubIssue {
        updates.append((number, update))
        if let updateResult { return try updateResult.get() }
        return GitHubIssue(number: number, title: "Updated", state: update.state ?? .open)
    }

    func addComment(repo: String, number: Int, body: String) async throws -> GitHubComment {
        comments.append((number, body))
        return try commentResult.get()
    }

    func assignableUsers(repo: String) async throws -> [GitHubActor] {
        try assigneesResult.get()
    }

    func labels(repo: String) async throws -> [GitHubLabel] {
        try labelsResult.get()
    }

    func nextIssueNumber(repo: String) async throws -> Int? {
        try nextNumberResult.get()
    }
}
