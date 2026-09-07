import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `GitHubService` (work-consolidation.md G4).
final class GitHubServiceTests: XCTestCase {

    // MARK: - Repositories

    func test_givenRepos_whenLoading_thenMapsSlugsAndHitsReposPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"repos":[
          {"fullName":"octocat/hello","name":"hello","owner":"octocat","private":false},
          {"full_name":"octocat/world","name":"world","owner":{"login":"octocat"},"private":true}
        ]}
        """#)
        let service = GitHubService(api: api)

        let repos = try await service.repositories()

        XCTAssertEqual(repos.map(\.fullName), ["octocat/hello", "octocat/world"])
        XCTAssertEqual(repos.last?.isPrivate, true)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/github/repos")
    }

    func test_givenRepoMissingSlug_whenMapping_thenIsDropped() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"repos":[{"name":"orphan"},{"fullName":"o/keep","name":"keep","owner":"o"}]}"#)
        let service = GitHubService(api: api)

        let repos = try await service.repositories()

        XCTAssertEqual(repos.map(\.fullName), ["o/keep"])
    }

    // MARK: - Issues

    func test_givenIssues_whenLoading_thenMapsAndPassesStateQuery() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"issues":[{"number":13,"title":"Crash","state":"open",
          "htmlUrl":"https://github.com/o/r/issues/13",
          "user":{"login":"octocat","avatarUrl":"https://cdn/a.png"},
          "labels":[{"name":"bug","color":"f00"}],"assignees":[{"login":"hubot"}],"comments":2}]}
        """#)
        let service = GitHubService(api: api)

        let issues = try await service.issues(repo: "o/r", state: .all)

        let issue = try XCTUnwrap(issues.first)
        XCTAssertEqual(issue.number, 13)
        XCTAssertEqual(issue.state, .open)
        XCTAssertEqual(issue.author?.login, "octocat")
        XCTAssertEqual(issue.labels.map(\.name), ["bug"])
        XCTAssertEqual(issue.assignees.map(\.login), ["hubot"])
        XCTAssertEqual(issue.commentCount, 2)
        let recorded = await api.recorded
        // Flat issues route with `repo` as a query param (verified live 2026-08-17).
        XCTAssertEqual(recorded.first?.path, "/api/github/issues")
        XCTAssertEqual(recorded.first?.query["repo"], "o/r")
        XCTAssertEqual(recorded.first?.query["state"], "all")
    }

    func test_givenIssueMissingNumber_whenMapping_thenIsDropped() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"issues":[{"title":"no number"},{"number":5,"title":"ok"}]}"#)
        let service = GitHubService(api: api)

        let issues = try await service.issues(repo: "o/r", state: .open)

        XCTAssertEqual(issues.map(\.number), [5])
    }

    func test_givenUnknownState_whenMapping_thenFallsBackToOther() {
        XCTAssertEqual(GitHubIssueState("frozen"), .other)
        XCTAssertEqual(GitHubIssueState("OPEN"), .open)
        XCTAssertEqual(GitHubIssueState(nil), .other)
    }

    // MARK: - Create / update / comment

    func test_givenDraft_whenCreating_thenPostsAndReturnsIssue() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"number":21,"title":"New bug","state":"open"}"#)
        let service = GitHubService(api: api)

        let issue = try await service.createIssue(
            repo: "o/r",
            GitHubIssueDraft(title: "New bug", body: "detail", labels: ["bug"], assignees: ["octocat"])
        )

        XCTAssertEqual(issue.number, 21)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        // Flat issues route with `repo` as a query param (verified live 2026-08-17).
        XCTAssertEqual(recorded.first?.path, "/api/github/issues")
        XCTAssertEqual(recorded.first?.query["repo"], "o/r")
    }

    // The live `PATCH /api/github/issues/{owner}/{repo}/{number}` sets labels
    // and assignees only. A state/title/body-only body comes back
    // `400 "labels or assignees required"` (verified 2026-09-06 —
    // work-consolidation.md §1c · V7), so the service refuses it locally.
    func test_givenLabelUpdate_whenUpdating_thenPatchesFlatIssuePath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"number":21,"title":"New bug","state":"open"}"#)
        let service = GitHubService(api: api)

        let issue = try await service.updateIssue(
            repo: "o/r",
            number: 21,
            GitHubIssueUpdate(labels: ["bug"])
        )

        XCTAssertEqual(issue.number, 21)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PATCH")
        XCTAssertEqual(recorded.first?.path, "/api/github/issues/o/r/21")
    }

    func test_givenStateOnlyUpdate_whenUpdating_thenThrowsWithoutCallingAPI() async throws {
        let api = StubAPIClient()
        let service = GitHubService(api: api)

        do {
            _ = try await service.updateIssue(repo: "o/r", number: 21, GitHubIssueUpdate(state: .closed))
            XCTFail("Expected unsupportedIssueEdit")
        } catch let error as GitHubServiceError {
            XCTAssertEqual(error, .unsupportedIssueEdit)
        }

        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // Boundary: a title/body edit is refused on the same grounds — the route
    // ignores both unless labels/assignees accompany them.
    func test_givenTitleOnlyUpdate_whenUpdating_thenThrowsUnsupported() async throws {
        let api = StubAPIClient()
        let service = GitHubService(api: api)

        do {
            _ = try await service.updateIssue(repo: "o/r", number: 21, GitHubIssueUpdate(title: "Renamed"))
            XCTFail("Expected unsupportedIssueEdit")
        } catch let error as GitHubServiceError {
            XCTAssertEqual(error, .unsupportedIssueEdit)
        }
    }

    // Boundary: assignees alone is enough to satisfy the route's requirement.
    func test_givenAssigneesOnlyUpdate_whenUpdating_thenIsAccepted() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"number":21,"title":"New bug","state":"open"}"#)
        let service = GitHubService(api: api)

        _ = try await service.updateIssue(
            repo: "o/r",
            number: 21,
            GitHubIssueUpdate(assignees: ["octocat"])
        )

        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    func test_givenComment_whenAdding_thenPostsAndReturnsComment() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"id":100,"body":"thanks","user":{"login":"octocat"}}"#)
        let service = GitHubService(api: api)

        let comment = try await service.addComment(repo: "o/r", number: 21, body: "thanks")

        XCTAssertEqual(comment.body, "thanks")
        XCTAssertEqual(comment.author?.login, "octocat")
        let recorded = await api.recorded
        // Flat comment route, verified live 2026-09-06 (§1c · V7).
        XCTAssertEqual(recorded.first?.path, "/api/github/issues/o/r/21/comments")
    }

    // MARK: - Labels / assignees / next number

    func test_givenLabelsAndAssignees_whenLoading_thenMap() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"labels":[{"name":"bug"},{"color":"f00"}]}"#)   // 2nd has no name → dropped
        await api.enqueue(json: #"{"assignees":[{"login":"octocat"},{"avatarUrl":"x"}]}"#) // 2nd no login → dropped
        let service = GitHubService(api: api)

        let labels = try await service.labels(repo: "o/r")
        let users = try await service.assignableUsers(repo: "o/r")

        XCTAssertEqual(labels.map(\.name), ["bug"])
        XCTAssertEqual(users.map(\.login), ["octocat"])
    }

    func test_givenMissingNextNumberRoute_whenLoading_thenReturnsNil() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no such route"))
        let service = GitHubService(api: api)

        let number = try await service.nextIssueNumber(repo: "o/r")

        XCTAssertNil(number)
    }

    func test_givenNextNumber_whenLoading_thenReturnsValue() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"nextIssueNumber":124}"#)
        let service = GitHubService(api: api)

        let number = try await service.nextIssueNumber(repo: "o/r")

        XCTAssertEqual(number, 124)
    }

    // MARK: - Not-linked translation

    func test_givenUnlinked400_whenLoadingRepos_thenThrowsNotLinked() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "GitHub account not linked"))
        let service = GitHubService(api: api)

        do {
            _ = try await service.repositories()
            XCTFail("Expected notLinked")
        } catch let error as GitHubServiceError {
            XCTAssertEqual(error, .notLinked(message: "GitHub account not linked"))
        }
    }

    func test_givenUnlinked403_whenLoadingIssues_thenThrowsNotLinked() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "Please connect your GitHub account"))
        let service = GitHubService(api: api)

        do {
            _ = try await service.issues(repo: "o/r", state: .open)
            XCTFail("Expected notLinked")
        } catch let error as GitHubServiceError {
            guard case .notLinked = error else { return XCTFail("Expected notLinked, got \(error)") }
        }
    }

    func test_givenUnrelatedBadRequest_whenLoading_thenPropagatesAPIError() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "invalid state filter"))
        let service = GitHubService(api: api)

        do {
            _ = try await service.repositories()
            XCTFail("Expected APIError, not notLinked")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "invalid state filter"))
        }
    }

    func test_givenServerError_whenLoading_thenPropagates() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = GitHubService(api: api)

        do {
            _ = try await service.repositories()
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - notLinkedError classification (unit)

    func test_givenNotLinkedClassification_thenMatchesLinkingMessagesOnly() {
        XCTAssertNotNil(GitHubService.notLinkedError(.badRequest(serverMessage: "GitHub account not linked")))
        XCTAssertNotNil(GitHubService.notLinkedError(.forbidden(serverMessage: "Link your GitHub to continue")))
        XCTAssertNotNil(GitHubService.notLinkedError(.badRequest(serverMessage: "No linked GitHub identity")))
        XCTAssertNil(GitHubService.notLinkedError(.badRequest(serverMessage: "rate limit exceeded")))
        XCTAssertNil(GitHubService.notLinkedError(.notFound(serverMessage: "not linked")))
        XCTAssertNil(GitHubService.notLinkedError(.unauthorized(serverMessage: nil)))
    }
}
