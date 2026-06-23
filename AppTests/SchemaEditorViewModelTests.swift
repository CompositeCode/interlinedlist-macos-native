// SchemaEditorViewModelTests
//
// BDD-named tests for the per-field schema editor view model.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class SchemaEditorViewModelTests: XCTestCase {

    // MARK: - field add / remove / reorder

    func test_givenInitialSchema_whenAddingField_thenAppendsEmpty() {
        let viewModel = makeViewModel(
            initial: ListSchema(fields: [SchemaField(name: "Title", type: .text)])
        )

        viewModel.addField()

        XCTAssertEqual(viewModel.fields.count, 2)
        XCTAssertEqual(viewModel.fields.last?.name, "")
        XCTAssertEqual(viewModel.fields.last?.type, .text)
    }

    func test_givenFields_whenRemovingByID_thenDrops() {
        let viewModel = makeViewModel(
            initial: ListSchema(fields: [
                SchemaField(name: "A", type: .text),
                SchemaField(name: "B", type: .number),
            ])
        )
        let bID = viewModel.fields[1].id

        viewModel.removeField(id: bID)

        XCTAssertEqual(viewModel.fields.map(\.name), ["A"])
    }

    func test_givenThreeFields_whenMoving_thenReorders() {
        let viewModel = makeViewModel(
            initial: ListSchema(fields: [
                SchemaField(name: "A", type: .text),
                SchemaField(name: "B", type: .number),
                SchemaField(name: "C", type: .boolean),
            ])
        )

        viewModel.moveFields(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(viewModel.fields.map(\.name), ["B", "C", "A"])
    }

    // MARK: - validation

    func test_givenEmptyName_whenValidating_thenReturnsError() {
        let viewModel = makeViewModel(initial: .empty)
        viewModel.addField()

        let error = viewModel.validationError(for: viewModel.fields[0])
        XCTAssertNotNil(error)
        XCTAssertFalse(viewModel.isValid)
    }

    func test_givenDuplicateName_whenValidating_thenReturnsError() {
        let viewModel = makeViewModel(
            initial: ListSchema(fields: [
                SchemaField(name: "X", type: .text),
                SchemaField(name: "X", type: .number),
            ])
        )

        XCTAssertNotNil(viewModel.validationError(for: viewModel.fields[0]))
        XCTAssertNotNil(viewModel.validationError(for: viewModel.fields[1]))
        XCTAssertFalse(viewModel.isValid)
    }

    func test_givenForbiddenCharacters_whenValidating_thenReturnsError() {
        let viewModel = makeViewModel(initial: .empty)
        viewModel.addField()
        viewModel.fields[0].name = "Bad:name"

        XCTAssertNotNil(viewModel.validationError(for: viewModel.fields[0]))
    }

    // MARK: - save

    func test_givenValidSchema_whenSaving_thenCallsUpdateAndPostsEvent() async {
        let stub = StubListsService()
        let savedSchema = ListSchema(fields: [SchemaField(name: "Title", type: .text)])
        await stub.enqueueUpdateSchema(success: savedSchema)
        let bus = ListsEventBus()
        let viewModel = SchemaEditorViewModel(
            lists: stub,
            eventBus: bus,
            listId: "L1",
            role: .owner,
            initialSchema: savedSchema
        )

        var iterator = bus.events().makeAsyncIterator()
        await viewModel.save()

        XCTAssertTrue(viewModel.didFinish)
        XCTAssertNil(viewModel.error)
        let recorded = await stub.recorded
        if case .updateSchema(let listId, let count) = recorded.first?.kind {
            XCTAssertEqual(listId, "L1")
            XCTAssertEqual(count, 1)
        } else {
            XCTFail("expected updateSchema, got \(String(describing: recorded.first))")
        }
        let event = await iterator.next()
        if case .schemaChanged(let id, _) = event {
            XCTAssertEqual(id, "L1")
        } else {
            XCTFail("expected schemaChanged, got \(String(describing: event))")
        }
    }

    func test_givenSubscriberRequiredError_whenSaving_thenSurfacesError() async {
        // Upstream API failure case using domain typed error.
        let stub = StubListsService()
        await stub.enqueueUpdateSchema(failure: ListsError.subscriberRequired)
        let viewModel = SchemaEditorViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            listId: "L1",
            role: .owner,
            initialSchema: ListSchema(fields: [SchemaField(name: "X", type: .text)])
        )

        await viewModel.save()

        XCTAssertFalse(viewModel.didFinish)
        XCTAssertEqual(viewModel.error as? ListsError, .subscriberRequired)
    }

    func test_givenViewerRole_whenSaving_thenIsNoop() async {
        // Boundary — read-only role doesn't save.
        let stub = StubListsService()
        let viewModel = SchemaEditorViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            listId: "L1",
            role: .viewer,
            initialSchema: ListSchema(fields: [SchemaField(name: "X", type: .text)])
        )

        await viewModel.save()

        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
        XCTAssertFalse(viewModel.isEditable)
    }

    func test_givenEmptySchema_whenSaving_thenIsNoop() async {
        // Empty / boundary: an empty schema isn't valid.
        let stub = StubListsService()
        let viewModel = SchemaEditorViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            listId: "L1",
            role: .owner,
            initialSchema: .empty
        )

        await viewModel.save()

        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
        XCTAssertFalse(viewModel.didFinish)
    }

    // MARK: - helpers

    private func makeViewModel(initial: ListSchema, role: WatcherRole = .owner) -> SchemaEditorViewModel {
        SchemaEditorViewModel(
            lists: StubListsService(),
            eventBus: ListsEventBus(),
            listId: "L1",
            role: role,
            initialSchema: initial
        )
    }
}
