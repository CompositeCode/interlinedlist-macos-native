import XCTest
@testable import InterlinedKit

/// BDD tests for the server document-templates builders (work-consolidation.md G12).
final class DocumentTemplatesEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport(),
        tokenStore: TokenStore = InMemoryTokenStore(initial: "il_tok_abc")
    ) -> (APIClient, StubHTTPDataTransport) {
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: transport, authTransport: auth)
        return (client, transport)
    }

    func test_givenTemplateBuilders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(Documents.templates().path, "/api/documents/templates")
        XCTAssertEqual(Documents.templates().method, .get)
        XCTAssertEqual(Documents.templates().auth, .bearer)

        XCTAssertEqual(Documents.createFromTemplate(CreateFromTemplateRequest(templateDocumentId: "t1")).method, .post)
        XCTAssertEqual(Documents.createFromTemplate(CreateFromTemplateRequest(templateDocumentId: "t1")).path, "/api/documents/from-template")

        XCTAssertEqual(Documents.seedDefaultTemplates().path, "/api/documents/templates/seed-defaults")
        XCTAssertEqual(Documents.seedDefaultTemplates().method, .post)
    }

    func test_givenTemplatesBody_whenSent_thenDecodesTemplates() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"folderCreated":false,"templatesFolderId":"f-tpl",
         "templates":[
           {"id":"t1","title":"Recipe","relativePath":"recipe.md"},
           {"id":"t2","title":"Social Media Campaign","relativePath":"social-media-campaign.md"}
         ]}
        """#))

        let response = try await client.send(Documents.templates())

        XCTAssertEqual(response.templates.map(\.id), ["t1", "t2"])
        XCTAssertEqual(response.templatesFolderId, "f-tpl")
    }

    func test_givenTemplateId_whenCreateFromTemplateSent_thenEncodesTemplateDocumentId() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{}"#, status: 201))

        _ = try await client.send(Documents.createFromTemplate(CreateFromTemplateRequest(templateDocumentId: "t1")))

        let received = await transport.received
        let body = try XCTUnwrap(received[0].httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["templateDocumentId"] as? String, "t1")
    }

    func test_givenBadRequest_whenCreateFromTemplateSent_thenThrows() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"templateDocumentId is required."}"#, status: 400))

        do {
            _ = try await client.send(Documents.createFromTemplate(CreateFromTemplateRequest(templateDocumentId: "")))
            XCTFail("Expected badRequest")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "templateDocumentId is required."))
        }
    }

    func test_givenNoTemplates_whenSent_thenReturnsEmpty() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"folderCreated":true,"templatesFolderId":"f","templates":[]}"#))

        let response = try await client.send(Documents.templates())

        XCTAssertTrue(response.templates.isEmpty)
        XCTAssertEqual(response.folderCreated, true)
    }
}
