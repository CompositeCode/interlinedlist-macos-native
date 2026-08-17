import XCTest
import InterlinedDomain
import InterlinedKit
@testable import InterlinedList

/// BDD-named coverage for `CreateIssueFromMessageViewModel` (work-consolidation.md G4).
@MainActor
final class CreateIssueFromMessageViewModelTests: XCTestCase {

    private func message(text: String = "First line\nSecond line", username: String = "ada", id: String = "msg-1") -> Message {
        MessageFixtures.message(id: id, author: MessageFixtures.author(username: username), text: text)
    }

    private func makeVM(_ stub: StubGitHubService, message: Message? = nil) -> CreateIssueFromMessageViewModel {
        CreateIssueFromMessageViewModel(
            github: stub,
            message: message ?? self.message(),
            webBaseURL: URL(string: "https://example.test")!
        )
    }

    // MARK: - Prefill

    func test_givenMessage_whenInit_thenPrefillsTitleFromFirstLineAndBodyWithLink() {
        let vm = makeVM(StubGitHubService(), message: message(text: "Fix the parser\nmore detail", username: "ada", id: "abc"))

        XCTAssertEqual(vm.title, "Fix the parser")
        XCTAssertTrue(vm.body.contains("more detail"))
        XCTAssertTrue(vm.body.contains("https://example.test/messages/abc"))
        XCTAssertTrue(vm.body.contains("@ada"))
    }

    func test_givenEmptyMessage_whenInit_thenTitleFallsBackToAuthor() {
        let vm = makeVM(StubGitHubService(), message: message(text: "   ", username: "grace"))
        XCTAssertEqual(vm.title, "Post by @grace")
    }

    func test_givenLongFirstLine_whenInit_thenTitleTruncated() {
        let long = String(repeating: "x", count: 200)
        let vm = makeVM(StubGitHubService(), message: message(text: long))
        XCTAssertLessThanOrEqual(vm.title.count, 100)
        XCTAssertTrue(vm.title.hasSuffix("…"))
    }

    // MARK: - Loading repos

    func test_givenRepos_whenLoading_thenPreselectsFirstAndMarksLinked() async {
        let stub = StubGitHubService()
        stub.reposResult = .success([
            GitHubRepo(fullName: "o/one", name: "one", owner: "o"),
            GitHubRepo(fullName: "o/two", name: "two", owner: "o")
        ])
        let vm = makeVM(stub)

        await vm.loadRepos()

        XCTAssertEqual(vm.repos.map(\.fullName), ["o/one", "o/two"])
        XCTAssertEqual(vm.selectedRepo, "o/one")
        XCTAssertEqual(vm.linkState, .linked)
    }

    func test_givenNotLinked_whenLoading_thenSetsNotLinked() async {
        let stub = StubGitHubService()
        stub.reposResult = .failure(GitHubServiceError.notLinked(message: "GitHub account not linked"))
        let vm = makeVM(stub)

        await vm.loadRepos()

        XCTAssertEqual(vm.linkState, .notLinked)
        XCTAssertTrue(vm.repos.isEmpty)
        XCTAssertNil(vm.error)
    }

    func test_givenServerError_whenLoading_thenSurfacesError() async {
        let stub = StubGitHubService()
        stub.reposResult = .failure(APIError.httpStatus(code: 500, serverMessage: "boom"))
        let vm = makeVM(stub)

        await vm.loadRepos()

        XCTAssertNotNil(vm.error)
        XCTAssertNotEqual(vm.linkState, .notLinked)
    }

    // MARK: - Create

    func test_givenNoRepoSelected_thenCannotCreate() {
        let vm = makeVM(StubGitHubService())
        XCTAssertNil(vm.selectedRepo)
        XCTAssertFalse(vm.canCreate)
    }

    func test_givenRepoAndTitle_whenCreating_thenPostsDraftAndSetsCreatedIssue() async {
        let stub = StubGitHubService()
        stub.reposResult = .success([GitHubRepo(fullName: "o/r", name: "r", owner: "o")])
        stub.createResult = .success(GitHubIssue(number: 55, title: "Fix the parser", state: .open))
        let vm = makeVM(stub)
        await vm.loadRepos()
        vm.title = "Fix the parser"

        await vm.create()

        XCTAssertEqual(vm.createdIssue?.number, 55)
        XCTAssertEqual(stub.createdDrafts.first?.title, "Fix the parser")
        XCTAssertTrue(stub.createdDrafts.first?.body?.contains("example.test/messages") ?? false)
        XCTAssertNil(vm.error)
    }

    func test_givenBlankTitle_whenCreating_thenNoop() async {
        let stub = StubGitHubService()
        stub.reposResult = .success([GitHubRepo(fullName: "o/r", name: "r", owner: "o")])
        let vm = makeVM(stub, message: message(text: "  "))   // title becomes "Post by @ada" — not blank
        await vm.loadRepos()
        vm.title = "   "

        await vm.create()

        XCTAssertNil(vm.createdIssue)
        XCTAssertTrue(stub.createdDrafts.isEmpty)
    }

    func test_givenNotLinked_whenCreating_thenFlipsToNotLinked() async {
        let stub = StubGitHubService()
        stub.reposResult = .success([GitHubRepo(fullName: "o/r", name: "r", owner: "o")])
        stub.createResult = .failure(GitHubServiceError.notLinked(message: "not linked"))
        let vm = makeVM(stub)
        await vm.loadRepos()

        await vm.create()

        XCTAssertEqual(vm.linkState, .notLinked)
        XCTAssertNil(vm.createdIssue)
    }

    func test_givenNotLinked_whenReloadAfterLink_thenRetriesRepos() async {
        let stub = StubGitHubService()
        stub.reposResult = .failure(GitHubServiceError.notLinked(message: "not linked"))
        let vm = makeVM(stub)
        await vm.loadRepos()
        XCTAssertEqual(vm.linkState, .notLinked)

        stub.reposResult = .success([GitHubRepo(fullName: "o/r", name: "r", owner: "o")])
        await vm.reloadAfterLink()

        XCTAssertEqual(vm.linkState, .linked)
        XCTAssertEqual(vm.selectedRepo, "o/r")
    }
}
