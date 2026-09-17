// RowValueValidatorTests
//
// The client-side half of per-column validation (GitHub #50).
//
// The rules are the server's and it enforces them regardless. Checking locally
// buys the user a specific answer against the field they typed into, instead of
// a round-trip that returns a generic 400 with no idea which column was wrong.
//
// Two deliberate non-checks are asserted here as behaviour, because they are
// decisions rather than omissions: `pattern` is never evaluated, and an absent
// optional value breaks no rule but `required`.

import XCTest
import InterlinedDomain
@testable import InterlinedList

final class RowValueValidatorTests: XCTestCase {

    private func field(
        key: String = "title",
        label: String = "Title",
        type: SchemaFieldType = .text,
        required: Bool? = nil,
        validation: SchemaFieldValidation? = nil,
        options: [String]? = nil
    ) -> SchemaField {
        SchemaField(
            key: key,
            label: label,
            type: type,
            isRequired: required,
            validation: validation,
            enumValues: options
        )
    }

    // MARK: - Happy path

    func test_givenAValueSatisfyingEveryRule_whenValidating_thenItPasses() {
        let column = field(
            required: true,
            validation: SchemaFieldValidation(minLength: 2, maxLength: 20)
        )
        XCTAssertNil(RowValueValidator.failure(for: .string("Dune"), field: column))
    }

    // MARK: - Required

    func test_givenAMissingRequiredValue_whenValidating_thenItIsRefusedByLabel() {
        // The label, not the key: the user sees "Publication Year", not "year".
        let column = field(key: "year", label: "Publication Year", type: .number, required: true)
        XCTAssertEqual(
            RowValueValidator.failure(for: .null, field: column),
            "Publication Year is required."
        )
    }

    func test_givenWhitespaceOnly_whenValidatingARequiredField_thenItStillCountsAsEmpty() {
        // Otherwise a required field passes with a space in it.
        let column = field(required: true)
        XCTAssertNotNil(RowValueValidator.failure(for: .string("   "), field: column))
    }

    func test_givenAMissingOptionalValue_whenValidating_thenNoRuleApplies() {
        // A min length on a field the user left blank is not a violation — it is
        // an empty optional field. Applying length rules to absence would make
        // every optional constrained column effectively required.
        let column = field(validation: SchemaFieldValidation(minLength: 5))
        XCTAssertNil(RowValueValidator.failure(for: .null, field: column))
    }

    // MARK: - Ranges and lengths

    func test_givenANumberOutsideItsRange_whenValidating_thenTheBoundIsNamed() {
        let column = field(key: "year", label: "Year", type: .number,
                           validation: SchemaFieldValidation(min: 1000, max: 2100))
        XCTAssertEqual(
            RowValueValidator.failure(for: .int(12), field: column),
            "Year must be at least 1000."
        )
        XCTAssertEqual(
            RowValueValidator.failure(for: .int(9999), field: column),
            "Year must be at most 2100."
        )
        XCTAssertNil(RowValueValidator.failure(for: .int(1965), field: column))
    }

    func test_givenANumberTypedAsText_whenValidating_thenItIsStillRangeChecked() {
        // A text field produces a string before a save coerces it, so a
        // number-only check would skip validation exactly when the user is
        // typing.
        let column = field(key: "year", label: "Year", type: .number,
                           validation: SchemaFieldValidation(min: 1000))
        XCTAssertNotNil(RowValueValidator.failure(for: .string("12"), field: column))
    }

    func test_givenTextOutsideItsLengthRules_whenValidating_thenTheBoundIsNamed() {
        let column = field(validation: SchemaFieldValidation(minLength: 3, maxLength: 5))
        XCTAssertEqual(
            RowValueValidator.failure(for: .string("Hi"), field: column),
            "Title must be at least 3 characters."
        )
        XCTAssertEqual(
            RowValueValidator.failure(for: .string("Far too long"), field: column),
            "Title must be at most 5 characters."
        )
    }

    func test_givenLengthRulesOnANonTextColumn_whenValidating_thenTheyAreIgnored() {
        // Character-count rules belong to the text family. A stored rule on a
        // boolean is the server's business; enforcing it here would refuse rows
        // the platform accepts.
        let column = field(key: "read", label: "Read", type: .boolean,
                           validation: SchemaFieldValidation(minLength: 50))
        XCTAssertNil(RowValueValidator.failure(for: .bool(true), field: column))
    }

    // MARK: - Select options

    func test_givenAValueOutsideTheOptionSet_whenValidating_thenTheOptionsAreListed() {
        let column = field(key: "status", label: "Status", type: .select,
                           options: ["todo", "doing", "done"])
        XCTAssertEqual(
            RowValueValidator.failure(for: .string("maybe"), field: column),
            "Status must be one of: todo, doing, done."
        )
        XCTAssertNil(RowValueValidator.failure(for: .string("done"), field: column))
    }

    // MARK: - The deliberate non-check

    func test_givenAPattern_whenValidating_thenItIsNeverEvaluatedLocally() {
        // `pattern` is a server-side regular expression. Compiling it here and
        // rejecting a non-match would let this client refuse a value the server
        // accepts whenever the two engines disagree on syntax. A round-trip is
        // the correct cost for the one rule we cannot faithfully reproduce.
        let column = field(validation: SchemaFieldValidation(pattern: "^[A-Z][0-9]{99}$"))
        XCTAssertNil(
            RowValueValidator.failure(for: .string("definitely does not match"), field: column),
            "the server owns this rule"
        )
    }

    // MARK: - Whole-row

    func test_givenARowWithSeveralProblems_whenValidating_thenEveryFailureIsReturned() {
        // A form that reports one problem at a time makes the user submit
        // repeatedly to discover the rest.
        let schema = ListSchema(fields: [
            field(required: true),
            field(key: "year", label: "Year", type: .number,
                  validation: SchemaFieldValidation(min: 1000)),
            field(key: "status", label: "Status", type: .select, options: ["a", "b"])
        ])

        let failures = RowValueValidator.failures(
            forRow: ["year": .int(5), "status": .string("z")],
            schema: schema
        )

        XCTAssertEqual(Set(failures.map(\.key)), ["title", "year", "status"])
    }

    func test_givenAnEmptySchema_whenValidating_thenThereIsNothingToFail() {
        XCTAssertTrue(RowValueValidator.failures(forRow: [:], schema: .empty).isEmpty)
    }

    func test_givenAValueForAColumnTheSchemaDoesNotHave_whenValidating_thenItIsIgnored() {
        // Boundary: a stale cell from a column that was removed. The server owns
        // what to do with it; refusing the whole row here would strand the user.
        let schema = ListSchema(fields: [field()])
        let failures = RowValueValidator.failures(
            forRow: ["title": .string("Dune"), "removed": .string("x")],
            schema: schema
        )
        XCTAssertTrue(failures.isEmpty)
    }
}
