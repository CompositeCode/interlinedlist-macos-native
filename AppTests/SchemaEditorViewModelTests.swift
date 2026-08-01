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

    // MARK: - select options (§1.1)

    func test_givenSelectFieldFromSchema_whenInitialising_thenSeedsOptions() {
        // Happy path — a `select` column's options hydrate the editable row.
        let viewModel = makeViewModel(
            initial: ListSchema(fields: [
                SchemaField(name: "Priority", type: .select, enumValues: ["low", "high"])
            ])
        )

        XCTAssertEqual(viewModel.fields.first?.type, .select)
        XCTAssertEqual(viewModel.fields.first?.options, ["low", "high"])
    }

    func test_givenSelectField_whenAddingOption_thenAppendsBlankOption() {
        let viewModel = makeViewModel(
            initial: ListSchema(fields: [SchemaField(name: "P", type: .select, enumValues: ["a"])])
        )
        let id = viewModel.fields[0].id

        viewModel.addOption(toFieldID: id)

        XCTAssertEqual(viewModel.fields[0].options, ["a", ""])
    }

    func test_givenSelectField_whenSettingAndRemovingOptions_thenMutatesInPlace() {
        let viewModel = makeViewModel(
            initial: ListSchema(fields: [SchemaField(name: "P", type: .select, enumValues: ["a", "b", "c"])])
        )
        let id = viewModel.fields[0].id

        viewModel.setOption("z", forFieldID: id, at: 1)
        viewModel.removeOption(fromFieldID: id, at: 0)

        XCTAssertEqual(viewModel.fields[0].options, ["z", "c"])
    }

    func test_givenSelectField_whenSwitchingTypeAway_thenDiscardsOptions() {
        // Boundary — options must not survive a switch to a non-select type,
        // or `save()` would carry a stale set into the DSL.
        let viewModel = makeViewModel(
            initial: ListSchema(fields: [SchemaField(name: "P", type: .select, enumValues: ["a", "b"])])
        )
        let id = viewModel.fields[0].id

        viewModel.setType(.text, forFieldID: id)

        XCTAssertTrue(viewModel.fields[0].options.isEmpty)
    }

    func test_givenSelectWithNoOptions_whenValidating_thenReturnsError() {
        // Invalid input — a select with an empty option set fails validation,
        // mirroring the DSL parser's `.emptySelectOptions`.
        let viewModel = makeViewModel(initial: .empty)
        viewModel.addField()
        let id = viewModel.fields[0].id
        viewModel.fields[0].name = "P"
        viewModel.setType(.select, forFieldID: id)

        XCTAssertNotNil(viewModel.validationError(for: viewModel.fields[0]))
        XCTAssertFalse(viewModel.isValid)
    }

    func test_givenSelectWithDuplicateOptions_whenValidating_thenReturnsError() {
        // Invalid input — duplicate options fail validation, mirroring the
        // parser's `.duplicateSelectOption`.
        let viewModel = makeViewModel(
            initial: ListSchema(fields: [
                SchemaField(name: "P", type: .select, enumValues: ["a", "a"])
            ])
        )

        XCTAssertNotNil(viewModel.validationError(for: viewModel.fields[0]))
        XCTAssertFalse(viewModel.isValid)
    }

    func test_givenValidSelectSchema_whenSaving_thenRoundTripsOptionsToService() async {
        // Happy path — a valid `select` column saves with its options intact.
        let stub = StubListsService()
        let saved = ListSchema(fields: [
            SchemaField(name: "Priority", type: .select, enumValues: ["low", "high"])
        ])
        await stub.enqueueUpdateSchema(success: saved)
        let viewModel = SchemaEditorViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            listId: "L1",
            role: .owner,
            initialSchema: saved
        )

        await viewModel.save()

        XCTAssertTrue(viewModel.didFinish)
        let sent = await stub.lastUpdatedSchema
        XCTAssertEqual(sent?.fields.first?.type, .select)
        XCTAssertEqual(sent?.fields.first?.enumValues, ["low", "high"])
    }

    func test_givenInvalidSelectSchema_whenSaving_thenDoesNotCallService() async {
        // Invalid input — a select with no options must not reach the service.
        let stub = StubListsService()
        let viewModel = makeViewModel(
            initial: ListSchema(fields: [SchemaField(name: "P", type: .select, enumValues: [])]),
            lists: stub
        )

        await viewModel.save()

        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
        XCTAssertFalse(viewModel.didFinish)
    }

    func test_givenMarkdownField_whenSaving_thenSerialisesWithNoOptions() async {
        // Markdown is long-text: saves as a bare token, no options attached.
        let stub = StubListsService()
        let saved = ListSchema(fields: [SchemaField(name: "Body", type: .markdown)])
        await stub.enqueueUpdateSchema(success: saved)
        let viewModel = SchemaEditorViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            listId: "L1",
            role: .owner,
            initialSchema: saved
        )

        await viewModel.save()

        let sent = await stub.lastUpdatedSchema
        XCTAssertEqual(sent?.fields.first?.type, .markdown)
        XCTAssertNil(sent?.fields.first?.enumValues)
    }

    // MARK: - helpers

    private func makeViewModel(
        initial: ListSchema,
        role: WatcherRole = .owner,
        lists: StubListsService = StubListsService()
    ) -> SchemaEditorViewModel {
        SchemaEditorViewModel(
            lists: lists,
            eventBus: ListsEventBus(),
            listId: "L1",
            role: role,
            initialSchema: initial
        )
    }
}
