import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `ExportsService` (PLAN.md §1 "Data Exports",
/// §6 M7, §7 testing). Required quartet per behavior.
///
/// The four test pairs exercise:
///   1. Happy path (three methods — messages, lists, follows)
///   2. Upstream API failure — error propagates unchanged
///   3. Boundary — empty response body (list-data-rows with zero rows)
///
/// Note: `StubAPIClient.sendRaw` returns `(data, "application/json")` for
/// any enqueued `.json(data)` outcome; contentType assertions reflect that
/// stub behavior.
final class ExportsServiceTests: XCTestCase {

    // MARK: - Happy path

    func test_givenSuccessfulResponse_whenExportMessages_thenReturnsCsvExport() async throws {
        // Given
        let api = StubAPIClient()
        let csvBytes = Data("id,content\n1,hello world".utf8)
        await api.enqueue(data: csvBytes)
        let service = ExportsService(api: api)

        // When
        let export = try await service.exportMessages()

        // Then — raw bytes forwarded, kit path is correct.
        XCTAssertEqual(export.data, csvBytes)
        XCTAssertNotNil(export.contentType)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "GET")
        XCTAssertEqual(recorded.first?.path, "/api/exports/messages")
    }

    func test_givenSuccessfulResponse_whenExportLists_thenReturnsCsvExport() async throws {
        // Given
        let api = StubAPIClient()
        let csvBytes = Data("id,title\n1,My List".utf8)
        await api.enqueue(data: csvBytes)
        let service = ExportsService(api: api)

        // When
        let export = try await service.exportLists()

        // Then
        XCTAssertEqual(export.data, csvBytes)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/exports/lists")
    }

    func test_givenSuccessfulResponse_whenExportFollows_thenReturnsCsvExport() async throws {
        // Given
        let api = StubAPIClient()
        let csvBytes = Data("follower,following\nada,grace".utf8)
        await api.enqueue(data: csvBytes)
        let service = ExportsService(api: api)

        // When
        let export = try await service.exportFollows()

        // Then
        XCTAssertEqual(export.data, csvBytes)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/exports/follows")
    }

    // MARK: - Upstream API failure

    func test_givenAPIError_whenExportMessages_thenThrows() async throws {
        // Given — upstream failure (e.g. session token expired).
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 401, serverMessage: "unauthorized"))
        let service = ExportsService(api: api)

        // When / Then
        do {
            _ = try await service.exportMessages()
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 401, serverMessage: "unauthorized"))
        }
    }

    // MARK: - Boundary

    func test_givenEmptyResponseData_whenExportListDataRows_thenReturnsCsvExportWithEmptyData() async throws {
        // Given — boundary: server returns empty body (no rows to export).
        let api = StubAPIClient()
        await api.enqueue(data: Data())
        let service = ExportsService(api: api)

        // When
        let export = try await service.exportListDataRows()

        // Then — empty bytes are a valid domain result; forwarded unchanged.
        XCTAssertTrue(export.data.isEmpty)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/exports/list-data-rows")
    }
}
