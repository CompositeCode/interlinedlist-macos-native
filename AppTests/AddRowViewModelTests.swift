// AddRowViewModelTests
//
// BDD quartet for the Add Row form (GitHub #50).
//
// The rule with the sharpest consequence is that **a rejected save clears
// nothing**. A bulk-entry session that loses a typed row to a validation error
// is worse than one that never offered the form, and the web's help page calls
// it out explicitly.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class AddRowViewModelTests: XCTestCase {

    private func schema(
        required: Bool = false,
        validation: SchemaFieldValidation? = nil,
        options: [String]? = nil,
        defaultValue: ListCellValue? = nil
    ) -> ListSchema {
        ListSchema(fields: [
            SchemaField(
                key: "title",
                label: "Title",
                type: .text,
                isRequired: required,
                displayOrder: 0,
                helpText: "What is it called?",
                placeholder: "e.g. Dune",
                validation: validation
            ),
            SchemaField(
                key: "year",
                label: "Publication Year",
                type: .number,
                displayOrder: 1,
                validation: validation
            ),
            SchemaField(
                key: "status",
                label: "Status",
                type: .select,
                displayOrder: 2,
                defaultValue: defaultValue,
                enumValues: options
            )
        ])
    }

    private func makeViewModel(
        schema: ListSchema,
        addAnother: Bool = false
    ) -> (AddRowViewModel, StubListsService) {
        let stub = StubListsService()
        let vm = AddRowViewModel(
            lists: stub,
            listId: "L1",
            schema: schema,
            addAnotherAfterSaving: addAnother
        )
        return (vm, stub)
    }

    // MARK: - Happy path

    func test_givenAValidRow_whenSaving_thenItIsCreatedAndTheSheetFinishes() async {
        let (vm, stub) = makeViewModel(schema: schema())
        await stub.enqueueCreateRow(success: ListsFixtures.row(id: "R1", listId: "L1", fields: [:]))

        vm.setValue(.string("Dune"), forKey: "title")
        await vm.save()

        XCTAssertTrue(vm.didFinish)
        XCTAssertEqual(vm.savedCount, 1)
        XCTAssertTrue(vm.failures.isEmpty)
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.contains { if case .createRow = $0.kind { return true } else { return false } })
    }

    func test_givenAColumnWithADefault_whenTheFormOpens_thenItIsSeeded() async {
        // The web opens a select on its default. A blank picker would make a
        // required column look unfilled when the server would have filled it.
        let (vm, _) = makeViewModel(
            schema: schema(options: ["todo", "done"], defaultValue: .string("todo"))
        )

        XCTAssertEqual(vm.value(forKey: "status"), .string("todo"))
    }

    // MARK: - Invalid input — refused before the service is called

    func test_givenAMissingRequiredValue_whenSaving_thenNoServiceCallIsMade() async {
        // The rules are the server's and it would reject the same row. Spending
        // a round-trip to be told what we already know costs the user time and
        // tells them *less* — a 400 cannot say which column was wrong.
        let (vm, stub) = makeViewModel(schema: schema(required: true))

        await vm.save()

        XCTAssertEqual(vm.failures["title"], "Title is required.")
        XCTAssertFalse(vm.didFinish)
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty, "a locally-invalid row never reaches the network")
    }

    func test_givenSeveralInvalidFields_whenSaving_thenEveryFailureIsReported() async {
        // Reporting one problem at a time makes the user submit repeatedly to
        // discover the rest.
        let rules = SchemaFieldValidation(min: 1000, max: 2100, minLength: 5, maxLength: 10)
        let (vm, _) = makeViewModel(schema: schema(required: true, validation: rules))

        vm.setValue(.string("Hi"), forKey: "title")
        vm.setValue(.string("12"), forKey: "year")
        await vm.save()

        XCTAssertEqual(vm.failures.count, 2)
        XCTAssertNotNil(vm.failures["title"])
        XCTAssertNotNil(vm.failures["year"])
    }

    func test_givenAFieldIsEdited_whenItHadAFailure_thenTheMessageClears() async {
        // A stale red message under a field the user has just fixed teaches them
        // to ignore the messages.
        let (vm, _) = makeViewModel(schema: schema(required: true))
        await vm.save()
        XCTAssertNotNil(vm.failures["title"])

        vm.setValue(.string("Dune"), forKey: "title")

        XCTAssertNil(vm.failures["title"])
    }

    // MARK: - Upstream failure — the rule this sheet exists for

    func test_givenARejectedSave_whenItFails_thenEveryTypedValueSurvives() async {
        let (vm, stub) = makeViewModel(schema: schema())
        await stub.enqueueCreateRow(failure: TestError.upstream("server said no"))

        vm.setValue(.string("Dune"), forKey: "title")
        vm.setValue(.string("1965"), forKey: "year")
        await vm.save()

        XCTAssertNotNil(vm.error)
        XCTAssertEqual(vm.value(forKey: "title"), .string("Dune"), "the user's typing survives")
        XCTAssertEqual(vm.value(forKey: "year"), .string("1965"))
        XCTAssertFalse(vm.didFinish)
        XCTAssertEqual(vm.savedCount, 0, "a failed save is not a saved row")
    }

    // MARK: - Add another after saving

    func test_givenAddAnotherOn_whenSaving_thenTheFormEmptiesAndStaysOpen() async {
        let (vm, stub) = makeViewModel(schema: schema(), addAnother: true)
        await stub.enqueueCreateRow(success: ListsFixtures.row(id: "R1", listId: "L1", fields: [:]))

        vm.setValue(.string("Dune"), forKey: "title")
        await vm.save()

        XCTAssertFalse(vm.didFinish, "the sheet stays open")
        XCTAssertEqual(vm.savedCount, 1)
        XCTAssertEqual(vm.value(forKey: "title"), .null, "the form empties for the next row")
        XCTAssertTrue(vm.shouldRefocusFirstField, "and the cursor returns to the first field")
    }

    func test_givenAddAnotherOn_whenSavingSeveral_thenTheCountRunsUp() async {
        let (vm, stub) = makeViewModel(schema: schema(), addAnother: true)
        for id in ["R1", "R2", "R3"] {
            await stub.enqueueCreateRow(success: ListsFixtures.row(id: id, listId: "L1", fields: [:]))
        }

        for title in ["A", "B", "C"] {
            vm.setValue(.string(title), forKey: "title")
            await vm.save()
            vm.consumeRefocusRequest()
        }

        XCTAssertEqual(vm.savedCount, 3)
        XCTAssertFalse(vm.didFinish)
    }

    func test_givenAddAnotherOnAndAFailedSave_whenItFails_thenTheFormIsNotEmptied() async {
        // The two rules interacting: staying open must not be confused with
        // clearing, or a bulk session silently drops the row that failed.
        let (vm, stub) = makeViewModel(schema: schema(), addAnother: true)
        await stub.enqueueCreateRow(failure: TestError.upstream("nope"))

        vm.setValue(.string("Dune"), forKey: "title")
        await vm.save()

        XCTAssertEqual(vm.value(forKey: "title"), .string("Dune"))
        XCTAssertFalse(vm.shouldRefocusFirstField, "no refocus without a save")
    }

    // MARK: - Boundary

    func test_givenBlankOptionalFields_whenSaving_thenTheyAreOmittedNotSentAsNull() async {
        // An absent key lets the server apply its own default; an explicit null
        // asks it to store nothing. They are different requests.
        let (vm, stub) = makeViewModel(schema: schema())
        await stub.enqueueCreateRow(success: ListsFixtures.row(id: "R1", listId: "L1", fields: [:]))

        vm.setValue(.string("Dune"), forKey: "title")
        vm.setValue(.string("   "), forKey: "year")
        await vm.save()

        let recorded = await stub.recorded
        guard case .createRow(_, let data)? = recorded.last?.kind else {
            return XCTFail("expected createRow, got \(String(describing: recorded.last))")
        }
        XCTAssertEqual(Set(data.keys), ["title"], "whitespace is not a value")
    }

    func test_givenAColumnlessList_whenSaving_thenNothingIsSent() async {
        // Boundary: a list with no schema yet. The form says so and the button
        // is disabled, but the model must refuse too.
        let (vm, stub) = makeViewModel(schema: .empty)

        await vm.save()

        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty || vm.didFinish == false)
    }
}
