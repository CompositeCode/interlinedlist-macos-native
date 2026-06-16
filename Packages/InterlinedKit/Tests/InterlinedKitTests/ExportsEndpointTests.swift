import XCTest
@testable import InterlinedKit

/// BDD tests for the Exports endpoint group — CSV exports over the
/// session-only transport (decision 0001 allowlist), consumed via `sendRaw`.
final class ExportsEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    /// Exports route through the `.session` transport, so the canned CSV is
    /// enqueued on the session stub, not the base transport.
    private func makeClient() -> (APIClient, StubHTTPDataTransport, StubHTTPDataTransport) {
        let base = StubHTTPDataTransport()
        let session = StubHTTPDataTransport()
        let auth = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(initial: "il_tok_abc"),
            sessionTransport: session,
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: base, authTransport: auth)
        return (client, base, session)
    }

    // MARK: - Builder shape assertions

    func test_givenExportBuilders_whenConstructed_thenUseGetAndSessionAuth() {
        XCTAssertEqual(Exports.messages().method, .get)
        XCTAssertEqual(Exports.messages().path, "/api/exports/messages")
        XCTAssertEqual(Exports.messages().auth, .session)

        XCTAssertEqual(Exports.lists().path, "/api/exports/lists")
        XCTAssertEqual(Exports.lists().auth, .session)

        XCTAssertEqual(Exports.listDataRows().path, "/api/exports/list-data-rows")
        XCTAssertEqual(Exports.listDataRows().auth, .session)

        XCTAssertEqual(Exports.follows().path, "/api/exports/follows")
        XCTAssertEqual(Exports.follows().auth, .session)
    }

    // MARK: - Happy path

    func test_givenCSVBody_whenSendRawMessages_thenReturnsBytesAndContentType() async throws {
        let (client, _, session) = makeClient()
        let csv = Data("id,content\n1,hello\n".utf8)
        await session.enqueue(.data(csv, headers: ["Content-Type": "text/csv"]))

        let raw = try await client.sendRaw(Exports.messages())
        let export = CSVExport.from(raw)

        XCTAssertEqual(export.data, csv)
        XCTAssertEqual(export.contentType, "text/csv")
        XCTAssertEqual(export.text, "id,content\n1,hello\n")

        // Routed through the session transport, not the base transport.
        let received = await session.received
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].url?.path, "/api/exports/messages")
    }

    func test_givenCSVBody_whenSendRawListDataRows_thenReturnsBytes() async throws {
        let (client, _, session) = makeClient()
        let csv = Data("listId,rowId,field,value\nL1,R1,Title,Dune\n".utf8)
        await session.enqueue(.data(csv, headers: ["Content-Type": "text/csv"]))

        let export = CSVExport.from(try await client.sendRaw(Exports.listDataRows()))

        XCTAssertEqual(export.data, csv)
    }

    // MARK: - API failure

    func test_givenForbidden_whenSendRawExport_thenThrowsForbidden() async throws {
        let (client, _, session) = makeClient()
        await session.enqueue(.json(#"{"error":"export not available"}"#, status: 403))

        do {
            _ = try await client.sendRaw(Exports.lists())
            XCTFail("Expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "export not available"))
        }
    }

    // MARK: - Empty / boundary

    func test_givenHeaderOnlyCSV_whenSendRawFollows_thenReturnsHeaderRowOnly() async throws {
        let (client, _, session) = makeClient()
        let csv = Data("type,userId\n".utf8)
        await session.enqueue(.data(csv, headers: ["Content-Type": "text/csv"]))

        let export = CSVExport.from(try await client.sendRaw(Exports.follows()))

        XCTAssertEqual(export.text, "type,userId\n")
    }

    func test_givenNonUTF8Bytes_whenDecodedAsText_thenTextIsNil() {
        let invalid = Data([0xFF, 0xFE, 0xFD])
        let export = CSVExport(data: invalid, contentType: "text/csv")

        XCTAssertNil(export.text)
        XCTAssertEqual(export.data, invalid)
    }
}
