import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD tests for `MaterializeService` and the Create-from domain models
/// (work-consolidation.md G16).
final class MaterializeServiceTests: XCTestCase {

    private func spec(
        source: MaterializeSourceRef = .messages(ids: ["m1"]),
        output: MaterializeOutput = .list,
        title: String = "From messages",
        columns: [MaterializeColumn]? = nil
    ) -> MaterializeSpec {
        MaterializeSpec(
            source: source,
            output: output,
            list: output.createsList
                ? .init(title: title, columns: columns ?? MaterializeColumn.defaults(for: source))
                : nil,
            document: output.createsDocument ? .init(title: title) : nil
        )
    }

    // MARK: - Happy path

    func test_givenListSpec_whenCreated_thenPostsToMaterializeAndMapsTheNestedId() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"list":{"id":"l-new","title":"From messages"}}"#)

        let outcome = try await MaterializeService(api: api).create(spec())

        XCTAssertEqual(outcome.listId, "l-new")
        XCTAssertEqual(outcome.listTitle, "From messages")
        XCTAssertNil(outcome.documentId)
        XCTAssertFalse(outcome.isEmpty)

        let recorded = await api.recorded
        XCTAssertEqual(recorded.map(\.path), ["/api/materialize"])
        XCTAssertEqual(recorded.first?.method, "POST")
    }

    func test_givenBothOutput_whenCreated_thenMapsBothCreatedObjects() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"list":{"id":"l-1","title":"Both"},"document":{"id":"d-1","title":"Both"}}
        """#)

        let outcome = try await MaterializeService(api: api).create(spec(output: .both, title: "Both"))

        XCTAssertEqual(outcome.listId, "l-1")
        XCTAssertEqual(outcome.documentId, "d-1")
        XCTAssertEqual(outcome.documentTitle, "Both")
    }

    // MARK: - Wire mapping

    func test_givenDomainColumns_whenMapped_thenUseTheRoutesOwnPropertyNames() {
        let column = MaterializeColumn(key: "content", name: "Content", type: .textarea)
        let field = column.wireField

        // This route wants propertyKey/propertyName/propertyType/sourceKey — not the
        // key/label/type used elsewhere in the schema API.
        XCTAssertEqual(field.propertyKey, "content")
        XCTAssertEqual(field.propertyName, "Content")
        XCTAssertEqual(field.propertyType, .textarea)
        XCTAssertEqual(field.sourceKey, "content", "sourceKey defaults to the column key")
    }

    func test_givenEverySourceKind_whenMapped_thenCarriesItsIdentifiers() {
        XCTAssertEqual(MaterializeSourceRef.messages(ids: ["a"]).wireSource, .messages(ids: ["a"]))
        XCTAssertEqual(MaterializeSourceRef.lists(ids: ["l"]).wireSource, .lists(ids: ["l"]))
        XCTAssertEqual(MaterializeSourceRef.rows(listId: "l", rowIds: ["r"]).wireSource,
                       .rows(listId: "l", rowIds: ["r"]))
        XCTAssertEqual(MaterializeSourceRef.document(id: "d").wireSource, .document(id: "d"))
        XCTAssertEqual(MaterializeSourceRef.documentSelection(documentId: "d", markdown: "sel").wireSource,
                       .documentElements(documentId: "d", markdown: "sel"))
    }

    func test_givenOutputsAndStyles_whenMapped_thenMatchTheWireEnums() {
        XCTAssertEqual(MaterializeOutput.list.wireTarget, .list)
        XCTAssertEqual(MaterializeOutput.document.wireTarget, .doc)
        XCTAssertEqual(MaterializeOutput.both.wireTarget, .both)
        XCTAssertEqual(MaterializeBulletStyle.numbered.wireStyle, .numbered)
        XCTAssertEqual(MaterializeRowStyle.paragraph.wireStyle, .paragraph)
        // Every domain column type must have a wire counterpart; a typo would
        // silently degrade the column to `.text`.
        for type in MaterializeColumnType.allCases {
            XCTAssertEqual(type.wireType.rawValue, type.rawValue, "\(type) lost its wire type")
        }
    }

    func test_givenDefaultsPerSource_whenBuilt_thenMatchTheWebAppsStartingColumns() {
        let messageDefaults = MaterializeColumn.defaults(for: .messages(ids: ["m"]))
        XCTAssertEqual(messageDefaults.map(\.key), ["content", "author", "posted", "links", "tags"])
        XCTAssertEqual(messageDefaults.map(\.name), ["Content", "Author", "Posted", "Links", "Tags"])
        XCTAssertEqual(messageDefaults.map(\.type),
                       [.textarea, .text, .text, .textarea, .text])
        XCTAssertFalse(MaterializeColumn.defaults(for: .document(id: "d")).isEmpty)
    }

    func test_givenSources_whenTitled_thenReadNaturallyForOneAndMany() {
        XCTAssertEqual(MaterializeSourceRef.messages(ids: ["a"]).defaultTitle(authorHandle: "adron"),
                       "Message by @adron")
        XCTAssertEqual(MaterializeSourceRef.messages(ids: ["a", "b"]).defaultTitle(authorHandle: "adron"),
                       "2 messages")
        XCTAssertEqual(MaterializeSourceRef.messages(ids: ["a"]).defaultTitle(authorHandle: nil), "Message")
        XCTAssertEqual(MaterializeSourceRef.rows(listId: "l", rowIds: ["r1", "r2"]).defaultTitle(authorHandle: nil),
                       "2 rows")
    }

    // MARK: - Invalid input

    func test_givenListOutputWithNoTitle_whenCreated_thenRefusesWithoutCallingTheServer() async throws {
        let api = StubAPIClient()
        var incomplete = spec()
        incomplete.list?.title = "   "

        do {
            _ = try await MaterializeService(api: api).create(incomplete)
            XCTFail("Expected MaterializeError.incompleteSpec")
        } catch MaterializeError.incompleteSpec {
            let count = await api.recorded.count
            XCTAssertEqual(count, 0, "an incomplete spec must not reach the server")
        }
    }

    func test_givenListOutputWithNoColumns_whenChecked_thenSpecIsIncomplete() {
        var incomplete = spec()
        incomplete.list?.columns = []
        XCTAssertFalse(incomplete.isComplete)
    }

    func test_givenDocumentOutputWithNoTitle_whenChecked_thenSpecIsIncomplete() {
        var incomplete = spec(output: .document)
        incomplete.document?.title = ""
        XCTAssertFalse(incomplete.isComplete)
    }

    func test_givenCompleteSpecs_whenChecked_thenAreComplete() {
        XCTAssertTrue(spec().isComplete)
        XCTAssertTrue(spec(output: .document).isComplete)
        XCTAssertTrue(spec(output: .both).isComplete)
    }

    // MARK: - Upstream failure

    func test_givenUnavailableSource_whenCreated_thenPropagatesNotFound() async throws {
        let api = StubAPIClient()
        // The live 404 when a source id does not resolve.
        await api.enqueue(failure: .notFound(serverMessage: "One or more messages are unavailable"))

        do {
            _ = try await MaterializeService(api: api).create(spec())
            XCTFail("Expected the underlying APIError")
        } catch APIError.notFound(let message) {
            XCTAssertEqual(message, "One or more messages are unavailable")
        }
    }

    // MARK: - Empty / boundary

    func test_givenAcknowledgementWithNoIds_whenCreated_thenOutcomeReportsEmpty() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{}"#)

        let outcome = try await MaterializeService(api: api).create(spec())

        XCTAssertTrue(outcome.isEmpty)
        XCTAssertNil(outcome.listId)
    }

    func test_givenFlatIdResponse_whenCreated_thenStillSurfacesTheId() async throws {
        let api = StubAPIClient()
        // A future server that flattens the created object must still work.
        await api.enqueue(json: #"{"listId":"l-flat"}"#)

        let outcome = try await MaterializeService(api: api).create(spec())

        XCTAssertEqual(outcome.listId, "l-flat")
        XCTAssertNil(outcome.listTitle)
    }
}
