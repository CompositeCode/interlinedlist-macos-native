import XCTest
import InterlinedDomain
import InterlinedKit
@testable import InterlinedList

/// BDD-named coverage for `GitHubIssuesViewModel` (work-consolidation.md G4).
@MainActor
final class GitHubIssuesViewModelTests: XCTestCase {

    private func makeIssue(_ number: Int, title: String = "T", state: GitHubIssueState = .open, comments: Int = 0) -> GitHubIssue {
        GitHubIssue(number: number, title: title, state: state, commentCount: comments)
    }

    // MARK: - Loading

    func test_givenIssues_whenLoading_thenPopulatesAndMarksLinked() async {
        let stub = StubGitHubService()
        stub.issuesResult = .success([makeIssue(3), makeIssue(1)])
        let vm = GitHubIssuesViewModel(github: stub, repo: "o/r")

        await vm.load()

        XCTAssertEqual(vm.issues.map(\.number), [3, 1])
        XCTAssertEqual(vm.linkState, .linked)
        XCTAssertNil(vm.error)
        XCTAssertEqual(stub.requestedStates, [.open])   // default filter
    }

    func test_givenNotLinked_whenLoading_thenSetsNotLinkedWithoutError() async {
        let stub = StubGitHubService()
        stub.issuesResult = .failure(GitHubServiceError.notLinked(message: "GitHub account not linked"))
        let vm = GitHubIssuesViewModel(github: stub, repo: "o/r")

        await vm.load()

        XCTAssertEqual(vm.linkState, .notLinked)
        XCTAssertTrue(vm.issues.isEmpty)
        XCTAssertNil(vm.error)
    }

    func test_givenServerError_whenLoading_thenSurfacesError() async {
        let stub = StubGitHubService()
        stub.issuesResult = .failure(APIError.httpStatus(code: 500, serverMessage: "boom"))
        let vm = GitHubIssuesViewModel(github: stub, repo: "o/r")

        await vm.load()

        XCTAssertNotNil(vm.error)
        XCTAssertNotEqual(vm.linkState, .notLinked)
    }

    func test_givenNewFilter_whenSet_thenReloadsWithThatState() async {
        let stub = StubGitHubService()
        stub.issuesResult = .success([makeIssue(1)])
        let vm = GitHubIssuesViewModel(github: stub, repo: "o/r")
        await vm.load()

        await vm.setFilter(.closed)

        XCTAssertEqual(vm.filter, .closed)
        XCTAssertEqual(stub.requestedStates, [.open, .closed])
    }

    func test_givenSameFilter_whenSet_thenDoesNotReload() async {
        let stub = StubGitHubService()
        let vm = GitHubIssuesViewModel(github: stub, repo: "o/r")
        await vm.load()

        await vm.setFilter(.open)   // already .open

        XCTAssertEqual(stub.requestedStates, [.open])
    }

    // MARK: - Create

    func test_givenBlankTitle_thenCannotCreate() {
        let vm = GitHubIssuesViewModel(github: StubGitHubService(), repo: "o/r")
        vm.newIssueTitle = "   "
        XCTAssertFalse(vm.canCreateIssue)
        vm.newIssueTitle = "Real title"
        XCTAssertTrue(vm.canCreateIssue)
    }

    func test_givenDraft_whenCreating_thenPrependsAndClearsComposer() async {
        let stub = StubGitHubService()
        stub.issuesResult = .success([makeIssue(1)])
        stub.createResult = .success(makeIssue(2, title: "Created"))
        let vm = GitHubIssuesViewModel(github: stub, repo: "o/r")
        await vm.load()
        vm.newIssueTitle = "Created"
        vm.newIssueBody = "body text"

        await vm.createIssue()

        XCTAssertEqual(vm.issues.map(\.number), [2, 1])   // prepended
        XCTAssertEqual(vm.newIssueTitle, "")
        XCTAssertEqual(vm.newIssueBody, "")
        XCTAssertEqual(stub.createdDrafts.first?.title, "Created")
        XCTAssertEqual(stub.createdDrafts.first?.body, "body text")
    }

    func test_givenClosedFilter_whenCreating_thenDoesNotPrependOpenIssue() async {
        let stub = StubGitHubService()
        stub.issuesResult = .success([makeIssue(1, state: .closed)])
        stub.createResult = .success(makeIssue(2, title: "New", state: .open))
        let vm = GitHubIssuesViewModel(github: stub, repo: "o/r")
        await vm.load()
        await vm.setFilter(.closed)
        vm.newIssueTitle = "New"

        await vm.createIssue()

        XCTAssertFalse(vm.issues.contains { $0.number == 2 })   // not shown under Closed
        XCTAssertEqual(stub.createdDrafts.count, 1)
    }

    func test_givenNotLinked_whenCreating_thenFlipsToNotLinked() async {
        let stub = StubGitHubService()
        stub.createResult = .failure(GitHubServiceError.notLinked(message: "not linked"))
        let vm = GitHubIssuesViewModel(github: stub, repo: "o/r")
        vm.newIssueTitle = "X"

        await vm.createIssue()

        XCTAssertEqual(vm.linkState, .notLinked)
    }

    // MARK: - Comment

    func test_givenComment_whenAdding_thenBumpsCountAndRecords() async {
        let stub = StubGitHubService()
        stub.issuesResult = .success([makeIssue(7, comments: 2)])
        let vm = GitHubIssuesViewModel(github: stub, repo: "o/r")
        await vm.load()

        await vm.addComment(to: makeIssue(7, comments: 2), body: "thanks!")

        XCTAssertEqual(vm.issues.first?.commentCount, 3)
        XCTAssertEqual(stub.comments.first?.number, 7)
        XCTAssertEqual(stub.comments.first?.body, "thanks!")
    }

    func test_givenBlankComment_whenAdding_thenNoop() async {
        let stub = StubGitHubService()
        stub.issuesResult = .success([makeIssue(7)])
        let vm = GitHubIssuesViewModel(github: stub, repo: "o/r")
        await vm.load()

        await vm.addComment(to: makeIssue(7), body: "   ")

        XCTAssertTrue(stub.comments.isEmpty)
    }

    // MARK: - Relink

    func test_givenNotLinked_whenReloadAfterLink_thenRetriesLoad() async {
        let stub = StubGitHubService()
        stub.issuesResult = .failure(GitHubServiceError.notLinked(message: "not linked"))
        let vm = GitHubIssuesViewModel(github: stub, repo: "o/r")
        await vm.load()
        XCTAssertEqual(vm.linkState, .notLinked)

        // Account is now linked; the next load succeeds.
        stub.issuesResult = .success([makeIssue(1)])
        await vm.reloadAfterLink()

        XCTAssertEqual(vm.linkState, .linked)
        XCTAssertEqual(vm.issues.map(\.number), [1])
    }
}
