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

// MARK: - The schema goes on the wire as columns, not as a DSL string (GitHub #85)
//
// `POST /api/lists` rejects a string schema outright —
// `400 {"error":"Invalid schema: DSL must be an object"}` — so a list created
// from macOS with columns never worked. The DSL survives as an *authoring*
// convenience: what the user types is parsed here, client-side, and the parsed
// columns are what travel.

extension NewListViewModelTests {

    // Happy path

    func test_givenTypedDSL_whenSubmitting_thenParsedColumnsAreSentNotTheString() async {
        let stub = StubListsService()
        await stub.enqueueCreate(success: ListsFixtures.ownedList(id: "L1", title: "Films"))
        let viewModel = NewListViewModel(lists: stub, eventBus: ListsEventBus())
        viewModel.title = "Films"
        viewModel.schemaDSL = "Title:text, Year:number"

        await viewModel.submit()

        XCTAssertTrue(viewModel.didFinish)
        let recorded = await stub.recorded
        guard case .create(_, _, let schema, _, _)? = recorded.first?.kind else {
            return XCTFail("expected create, got \(String(describing: recorded.first))")
        }
        XCTAssertEqual(schema?.fields.map(\.key), ["Title", "Year"])
        XCTAssertEqual(schema?.fields.map(\.type), [.text, .number])
    }

    // Invalid input — rejected before the service is called

    func test_givenMalformedDSL_whenSubmitting_thenNoCreateCallIsMade() async {
        // The parse failure is now caught client-side and reported against the
        // field the user typed into, instead of arriving as an opaque 400.
        let stub = StubListsService()
        let viewModel = NewListViewModel(lists: stub, eventBus: ListsEventBus())
        viewModel.title = "Films"
        viewModel.schemaDSL = "Bogus without a colon"

        await viewModel.submit()

        XCTAssertFalse(viewModel.didFinish)
        XCTAssertNotNil(viewModel.error)
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty, "a malformed schema never reaches the network")
    }

    // Boundary — no schema typed at all

    func test_givenNoDSL_whenSubmitting_thenSchemaIsNilRatherThanEmpty() async {
        let stub = StubListsService()
        await stub.enqueueCreate(success: ListsFixtures.ownedList(id: "L1", title: "Bare"))
        let viewModel = NewListViewModel(lists: stub, eventBus: ListsEventBus())
        viewModel.title = "Bare"
        viewModel.schemaDSL = "   "

        await viewModel.submit()

        let recorded = await stub.recorded
        guard case .create(_, _, let schema, _, _)? = recorded.first?.kind else {
            return XCTFail("expected create")
        }
        XCTAssertNil(schema, "whitespace is not a schema")
    }
}
