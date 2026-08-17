import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `DocumentTemplatesService` (work-consolidation.md G12).
final class DocumentTemplatesServiceTests: XCTestCase {

    func test_givenTemplates_whenLoading_thenMapsRefsAndHitsPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"folderCreated":false,"templatesFolderId":"f-tpl",
         "templates":[{"id":"t1","title":"Recipe","relativePath":"recipe.md"}]}
        """#)
        let service = DocumentTemplatesService(api: api)

        let templates = try await service.templates()

        XCTAssertEqual(templates.map(\.id), ["t1"])
        XCTAssertEqual(templates.first?.title, "Recipe")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/documents/templates")
        XCTAssertEqual(recorded.first?.method, "GET")
    }

    func test_givenEmpty_whenLoadingTemplates_thenReturnsEmpty() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"templates":[]}"#)
        let service = DocumentTemplatesService(api: api)

        let templates = try await service.templates()

        XCTAssertTrue(templates.isEmpty)
    }

    func test_givenServerFailure_whenLoadingTemplates_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = DocumentTemplatesService(api: api)

        do {
            _ = try await service.templates()
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    func test_givenTemplateId_whenCreatingFromTemplate_thenPostsFromTemplatePath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{}"#)
        let service = DocumentTemplatesService(api: api)

        try await service.createFromTemplate(templateDocumentId: "t1")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/documents/from-template")
    }

    func test_givenCreateFails_whenCreatingFromTemplate_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "templateDocumentId is required."))
        let service = DocumentTemplatesService(api: api)

        do {
            try await service.createFromTemplate(templateDocumentId: "")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "templateDocumentId is required."))
        }
    }

    func test_whenSeedingDefaults_thenPostsSeedPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{}"#)
        let service = DocumentTemplatesService(api: api)

        try await service.seedDefaultTemplates()

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/documents/templates/seed-defaults")
    }
}
