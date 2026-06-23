import XCTest
@testable import InterlinedDomain

/// BDD-named, property-style coverage for the schema DSL parser
/// (PLAN.md §7 — "Schema DSL parser and sync engine get the deepest test
/// suites; property-style cases for the parser"). Covers round-trip, every
/// type, missing colon, duplicate names, empty source, trailing comma, and
/// whitespace tolerance.
final class SchemaDSLTests: XCTestCase {

    // MARK: - Happy path

    func test_givenSimpleSchema_whenParsing_thenReturnsOrderedFields() throws {
        // Given
        let source = "Title:text, Year:number, Released:date"

        // When
        let schema = try SchemaDSL.parse(source)

        // Then — order is preserved.
        XCTAssertEqual(schema.fields.map(\.name), ["Title", "Year", "Released"])
        XCTAssertEqual(schema.fields.map(\.type), [.text, .number, .date])
    }

    func test_givenSingleField_whenParsing_thenReturnsOneField() throws {
        // Given — boundary: a single field.
        let schema = try SchemaDSL.parse("Title:text")

        // Then
        XCTAssertEqual(schema.fields.count, 1)
        XCTAssertEqual(schema.fields.first, SchemaField(name: "Title", type: .text))
    }

    // MARK: - Every type

    func test_givenAllSupportedTypes_whenParsing_thenEachTypeIsRecognised() throws {
        // Given — one column per supported `SchemaFieldType`.
        let source = "A:text, B:number, C:boolean, D:date, E:url, F:email"

        // When
        let schema = try SchemaDSL.parse(source)

        // Then — every type case in the enum appears exactly once.
        let parsedTypes = schema.fields.map(\.type)
        let allTypes = SchemaFieldType.allCases
        XCTAssertEqual(Set(parsedTypes), Set(allTypes))
        XCTAssertEqual(parsedTypes.count, allTypes.count)
    }

    func test_givenUppercaseTypeToken_whenParsing_thenIsRecognisedCaseInsensitively() throws {
        // Given — type tokens are recognised regardless of casing; field
        // names are case-sensitive (the row data keys it case-sensitively).
        let schema = try SchemaDSL.parse("Title:TEXT, Count:Number")

        // Then
        XCTAssertEqual(schema.fields.map(\.type), [.text, .number])
        XCTAssertEqual(schema.fields.map(\.name), ["Title", "Count"])
    }

    // MARK: - Round-trip

    func test_givenSchema_whenSerializedAndReparsed_thenRoundTripsLossless() throws {
        // Given — non-trivial schema; the serializer's canonical output
        // should round-trip with no information loss.
        let original = ListSchema(fields: [
            SchemaField(name: "Title", type: .text),
            SchemaField(name: "Year", type: .number),
            SchemaField(name: "Released", type: .date),
            SchemaField(name: "IsPublic", type: .boolean),
            SchemaField(name: "Site", type: .url),
            SchemaField(name: "Owner", type: .email)
        ])

        // When
        let serialized = SchemaDSL.serialize(original)
        let reparsed = try SchemaDSL.parse(serialized)

        // Then
        XCTAssertEqual(reparsed, original)
    }

    func test_givenCanonicalForm_whenSerializingParsedInput_thenIsIdempotent() throws {
        // Given — the canonical form uses `", "` separators; reparsing must
        // produce the same serialized output (idempotent canonicalisation).
        let messy = "  Title : text ,Year:  number ,  Released:date  "

        // When
        let parsed = try SchemaDSL.parse(messy)
        let serialized1 = SchemaDSL.serialize(parsed)
        let serialized2 = SchemaDSL.serialize(try SchemaDSL.parse(serialized1))

        // Then — second canonicalisation is identical to the first.
        XCTAssertEqual(serialized1, serialized2)
        XCTAssertEqual(serialized1, "Title:text, Year:number, Released:date")
    }

    func test_givenEmptySchema_whenSerialized_thenProducesEmptyString() {
        // Given — `ListSchema.empty` serializes to `""` (the parser rejects
        // empty input — empty schemas live only in memory).
        let schema = ListSchema.empty

        // When
        let serialized = SchemaDSL.serialize(schema)

        // Then
        XCTAssertEqual(serialized, "")
    }

    // MARK: - Whitespace tolerance

    func test_givenWhitespaceAroundDelimiters_whenParsing_thenStripsAndParses() throws {
        // Given — whitespace around `,` and `:` is stripped.
        let source = "  Title  :  text  ,   Year:number"

        // When
        let schema = try SchemaDSL.parse(source)

        // Then
        XCTAssertEqual(schema.fields.map(\.name), ["Title", "Year"])
        XCTAssertEqual(schema.fields.map(\.type), [.text, .number])
    }

    func test_givenLeadingAndTrailingWhitespace_whenParsing_thenStripsOuterWhitespace() throws {
        // Given
        let schema = try SchemaDSL.parse("\n\t Title:text  \n")

        // Then
        XCTAssertEqual(schema.fields.count, 1)
        XCTAssertEqual(schema.fields.first?.name, "Title")
    }

    // MARK: - Error cases

    func test_givenEmptySource_whenParsing_thenThrowsEmptySource() {
        // Given / When / Then
        XCTAssertThrowsError(try SchemaDSL.parse("")) { error in
            XCTAssertEqual(error as? SchemaDSLError, .emptySource)
        }
    }

    func test_givenWhitespaceOnlySource_whenParsing_thenThrowsEmptySource() {
        // Given — trimmed-to-empty is treated as empty.
        XCTAssertThrowsError(try SchemaDSL.parse("   \n  \t  ")) { error in
            XCTAssertEqual(error as? SchemaDSLError, .emptySource)
        }
    }

    func test_givenFieldWithoutColon_whenParsing_thenThrowsInvalidFieldSyntax() {
        // Given — boundary: a field with no `:` separator.
        XCTAssertThrowsError(try SchemaDSL.parse("Title text, Year:number")) { error in
            XCTAssertEqual(
                error as? SchemaDSLError,
                .invalidFieldSyntax(rawField: "Title text")
            )
        }
    }

    func test_givenFieldWithEmptyName_whenParsing_thenThrowsInvalidFieldSyntax() {
        // Given — `:text` has an empty name.
        XCTAssertThrowsError(try SchemaDSL.parse(":text")) { error in
            XCTAssertEqual(
                error as? SchemaDSLError,
                .invalidFieldSyntax(rawField: ":text")
            )
        }
    }

    func test_givenFieldWithEmptyType_whenParsing_thenThrowsInvalidFieldSyntax() {
        // Given — `Title:` has an empty type.
        XCTAssertThrowsError(try SchemaDSL.parse("Title:")) { error in
            XCTAssertEqual(
                error as? SchemaDSLError,
                .invalidFieldSyntax(rawField: "Title:")
            )
        }
    }

    func test_givenUnknownTypeToken_whenParsing_thenThrowsUnknownType() {
        // Given — `decimal` is not in the closed set.
        XCTAssertThrowsError(try SchemaDSL.parse("Amount:decimal")) { error in
            XCTAssertEqual(error as? SchemaDSLError, .unknownType(rawType: "decimal"))
        }
    }

    func test_givenDuplicateFieldNames_whenParsing_thenThrowsDuplicateFieldName() {
        // Given — same name twice in different positions.
        XCTAssertThrowsError(try SchemaDSL.parse("Title:text, Year:number, Title:url")) { error in
            XCTAssertEqual(error as? SchemaDSLError, .duplicateFieldName("Title"))
        }
    }

    func test_givenTrailingComma_whenParsing_thenThrowsInvalidFieldSyntax() {
        // Given — a trailing comma yields an empty token. Treated as a
        // syntax error so the typo does not silently produce a partial schema.
        XCTAssertThrowsError(try SchemaDSL.parse("Title:text,")) { error in
            // The empty token after the trailing comma reports the raw
            // input that produced it (the empty trailing piece).
            guard case .invalidFieldSyntax = error as? SchemaDSLError else {
                return XCTFail("Expected invalidFieldSyntax, got \(error)")
            }
        }
    }

    func test_givenLeadingComma_whenParsing_thenThrowsInvalidFieldSyntax() {
        // Given — a leading comma also yields an empty token.
        XCTAssertThrowsError(try SchemaDSL.parse(", Title:text")) { error in
            guard case .invalidFieldSyntax = error as? SchemaDSLError else {
                return XCTFail("Expected invalidFieldSyntax, got \(error)")
            }
        }
    }

    func test_givenDoubleComma_whenParsing_thenThrowsInvalidFieldSyntax() {
        // Given — `,,` is two empty tokens between commas.
        XCTAssertThrowsError(try SchemaDSL.parse("Title:text,, Year:number")) { error in
            guard case .invalidFieldSyntax = error as? SchemaDSLError else {
                return XCTFail("Expected invalidFieldSyntax, got \(error)")
            }
        }
    }

    // MARK: - SchemaFieldType DSL token

    func test_givenAllTypes_whenAskingForDSLToken_thenMatchesRawValue() {
        // Property-style: every type token is its `dslToken` and round-trips
        // through the initializer.
        for type in SchemaFieldType.allCases {
            XCTAssertEqual(SchemaFieldType(dslToken: type.dslToken), type)
        }
    }

    func test_givenUnknownToken_whenInitializingFromDSL_thenReturnsNil() {
        // Given / Then
        XCTAssertNil(SchemaFieldType(dslToken: "decimal"))
        XCTAssertNil(SchemaFieldType(dslToken: ""))
        XCTAssertNil(SchemaFieldType(dslToken: "json"))
    }

    // MARK: - ListSchema lookups

    func test_givenSchema_whenLookingUpByName_thenReturnsField() throws {
        // Given
        let schema = try SchemaDSL.parse("Title:text, Year:number")

        // When / Then
        XCTAssertEqual(schema.field(named: "Year")?.type, .number)
        XCTAssertNil(schema.field(named: "Missing"))
    }
}
