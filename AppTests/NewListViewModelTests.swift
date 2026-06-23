// NewListViewModelTests
//
// BDD-named tests for the New List sheet view model.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class NewListViewModelTests: XCTestCase {

    func test_givenValidTitle_whenSubmitting_thenCallsCreateAndPostsEvent() async {
        let stub = StubListsService()
        let created = ListsFixtures.ownedList(id: "L-new", title: "Books")
        await stub.enqueueCreate(success: created)
        let bus = ListsEventBus()
        let viewModel = NewListViewModel(lists: stub, eventBus: bus)
        viewModel.title = "Books"

        var iterator = bus.events().makeAsyncIterator()
        await viewModel.submit()

        XCTAssertTrue(viewModel.didFinish)
        XCTAssertEqual(viewModel.createdList?.id, "L-new")
        let recorded = await stub.recorded
        if case .create(let title, _, _, _, let isPublic) = recorded.first?.kind {
            XCTAssertEqual(title, "Books")
            XCTAssertFalse(isPublic)
        } else {
            XCTFail("expected create, got \(String(describing: recorded.first))")
        }
        let event = await iterator.next()
        if case .listCreated(let list) = event {
            XCTAssertEqual(list.id, "L-new")
        } else {
            XCTFail("expected listCreated, got \(String(describing: event))")
        }
    }

    func test_givenWhitespaceTitle_whenSubmitting_thenNoCallIsMade() async {
        // Invalid input — service must not be called.
        let stub = StubListsService()
        let viewModel = NewListViewModel(lists: stub, eventBus: ListsEventBus())
        viewModel.title = "   "

        await viewModel.submit()

        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
        XCTAssertFalse(viewModel.didFinish)
    }

    func test_givenSubscriberRequiredError_whenSubmitting_thenSurfacesError() async {
        // Upstream failure case using the domain's typed error.
        let stub = StubListsService()
        await stub.enqueueCreate(failure: ListsError.subscriberRequired)
        let viewModel = NewListViewModel(lists: stub, eventBus: ListsEventBus())
        viewModel.title = "Books"

        await viewModel.submit()

        XCTAssertFalse(viewModel.didFinish)
        XCTAssertEqual(viewModel.error as? ListsError, .subscriberRequired)
    }

    func test_givenEmptyOptionalFields_whenSubmitting_thenOmitsThem() async {
        // Empty / boundary: optional fields drop to nil.
        let stub = StubListsService()
        await stub.enqueueCreate(success: ListsFixtures.ownedList(id: "L-new"))
        let viewModel = NewListViewModel(lists: stub, eventBus: ListsEventBus())
        viewModel.title = "Books"
        viewModel.descriptionText = "  "
        viewModel.schemaDSL = ""

        await viewModel.submit()

        let recorded = await stub.recorded
        if case .create(_, let description, let schema, _, _) = recorded.first?.kind {
            XCTAssertNil(description)
            XCTAssertNil(schema)
        } else {
            XCTFail("expected create")
        }
    }
}
