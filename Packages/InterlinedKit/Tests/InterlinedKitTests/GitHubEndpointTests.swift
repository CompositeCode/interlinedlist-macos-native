import XCTest
@testable import InterlinedKit

/// BDD tests for the GitHub issue-integration endpoint group (work-consolidation.md G4).
///
/// The request contracts (path/method/auth/body) are verified precisely — the
/// client controls them. The response decoders are exercised against BOTH the
/// InterlinedList house style (camelCase named envelopes) AND the GitHub-raw
/// proxy style (snake_case bare arrays), since the live shape is unverified
/// (P1-H) and the DTOs decode tolerantly.
final class GitHubEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport(),
        tokenStore: TokenStore = InMemoryTokenStore(initial: "il_tok_abc")
    ) -> (APIClient, StubHTTPDataTransport) {
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: transport, authTransport: auth)
        return (client, transport)
    }

    // MARK: - Request contracts

    func test_givenBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(GitHub.repos().path, "/api/github/repos")
        XCTAssertEqual(GitHub.repos().method, .get)
        XCTAssertEqual(GitHub.repos().auth, .bearer)

        let issues = GitHub.issues(repo: "octocat/hello", state: "open")
        XCTAssertEqual(issues.path, "/api/github/repos/octocat/hello/issues")
        XCTAssertEqual(issues.method, .get)
        XCTAssertEqual(issues.query.first(where: { $0.name == "state" })?.value, "open")

        let create = GitHub.createIssue(repo: "octocat/hello", CreateGitHubIssueRequest(title: "T"))
        XCTAssertEqual(create.path, "/api/github/repos/octocat/hello/issues")
        XCTAssertEqual(create.method, .post)

        let update = GitHub.updateIssue(repo: "octocat/hello", number: 42, UpdateGitHubIssueRequest(state: "closed"))
        XCTAssertEqual(update.path, "/api/github/repos/octocat/hello/issues/42")
        XCTAssertEqual(update.method, .patch)

        let comment = GitHub.comment(repo: "octocat/hello", number: 42, CreateGitHubCommentRequest(body: "hi"))
        XCTAssertEqual(comment.path, "/api/github/repos/octocat/hello/issues/42/comments")
        XCTAssertEqual(comment.method, .post)

        XCTAssertEqual(GitHub.assignees(repo: "octocat/hello").path, "/api/github/repos/octocat/hello/assignees")
        XCTAssertEqual(GitHub.labels(repo: "octocat/hello").path, "/api/github/repos/octocat/hello/labels")
        XCTAssertEqual(GitHub.nextIssueNumber(repo: "octocat/hello").path, "/api/github/repos/octocat/hello/next-issue-number")
    }

    func test_givenIssuesWithoutState_whenBuilt_thenOmitsStateQuery() {
        let issues = GitHub.issues(repo: "octocat/hello")
        XCTAssertNil(issues.query.first(where: { $0.name == "state" })?.value)
    }

    // MARK: - Request body encoding

    func test_givenDraft_whenCreateIssueSent_thenEncodesTitleBodyLabelsAssignees() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"number":1,"title":"T"}"#))

        _ = try await client.send(GitHub.createIssue(
            repo: "octocat/hello",
            CreateGitHubIssueRequest(title: "Bug", body: "details", labels: ["bug"], assignees: ["octocat"])
        ))

        let received = await transport.received
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(received[0].httpBody)) as? [String: Any]
        XCTAssertEqual(json?["title"] as? String, "Bug")
        XCTAssertEqual(json?["body"] as? String, "details")
        XCTAssertEqual(json?["labels"] as? [String], ["bug"])
        XCTAssertEqual(json?["assignees"] as? [String], ["octocat"])
        XCTAssertEqual(received[0].httpMethod, "POST")
    }

    func test_givenTitleOnlyDraft_whenCreateIssueSent_thenOmitsNilFields() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"number":1,"title":"T"}"#))

        _ = try await client.send(GitHub.createIssue(repo: "o/r", CreateGitHubIssueRequest(title: "Just a title")))

        let received = await transport.received
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(received[0].httpBody)) as? [String: Any]
        XCTAssertEqual(json?["title"] as? String, "Just a title")
        XCTAssertNil(json?["body"])
        XCTAssertNil(json?["labels"])
        XCTAssertNil(json?["assignees"])
    }

    func test_givenLabelsOnlyUpdate_whenSent_thenEncodesOnlyLabels() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"number":42,"title":"T"}"#))

        _ = try await client.send(GitHub.updateIssue(repo: "o/r", number: 42, UpdateGitHubIssueRequest(labels: ["p1"])))

        let received = await transport.received
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(received[0].httpBody)) as? [String: Any]
        XCTAssertEqual(json?["labels"] as? [String], ["p1"])
        XCTAssertNil(json?["title"])
        XCTAssertNil(json?["state"])
        XCTAssertEqual(received[0].httpMethod, "PATCH")
    }

    func test_givenComment_whenSent_thenEncodesBody() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"id":1,"body":"hi"}"#))

        _ = try await client.send(GitHub.comment(repo: "o/r", number: 7, CreateGitHubCommentRequest(body: "hi there")))

        let received = await transport.received
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(received[0].httpBody)) as? [String: Any]
        XCTAssertEqual(json?["body"] as? String, "hi there")
    }

    // MARK: - Response decoding (InterlinedList house style — camelCase envelope)

    func test_givenNamedEnvelopeCamelCase_whenReposSent_thenDecodes() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"repos":[{"fullName":"octocat/hello","name":"hello","owner":"octocat","private":false,"defaultBranch":"main"}]}
        """#))

        let response = try await client.send(GitHub.repos())

        XCTAssertEqual(response.repos.map(\.fullName), ["octocat/hello"])
        XCTAssertEqual(response.repos.first?.owner, "octocat")
        XCTAssertEqual(response.repos.first?.isPrivate, false)
        XCTAssertEqual(response.repos.first?.defaultBranch, "main")
    }

    func test_givenCamelCaseIssueEnvelope_whenIssuesSent_thenDecodesNestedFields() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"issues":[{
          "number":13,"title":"Crash on launch","body":"stack trace","state":"open",
          "htmlUrl":"https://github.com/octocat/hello/issues/13",
          "user":{"login":"octocat","avatarUrl":"https://cdn/a.png"},
          "labels":[{"name":"bug","color":"d73a4a"}],
          "assignees":[{"login":"hubot","avatarUrl":null}],
          "comments":4,"createdAt":"2026-08-16T12:00:00Z","updatedAt":"2026-08-16T13:00:00Z"
        }]}
        """#))

        let response = try await client.send(GitHub.issues(repo: "octocat/hello", state: "open"))

        let issue = try XCTUnwrap(response.issues.first)
        XCTAssertEqual(issue.number, 13)
        XCTAssertEqual(issue.state, "open")
        XCTAssertEqual(issue.htmlUrl, "https://github.com/octocat/hello/issues/13")
        XCTAssertEqual(issue.user?.login, "octocat")
        XCTAssertEqual(issue.labels.first?.name, "bug")
        XCTAssertEqual(issue.assignees.first?.login, "hubot")
        XCTAssertEqual(issue.comments, 4)
        XCTAssertNotNil(issue.createdAt)
    }

    // MARK: - Response decoding (GitHub-raw proxy style — snake_case, bare arrays)

    func test_givenBareArraySnakeCase_whenReposSent_thenStillDecodes() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        [{"full_name":"octocat/hello","name":"hello","owner":{"login":"octocat"},"private":true,"default_branch":"trunk"}]
        """#))

        let response = try await client.send(GitHub.repos())

        XCTAssertEqual(response.repos.first?.fullName, "octocat/hello")
        XCTAssertEqual(response.repos.first?.owner, "octocat")   // owner object → login
        XCTAssertEqual(response.repos.first?.isPrivate, true)
        XCTAssertEqual(response.repos.first?.defaultBranch, "trunk")
    }

    func test_givenBareArraySnakeCaseIssues_whenSent_thenDecodesNestedFields() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        [{"number":99,"title":"Snake","state":"closed",
          "html_url":"https://github.com/o/r/issues/99",
          "user":{"login":"ghost","avatar_url":"https://cdn/g.png"},
          "labels":["needs-triage"],
          "created_at":"2026-08-16T12:00:00Z"}]
        """#))

        let response = try await client.send(GitHub.issues(repo: "o/r"))

        let issue = try XCTUnwrap(response.issues.first)
        XCTAssertEqual(issue.number, 99)
        XCTAssertEqual(issue.htmlUrl, "https://github.com/o/r/issues/99")
        XCTAssertEqual(issue.user?.avatarUrl, "https://cdn/g.png")
        XCTAssertEqual(issue.labels.first?.name, "needs-triage")  // bare-string label
        XCTAssertNotNil(issue.createdAt)
    }

    func test_givenBareIssueObject_whenCreateSent_thenUnwrapsIssue() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"number":7,"title":"Made it","state":"open"}"#))

        let response = try await client.send(GitHub.createIssue(repo: "o/r", CreateGitHubIssueRequest(title: "Made it")))

        XCTAssertEqual(response.issue.number, 7)
        XCTAssertEqual(response.issue.title, "Made it")
    }

    func test_givenWrappedIssueObject_whenCreateSent_thenUnwrapsIssue() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"issue":{"number":8,"title":"Wrapped"}}"#))

        let response = try await client.send(GitHub.createIssue(repo: "o/r", CreateGitHubIssueRequest(title: "Wrapped")))

        XCTAssertEqual(response.issue.number, 8)
        XCTAssertEqual(response.issue.title, "Wrapped")
    }

    func test_givenLabelsAndAssignees_whenSent_thenDecode() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"labels":[{"name":"bug","color":"f00"},{"name":"docs"}]}"#))
        await transport.enqueue(.json(#"{"assignees":[{"login":"octocat"},{"login":"hubot"}]}"#))

        let labels = try await client.send(GitHub.labels(repo: "o/r"))
        let assignees = try await client.send(GitHub.assignees(repo: "o/r"))

        XCTAssertEqual(labels.labels.map(\.name), ["bug", "docs"])
        XCTAssertEqual(assignees.assignees.compactMap(\.login), ["octocat", "hubot"])
    }

    func test_givenNextIssueNumber_whenSent_thenDecodesBareAndWrapped() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"nextIssueNumber":124}"#))
        await transport.enqueue(.json(#"125"#))

        let wrapped = try await client.send(GitHub.nextIssueNumber(repo: "o/r"))
        let bare = try await client.send(GitHub.nextIssueNumber(repo: "o/r"))

        XCTAssertEqual(wrapped.number, 124)
        XCTAssertEqual(bare.number, 125)
    }

    // MARK: - Unlinked / error state

    func test_givenNotLinked_whenReposSent_thenThrowsBadRequestWithMessage() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"GitHub account not linked"}"#, status: 400))

        do {
            _ = try await client.send(GitHub.repos())
            XCTFail("Expected badRequest")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "GitHub account not linked"))
        }
    }

    func test_givenEmptyBody_whenReposSent_thenDecodesEmpty() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{}"#))

        let response = try await client.send(GitHub.repos())

        XCTAssertTrue(response.repos.isEmpty)
    }
}
