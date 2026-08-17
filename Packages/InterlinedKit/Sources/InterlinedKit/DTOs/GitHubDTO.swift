import Foundation

// MARK: - GitHub issue-integration DTOs (work-consolidation.md G4)
//
// The `/api/github/*` routes are DEPLOYED but UNDOCUMENTED for third-party
// clients (work-consolidation.md §2 · P1-H). `GET /api/github/repos` returns
// HTTP 400 `{ "error": "GitHub account not linked" }` until the account links a
// GitHub identity, which confirms the route exists but leaves the *success*
// shapes unverified against a live linked account.
//
// Because the exact envelope + field casing can only be finalized by live
// observation, the response DTOs below decode **tolerantly**:
//
//   • list responses accept either a named envelope (`{ repos: [...] }`, the
//     InterlinedList house style) OR a bare top-level array (the GitHub-raw
//     proxy style);
//   • object fields accept both camelCase (`avatarUrl`, `htmlUrl`, `createdAt`
//     — the InterlinedList normalization) AND GitHub-canonical snake_case
//     (`avatar_url`, `html_url`, `created_at`);
//   • every field is optional, so an unexpected shape degrades to `nil`
//     rather than throwing.
//
// The **request** bodies are client-controlled (mirroring the GitHub issue
// create/update/comment payloads the backend must accept), so they carry no
// such uncertainty. Once P1-H documents the live shapes, the tolerant decoders
// can be tightened.

// MARK: - Request bodies

/// `POST /api/github/repos/{owner}/{repo}/issues` — create an issue.
/// Optional fields are omitted from the JSON when `nil` (synthesized
/// `encodeIfPresent`), so an empty draft sends only `title`.
public struct CreateGitHubIssueRequest: Encodable, Sendable, Equatable {
    public let title: String
    public let body: String?
    public let labels: [String]?
    public let assignees: [String]?

    public init(title: String, body: String? = nil, labels: [String]? = nil, assignees: [String]? = nil) {
        self.title = title
        self.body = body
        self.labels = labels
        self.assignees = assignees
    }
}

/// `PATCH /api/github/repos/{owner}/{repo}/issues/{number}` — edit an issue.
/// Every field is optional; only the provided ones are sent, so a labels-only
/// update never clobbers the title/body. `state` is `"open"` or `"closed"`.
public struct UpdateGitHubIssueRequest: Encodable, Sendable, Equatable {
    public let title: String?
    public let body: String?
    public let state: String?
    public let labels: [String]?
    public let assignees: [String]?

    public init(
        title: String? = nil,
        body: String? = nil,
        state: String? = nil,
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

/// `POST /api/github/repos/{owner}/{repo}/issues/{number}/comments`.
public struct CreateGitHubCommentRequest: Encodable, Sendable, Equatable {
    public let body: String

    public init(body: String) {
        self.body = body
    }
}

// MARK: - Tolerant decoding helpers

/// A string-only coding key so a decoder can look a value up under any of
/// several candidate JSON key spellings (camelCase vs snake_case).
private struct GitHubAnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension KeyedDecodingContainer where Key == GitHubAnyKey {
    func firstString(_ keys: String...) -> String? {
        for key in keys {
            if let value = try? decodeIfPresent(String.self, forKey: GitHubAnyKey(key)) {
                return value
            }
        }
        return nil
    }

    func firstInt(_ keys: String...) -> Int? {
        for key in keys {
            if let value = try? decodeIfPresent(Int.self, forKey: GitHubAnyKey(key)) {
                return value
            }
        }
        return nil
    }

    func firstBool(_ keys: String...) -> Bool? {
        for key in keys {
            if let value = try? decodeIfPresent(Bool.self, forKey: GitHubAnyKey(key)) {
                return value
            }
        }
        return nil
    }

    func firstDate(_ keys: String...) -> Date? {
        for key in keys {
            if let value = try? decodeIfPresent(Date.self, forKey: GitHubAnyKey(key)) {
                return value
            }
        }
        return nil
    }

    func firstObject<T: Decodable>(_ type: T.Type, _ keys: String...) -> T? {
        for key in keys {
            if let value = try? decodeIfPresent(T.self, forKey: GitHubAnyKey(key)) {
                return value
            }
        }
        return nil
    }

    func firstArray<T: Decodable>(_ type: T.Type, _ keys: String...) -> [T]? {
        for key in keys {
            if let value = try? decodeIfPresent([T].self, forKey: GitHubAnyKey(key)) {
                return value
            }
        }
        return nil
    }
}

/// Decodes either a bare top-level `[T]` array or a named-envelope
/// `{ <key>: [T] }` (trying each candidate key), degrading to `[]`.
private func decodeGitHubList<T: Decodable>(
    _ decoder: Decoder,
    keys: [String]
) -> [T] {
    if let bare = try? [T](from: decoder) { return bare }
    guard let container = try? decoder.container(keyedBy: GitHubAnyKey.self) else { return [] }
    for key in keys {
        if let value = try? container.decodeIfPresent([T].self, forKey: GitHubAnyKey(key)) {
            return value
        }
    }
    return []
}

// MARK: - Response objects

/// A GitHub account (issue author or assignable user).
public struct GitHubUserDTO: Decodable, Sendable, Equatable {
    public let login: String?
    public let avatarUrl: String?

    public init(login: String? = nil, avatarUrl: String? = nil) {
        self.login = login
        self.avatarUrl = avatarUrl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GitHubAnyKey.self)
        login = c.firstString("login", "username", "name")
        avatarUrl = c.firstString("avatarUrl", "avatar_url", "avatar")
    }
}

/// A GitHub issue label.
public struct GitHubLabelDTO: Decodable, Sendable, Equatable {
    public let name: String?
    public let color: String?

    public init(name: String? = nil, color: String? = nil) {
        self.name = name
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        // Labels can arrive as objects (`{name,color}`) or bare strings.
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            self.name = name
            self.color = nil
            return
        }
        let c = try decoder.container(keyedBy: GitHubAnyKey.self)
        name = c.firstString("name", "label")
        color = c.firstString("color")
    }
}

/// A GitHub repository the linked account can access.
public struct GitHubRepoDTO: Decodable, Sendable, Equatable {
    public let fullName: String?
    public let name: String?
    public let owner: String?
    public let isPrivate: Bool?
    public let defaultBranch: String?

    public init(
        fullName: String? = nil,
        name: String? = nil,
        owner: String? = nil,
        isPrivate: Bool? = nil,
        defaultBranch: String? = nil
    ) {
        self.fullName = fullName
        self.name = name
        self.owner = owner
        self.isPrivate = isPrivate
        self.defaultBranch = defaultBranch
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GitHubAnyKey.self)
        fullName = c.firstString("fullName", "full_name")
        name = c.firstString("name")
        // `owner` may be a bare login string or the GitHub `{ login }` object.
        owner = c.firstString("owner") ?? c.firstObject(GitHubUserDTO.self, "owner")?.login
        isPrivate = c.firstBool("isPrivate", "private")
        defaultBranch = c.firstString("defaultBranch", "default_branch")
    }
}

/// A GitHub issue.
public struct GitHubIssueDTO: Decodable, Sendable, Equatable {
    public let number: Int?
    public let title: String?
    public let body: String?
    public let state: String?
    public let htmlUrl: String?
    public let user: GitHubUserDTO?
    public let labels: [GitHubLabelDTO]
    public let assignees: [GitHubUserDTO]
    public let comments: Int?
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        number: Int? = nil,
        title: String? = nil,
        body: String? = nil,
        state: String? = nil,
        htmlUrl: String? = nil,
        user: GitHubUserDTO? = nil,
        labels: [GitHubLabelDTO] = [],
        assignees: [GitHubUserDTO] = [],
        comments: Int? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.number = number
        self.title = title
        self.body = body
        self.state = state
        self.htmlUrl = htmlUrl
        self.user = user
        self.labels = labels
        self.assignees = assignees
        self.comments = comments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GitHubAnyKey.self)
        number = c.firstInt("number")
        title = c.firstString("title")
        body = c.firstString("body")
        state = c.firstString("state")
        htmlUrl = c.firstString("htmlUrl", "html_url", "url")
        user = c.firstObject(GitHubUserDTO.self, "user", "author")
        labels = c.firstArray(GitHubLabelDTO.self, "labels") ?? []
        assignees = c.firstArray(GitHubUserDTO.self, "assignees") ?? []
        comments = c.firstInt("comments", "commentCount", "comment_count")
        createdAt = c.firstDate("createdAt", "created_at")
        updatedAt = c.firstDate("updatedAt", "updated_at")
    }
}

/// A comment posted on a GitHub issue.
public struct GitHubCommentDTO: Decodable, Sendable, Equatable {
    public let id: Int?
    public let body: String?
    public let user: GitHubUserDTO?
    public let htmlUrl: String?
    public let createdAt: Date?

    public init(
        id: Int? = nil,
        body: String? = nil,
        user: GitHubUserDTO? = nil,
        htmlUrl: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.body = body
        self.user = user
        self.htmlUrl = htmlUrl
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GitHubAnyKey.self)
        id = c.firstInt("id")
        body = c.firstString("body")
        user = c.firstObject(GitHubUserDTO.self, "user", "author")
        htmlUrl = c.firstString("htmlUrl", "html_url", "url")
        createdAt = c.firstDate("createdAt", "created_at")
    }
}

// MARK: - Response envelopes (keyed-or-bare tolerant)

/// `GET /api/github/repos` — `{ repos: [...] }` or a bare `[...]`.
public struct GitHubReposResponse: Decodable, Sendable, Equatable {
    public let repos: [GitHubRepoDTO]
    public init(repos: [GitHubRepoDTO]) { self.repos = repos }
    public init(from decoder: Decoder) throws {
        repos = decodeGitHubList(decoder, keys: ["repos", "repositories", "data"])
    }
}

/// `GET /api/github/repos/{repo}/issues` — `{ issues: [...] }` or a bare `[...]`.
public struct GitHubIssuesResponse: Decodable, Sendable, Equatable {
    public let issues: [GitHubIssueDTO]
    public init(issues: [GitHubIssueDTO]) { self.issues = issues }
    public init(from decoder: Decoder) throws {
        issues = decodeGitHubList(decoder, keys: ["issues", "data"])
    }
}

/// A single-issue response (`POST`/`PATCH`) — `{ issue: {...} }` or a bare issue.
public struct GitHubIssueResponse: Decodable, Sendable, Equatable {
    public let issue: GitHubIssueDTO
    public init(issue: GitHubIssueDTO) { self.issue = issue }
    public init(from decoder: Decoder) throws {
        if let bare = try? GitHubIssueDTO(from: decoder), bare.number != nil {
            issue = bare
            return
        }
        let c = try decoder.container(keyedBy: GitHubAnyKey.self)
        issue = try (c.firstObject(GitHubIssueDTO.self, "issue", "data") ?? GitHubIssueDTO(from: decoder))
    }
}

/// A single-comment response — `{ comment: {...} }` or a bare comment.
public struct GitHubCommentResponse: Decodable, Sendable, Equatable {
    public let comment: GitHubCommentDTO
    public init(comment: GitHubCommentDTO) { self.comment = comment }
    public init(from decoder: Decoder) throws {
        if let bare = try? GitHubCommentDTO(from: decoder), bare.body != nil || bare.id != nil {
            comment = bare
            return
        }
        let c = try decoder.container(keyedBy: GitHubAnyKey.self)
        comment = try (c.firstObject(GitHubCommentDTO.self, "comment", "data") ?? GitHubCommentDTO(from: decoder))
    }
}

/// `GET /api/github/repos/{repo}/assignees` — `{ assignees: [...] }` or bare.
public struct GitHubAssigneesResponse: Decodable, Sendable, Equatable {
    public let assignees: [GitHubUserDTO]
    public init(assignees: [GitHubUserDTO]) { self.assignees = assignees }
    public init(from decoder: Decoder) throws {
        assignees = decodeGitHubList(decoder, keys: ["assignees", "users", "data"])
    }
}

/// `GET /api/github/repos/{repo}/labels` — `{ labels: [...] }` or bare.
public struct GitHubLabelsResponse: Decodable, Sendable, Equatable {
    public let labels: [GitHubLabelDTO]
    public init(labels: [GitHubLabelDTO]) { self.labels = labels }
    public init(from decoder: Decoder) throws {
        labels = decodeGitHubList(decoder, keys: ["labels", "data"])
    }
}

/// `GET /api/github/repos/{repo}/next-issue-number` — `{ nextIssueNumber: N }`,
/// `{ number: N }`, or a bare integer. Speculative route (P1-H — "if it
/// exists"); the client tolerates its absence at the service layer.
public struct GitHubNextIssueNumberResponse: Decodable, Sendable, Equatable {
    public let number: Int
    public init(number: Int) { self.number = number }
    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let bare = try? single.decode(Int.self) {
            number = bare
            return
        }
        let c = try decoder.container(keyedBy: GitHubAnyKey.self)
        number = c.firstInt("nextIssueNumber", "next_issue_number", "number", "next") ?? 0
    }
}
