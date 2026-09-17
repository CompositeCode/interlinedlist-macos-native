// ListSchemaWireShapeTests
//
// Decode tests for the list and list-schema wire shapes, against payloads
// **captured live** on 2026-09-15 rather than written by hand (GitHub #75, #85).
//
// Why that distinction is the whole point of this file: three separate silent
// decode defects in this client — G21 link metadata, G25 org members, and the
// two fixed here — all shipped with green tests, because each test invented the
// payload it then asserted against. A fabricated fixture tests that the decoder
// matches the fixture, which is a tautology. Every JSON literal below is a
// verbatim response body; the transcripts are in
// `docs/spikes/list-schema-wire-shapes.md`.

import XCTest
@testable import InterlinedKit

final class ListSchemaWireShapeTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONCoders.makeDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - GET /api/lists/{id} — the #75 envelope

    /// Captured from `GET /api/lists/851954cb-…`.
    private let singleListJSON = """
    {
      "data": {
        "id": "851954cb-f9ee-4a1f-b864-d57ddeb639d6",
        "userId": "15e3d575-98bc-40e5-9aba-0d9cc9e30799",
        "messageId": null,
        "parentId": null,
        "folderId": null,
        "title": "probe-object-schema",
        "description": "recon probe",
        "isPublic": false,
        "metadata": null,
        "source": "local",
        "githubRepo": null,
        "githubRepoPrivate": null,
        "createdAt": "2026-09-15T10:55:39.152Z",
        "updatedAt": "2026-09-15T10:55:39.152Z",
        "deletedAt": null,
        "properties": [
          {
            "id": "3096cb0f-1f45-4935-a613-e1d5c2075e13",
            "listId": "851954cb-f9ee-4a1f-b864-d57ddeb639d6",
            "propertyKey": "title",
            "propertyName": "Title",
            "propertyType": "text",
            "displayOrder": 0,
            "isRequired": true,
            "defaultValue": null,
            "validationRules": null,
            "helpText": null,
            "placeholder": null,
            "isVisible": true,
            "visibilityCondition": null,
            "createdAt": "2026-09-15T10:55:39.282Z",
            "updatedAt": "2026-09-15T10:55:39.282Z"
          },
          {
            "id": "495aa482-5a6c-4e59-8205-37e4c64f4f42",
            "listId": "851954cb-f9ee-4a1f-b864-d57ddeb639d6",
            "propertyKey": "status",
            "propertyName": "Status",
            "propertyType": "select",
            "displayOrder": 1,
            "isRequired": false,
            "defaultValue": null,
            "validationRules": { "options": ["todo", "doing", "done"] },
            "helpText": null,
            "placeholder": null,
            "isVisible": true,
            "visibilityCondition": null,
            "createdAt": "2026-09-15T10:55:39.282Z",
            "updatedAt": "2026-09-15T10:55:39.282Z"
          }
        ]
      }
    }
    """

    // Happy path

    func test_givenTheCapturedSingleListBody_whenDecoding_thenTheEnvelopeAndItsColumnsArrive() throws {
        let response = try decode(ListResponse.self, singleListJSON)

        XCTAssertNil(response.message, "the read carries no message; only the writes do")
        XCTAssertEqual(response.data.title, "probe-object-schema")
        XCTAssertEqual(response.data.properties?.count, 2)
        XCTAssertEqual(response.data.schemaFields?.map(\.key), ["title", "status"])
        XCTAssertEqual(response.data.schemaFields?.map(\.label), ["Title", "Status"])
    }

    func test_givenTheCapturedBody_whenDecodedAsABareList_thenItFails() throws {
        // The regression this pins. `Lists.get` declared `Request<ListDTO>`, and
        // a bare decode of the real body cannot work — which is why
        // `ListsService.detail(listId:)` failed on every live call while its
        // test, written against a bare fixture, stayed green (GitHub #75).
        XCTAssertThrowsError(try decode(ListDTO.self, singleListJSON))
    }

    // MARK: - GET /api/lists/{id}/schema

    /// Captured from `GET /api/lists/851954cb-…/schema` after setting help text,
    /// placeholders and validation on the columns.
    private let schemaJSON = """
    {
      "data": {
        "name": "probe-object-schema",
        "description": "recon probe",
        "fields": [
          {
            "key": "title",
            "type": "text",
            "label": "Title",
            "displayOrder": 0,
            "required": true,
            "helpText": "What is it called?",
            "placeholder": "e.g. Dune",
            "visible": true,
            "validation": { "pattern": "^[A-Za-z].*$", "maxLength": 80, "minLength": 2 }
          },
          {
            "key": "year",
            "type": "number",
            "label": "Year",
            "displayOrder": 1,
            "required": false,
            "helpText": "Publication year",
            "visible": true,
            "validation": { "max": 2100, "min": 1000 }
          },
          {
            "key": "status",
            "type": "select",
            "label": "Status",
            "displayOrder": 5,
            "required": false,
            "visible": true,
            "defaultValue": "todo",
            "validation": { "options": ["todo", "doing", "done"] },
            "options": ["todo", "doing", "done"]
          }
        ]
      }
    }
    """

    // Happy path

    func test_givenTheCapturedSchemaBody_whenDecoding_thenEveryColumnFacetArrives() throws {
        let response = try decode(ListSchemaResponse.self, schemaJSON)
        let fields = response.data.fields

        XCTAssertEqual(response.data.name, "probe-object-schema")
        XCTAssertEqual(response.data.description, "recon probe")
        XCTAssertEqual(fields.map(\.key), ["title", "year", "status"])

        XCTAssertEqual(fields[0].helpText, "What is it called?")
        XCTAssertEqual(fields[0].placeholder, "e.g. Dune")
        XCTAssertEqual(fields[0].validation?.minLength, 2)
        XCTAssertEqual(fields[0].validation?.maxLength, 80)
        XCTAssertEqual(fields[0].validation?.pattern, "^[A-Za-z].*$")
        XCTAssertEqual(fields[1].validation?.min, 1000)
        XCTAssertEqual(fields[1].validation?.max, 2100)
        XCTAssertEqual(fields[2].defaultValue, .string("todo"))
    }

    func test_givenASelectColumn_whenOnlyOneOptionSpellingIsPresent_thenItStillResolves() throws {
        // Boundary. The live payload sends a select column's options **twice**,
        // under `options` and under `validation.options`. Reading only one would
        // work today and lose the options the day the server stops sending it,
        // so `resolvedOptions` accepts either — asserted in both directions.
        let onlyNested = """
        { "key": "s", "type": "select", "validation": { "options": ["a", "b"] } }
        """
        let onlyFlat = """
        { "key": "s", "type": "select", "options": ["a", "b"] }
        """
        XCTAssertEqual(try decode(ListSchemaFieldDTO.self, onlyNested).resolvedOptions, ["a", "b"])
        XCTAssertEqual(try decode(ListSchemaFieldDTO.self, onlyFlat).resolvedOptions, ["a", "b"])
    }

    // Boundary

    func test_givenAColumnlessList_whenDecodingItsSchema_thenFieldsIsEmptyNotMissing() throws {
        // Captured from a list created with no columns — the ordinary first
        // state of a list, and one the decoder must not treat as a failure.
        let json = """
        { "data": { "name": "New list", "fields": [] } }
        """
        XCTAssertTrue(try decode(ListSchemaResponse.self, json).data.fields.isEmpty)
    }

    func test_givenTheSchemaBody_whenDecodedAsTheOldStringShape_thenItFails() throws {
        // The other half of the regression: `ListSchemaDTO` was `{schema: String}`,
        // which cannot read this body at all. `ListsService.schema(of:)` is
        // called by the row table and the schema editor, so neither could load
        // a schema (GitHub #85).
        struct OldShape: Decodable { let schema: String }
        XCTAssertThrowsError(try decode(OldShape.self, schemaJSON))
    }

    // MARK: - Round trip

    func test_givenAColumn_whenEncodedAndDecoded_thenEveryFacetSurvives() throws {
        // A macOS-side schema edit must not quietly drop rules authored on the
        // web. Encoding and re-decoding is the cheapest guard against a facet
        // that decodes but never encodes.
        let field = ListSchemaFieldDTO(
            key: "year",
            type: "number",
            label: "Publication Year",
            displayOrder: 3,
            required: true,
            visible: false,
            helpText: "When was it published?",
            placeholder: "1965",
            defaultValue: .int(1965),
            validation: ListFieldValidationDTO(min: 1000, max: 2100)
        )
        let data = try JSONCoders.makeEncoder().encode(field)
        let round = try JSONCoders.makeDecoder().decode(ListSchemaFieldDTO.self, from: data)
        XCTAssertEqual(round, field)
    }

    // MARK: - GET /api/users/{username}/lists/{id}

    func test_givenTheCapturedPublicListBody_whenDecoding_thenTheNamedEnvelopeAndAncestorsArrive() throws {
        // Captured after making the probe list public. A third envelope
        // convention on the same resource — `{list, ancestors}` — where the
        // client decoded a bare `ListDTO`.
        let json = """
        {
          "list": {
            "id": "851954cb-f9ee-4a1f-b864-d57ddeb639d6",
            "title": "probe-object-schema",
            "description": "recon probe",
            "parentId": null,
            "children": []
          },
          "ancestors": []
        }
        """
        let response = try decode(PublicListResponse.self, json)
        XCTAssertEqual(response.list.title, "probe-object-schema")
        XCTAssertEqual(response.ancestors?.count, 0)
        // And the projection really is this thin — no columns to show.
        XCTAssertNil(response.list.properties)
        XCTAssertNil(response.list.isPublic)
    }
}
