import Foundation
import InterlinedKit

// MARK: - GitHub issue-integration domain models (work-consolidation.md G4)
//
// Value-typed projections of the kit `GitHub*DTO` shapes for the App layer —
// repos, issues, labels, assignable users, and comments — plus the client-side
// input values (`GitHubIssueDraft` / `GitHubIssueUpdate`) the composer and the
// "create issue from message" action build. Mapping drops entries that lack the
// identifying field (a repo with no name, an issue with no number, a user with
// no login), so the App never renders a half-formed row.

// MARK: - GitHubIssueState

/// The lifecycle state of an issue. `.other` guards against an unexpected
/// server token so the client never crashes on a new state value.
public enum GitHubIssueState: String, Sendable, Equatable, Hashable {
    case open
    case closed
    case other

    public init(_ raw: String?) {
        switch raw?.lowercased() {
        case "open": self = .open
        case "closed": self = .closed
        default: self = .other
        }
    }
}

/// The `state` filter for listing issues (`GET .../issues?state=`).
public enum GitHubIssueFilter: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case open
    case closed
    case all

    public var id: String { rawValue }

    /// The `state` query value the API expects.
    public var queryValue: String { rawValue }
}

// MARK: - GitHubActor

/// A GitHub account — an issue author or an assignable user.
public struct GitHubActor: Sendable, Equatable, Hashable, Identifiable {
    public let login: String
    public let avatarURL: URL?

    public var id: String { login }

    public init(login: String, avatarURL: URL? = nil) {
        self.login = login
        self.avatarURL = avatarURL
    }
}

extension GitHubActor {
    /// Fails when the DTO carries no `login` — an unusable actor.
    public init?(from dto: GitHubUserDTO) {
        guard let login = dto.login, !login.isEmpty else { return nil }
        self.init(login: login, avatarURL: dto.avatarUrl.flatMap(URL.init(string:)))
    }
}

// MARK: - GitHubLabel

/// A GitHub issue label.
public struct GitHubLabel: Sendable, Equatable, Hashable, Identifiable {
    public let name: String
    /// Hex color without a leading `#`, when the API supplies one.
    public let color: String?

    public var id: String { name }

    public init(name: String, color: String? = nil) {
        self.name = name
        self.color = color
    }
}

extension GitHubLabel {
    public init?(from dto: GitHubLabelDTO) {
        guard let name = dto.name, !name.isEmpty else { return nil }
        self.init(name: name, color: dto.color)
    }
}

// MARK: - GitHubRepo

/// A GitHub repository the linked account can access.
public struct GitHubRepo: Sendable, Equatable, Hashable, Identifiable {
    /// The `"owner/repo"` slug — the value threaded into every issue call.
    public let fullName: String
    public let name: String
    public let owner: String
    public let isPrivate: Bool
    public let defaultBranch: String?

    public var id: String { fullName }

    public init(fullName: String, name: String, owner: String, isPrivate: Bool = false, defaultBranch: String? = nil) {
        self.fullName = fullName
        self.name = name
        self.owner = owner
        self.isPrivate = isPrivate
        self.defaultBranch = defaultBranch
    }
}

extension GitHubRepo {
    public init?(from dto: GitHubRepoDTO) {
        // Reconstruct the `owner/repo` slug from whatever the DTO provides.
        let full = dto.fullName ?? [dto.owner, dto.name].compactMap { $0 }.joined(separator: "/")
        guard full.contains("/") else { return nil }
        let parts = full.split(separator: "/", maxSplits: 1).map(String.init)
        self.init(
            fullName: full,
            name: dto.name ?? parts.last ?? full,
            owner: dto.owner ?? parts.first ?? "",
            isPrivate: dto.isPrivate ?? false,
            defaultBranch: dto.defaultBranch
        )
    }
}

// MARK: - GitHubIssue

/// A GitHub issue rendered in a GitHub-backed list or the issue browser.
public struct GitHubIssue: Sendable, Equatable, Hashable, Identifiable {
    public let number: Int
    public let title: String
    public let body: String?
    public let state: GitHubIssueState
    public let url: URL?
    public let author: GitHubActor?
    public let labels: [GitHubLabel]
    public let assignees: [GitHubActor]
    public let commentCount: Int
    public let createdAt: Date?
    public let updatedAt: Date?

    public var id: Int { number }

    public init(
        number: Int,
        title: String,
        body: String? = nil,
        state: GitHubIssueState = .open,
        url: URL? = nil,
        author: GitHubActor? = nil,
        labels: [GitHubLabel] = [],
        assignees: [GitHubActor] = [],
        commentCount: Int = 0,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.number = number
        self.title = title
        self.body = body
        self.state = state
        self.url = url
        self.author = author
        self.labels = labels
        self.assignees = assignees
        self.commentCount = commentCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension GitHubIssue {
    /// Fails when the DTO carries no issue `number` — an unusable row.
    public init?(from dto: GitHubIssueDTO) {
        guard let number = dto.number else { return nil }
        self.init(
            number: number,
            title: dto.title ?? "",
            body: dto.body,
            state: GitHubIssueState(dto.state),
            url: dto.htmlUrl.flatMap(URL.init(string:)),
            author: dto.user.flatMap(GitHubActor.init(from:)),
            labels: dto.labels.compactMap(GitHubLabel.init(from:)),
            assignees: dto.assignees.compactMap(GitHubActor.init(from:)),
            commentCount: dto.comments ?? 0,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

// MARK: - GitHubComment

/// A comment posted on an issue (the result of `addComment`).
public struct GitHubComment: Sendable, Equatable, Hashable {
    public let id: Int?
    public let body: String
    public let author: GitHubActor?
    public let url: URL?
    public let createdAt: Date?

    public init(id: Int? = nil, body: String, author: GitHubActor? = nil, url: URL? = nil, createdAt: Date? = nil) {
        self.id = id
        self.body = body
        self.author = author
        self.url = url
        self.createdAt = createdAt
    }
}

extension GitHubComment {
    public init(from dto: GitHubCommentDTO) {
        self.init(
            id: dto.id,
            body: dto.body ?? "",
            author: dto.user.flatMap(GitHubActor.init(from:)),
            url: dto.htmlUrl.flatMap(URL.init(string:)),
            createdAt: dto.createdAt
        )
    }
}

// MARK: - Client-side inputs

/// A new issue the client is about to create.
public struct GitHubIssueDraft: Sendable, Equatable {
    public let title: String
    public let body: String?
    public let labels: [String]
    public let assignees: [String]

    public init(title: String, body: String? = nil, labels: [String] = [], assignees: [String] = []) {
        self.title = title
        self.body = body
        self.labels = labels
        self.assignees = assignees
    }
}

/// A partial edit to an existing issue — only the non-nil fields are sent.
public struct GitHubIssueUpdate: Sendable, Equatable {
    public var title: String?
    public var body: String?
    public var state: GitHubIssueState?
    public var labels: [String]?
    public var assignees: [String]?

    public init(
        title: String? = nil,
        body: String? = nil,
        state: GitHubIssueState? = nil,
        labels: [String]? = nil,
        assignees: [String]? = nil
    ) {
        self.title = title
        self.body = body
        self.state = state
        self.labels = labels
        self.assignees = assignees
    }
}

// MARK: - GitHubServiceError

/// Domain-level GitHub failures the App handles distinctly from a generic
/// `APIError`. `notLinked` is the translated `GET /api/github/repos` → 400
/// "GitHub account not linked" state — the App catches it to surface a
/// "Link GitHub" CTA that deep-links the existing native OAuth flow.
public enum GitHubServiceError: Error, Equatable, Sendable {
    case notLinked(message: String)
}
