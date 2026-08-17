// CreateIssueFromMessageViewModel
//
// Drives `CreateIssueFromMessageView` — the "Create GitHub issue from message"
// overflow action (work-consolidation.md G4, App UI slice 2). Loads the linked
// account's repositories, pre-fills an issue title/body from the message (with
// a link back to the post), and creates the issue in the chosen repo via the
// domain `GitHubServicing` surface.
//
// Like `GitHubIssuesViewModel`, the unlinked-account state is first-class:
// `GitHubServiceError.notLinked` flips `linkState` so the view can show a
// "Link GitHub" CTA instead of a raw error. Depends only on `GitHubServicing`
// (+ the source `Message`), so it substitutes trivially in tests.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class CreateIssueFromMessageViewModel {

    enum LinkState: Equatable {
        case unknown
        case linked
        case notLinked
    }

    // MARK: - Dependencies

    private let github: GitHubServicing
    let message: Message

    // MARK: - Observable state

    private(set) var repos: [GitHubRepo] = []
    var selectedRepo: String?
    var title: String
    var body: String

    private(set) var isLoadingRepos: Bool = false
    private(set) var isCreating: Bool = false
    private(set) var error: Error?
    private(set) var linkState: LinkState = .unknown

    /// Set on a successful create — the view shows a confirmation with a link.
    private(set) var createdIssue: GitHubIssue?

    // MARK: - Init

    init(
        github: GitHubServicing,
        message: Message,
        webBaseURL: URL = URL(string: "https://interlinedlist.com")!
    ) {
        self.github = github
        self.message = message
        self.title = Self.suggestedTitle(from: message)
        self.body = Self.suggestedBody(from: message, permalink: Self.permalink(for: message, base: webBaseURL))
    }

    // MARK: - Loading

    /// Loads the linked account's repositories and preselects the first.
    func loadRepos() async {
        guard !isLoadingRepos else { return }
        isLoadingRepos = true
        defer { isLoadingRepos = false }
        do {
            repos = try await github.repositories()
            if selectedRepo == nil { selectedRepo = repos.first?.fullName }
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

    // MARK: - Create

    var canCreate: Bool {
        selectedRepo != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isCreating
    }

    /// Creates the issue in the selected repo. On success sets `createdIssue`.
    func create() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let repo = selectedRepo, !trimmedTitle.isEmpty, !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let issue = try await github.createIssue(
                repo: repo,
                GitHubIssueDraft(title: trimmedTitle, body: trimmedBody.isEmpty ? nil : trimmedBody)
            )
            createdIssue = issue
            error = nil
        } catch let error as GitHubServiceError {
            handle(error)
        } catch {
            self.error = error
        }
    }

    /// Called by the view after a successful "Link GitHub" flow.
    func reloadAfterLink() async {
        linkState = .unknown
        await loadRepos()
    }

    // MARK: - Prefill

    static func suggestedTitle(from message: Message) -> String {
        let firstLine = message.text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let base = firstLine.isEmpty ? "Post by @\(message.author.username)" : firstLine
        return base.count > 100 ? String(base.prefix(99)) + "…" : base
    }

    static func suggestedBody(from message: Message, permalink: URL?) -> String {
        var parts: [String] = []
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
        parts.append("---")
        if let permalink {
            parts.append("From @\(message.author.username) on InterlinedList: \(permalink.absoluteString)")
        } else {
            parts.append("From @\(message.author.username) on InterlinedList")
        }
        return parts.joined(separator: "\n\n")
    }

    static func permalink(for message: Message, base: URL) -> URL? {
        base.appendingPathComponent("messages").appendingPathComponent(message.id)
    }

    // MARK: - Helpers

    private func handle(_ error: GitHubServiceError) {
        switch error {
        case .notLinked:
            linkState = .notLinked
        }
    }
}
