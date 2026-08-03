import XCTest
@testable import InterlinedKit

final class APIErrorTests: XCTestCase {

    // MARK: - Status code → case mapping

    func test_given400Status_whenMapped_thenReturnsBadRequestWithServerMessage() {
        // Given / When
        let error = APIError.from(statusCode: 400, serverMessage: "Missing field: email")

        // Then
        XCTAssertEqual(error, .badRequest(serverMessage: "Missing field: email"))
        XCTAssertEqual(error.httpStatusCode, 400)
    }

    func test_given401Status_whenMapped_thenReturnsUnauthorized() {
        let error = APIError.from(statusCode: 401, serverMessage: "Unauthorized")
        XCTAssertEqual(error, .unauthorized(serverMessage: "Unauthorized"))
        XCTAssertEqual(error.httpStatusCode, 401)
    }

    func test_given403Status_whenMapped_thenReturnsForbiddenPreservingServerMessage() {
        // Given — 403 carries operationally distinct messages (email not
        // verified, subscriber feature). The exact string must reach the UI.
        let error = APIError.from(statusCode: 403, serverMessage: "Email not verified")

        // Then
        XCTAssertEqual(error, .forbidden(serverMessage: "Email not verified"))
        if case .forbidden(let message) = error {
            XCTAssertEqual(message, "Email not verified")
        } else {
            XCTFail("Expected .forbidden")
        }
    }

    func test_given404Status_whenMapped_thenReturnsNotFound() {
        let error = APIError.from(statusCode: 404, serverMessage: "Not found")
        XCTAssertEqual(error, .notFound(serverMessage: "Not found"))
    }

    func test_given429Status_whenMappedWithRetryAfter_thenCarriesDelay() {
        let error = APIError.from(statusCode: 429, serverMessage: nil, retryAfter: 5)
        XCTAssertEqual(error, .rateLimited(serverMessage: nil, retryAfter: 5))
    }

    func test_given429StatusWithNoRetryAfterHeader_whenMapped_thenRateLimitedWithNilDelay() {
        // Boundary: Retry-After absent (header not emitted by this route).
        // Must produce .rateLimited with nil retryAfter — not an error, not a crash.
        let error = APIError.from(statusCode: 429, serverMessage: "slow down", retryAfter: nil)
        XCTAssertEqual(error, .rateLimited(serverMessage: "slow down", retryAfter: nil))
        if case .rateLimited(_, let delay) = error {
            XCTAssertNil(delay, "Absent Retry-After must yield nil delay, not a default value")
        } else {
            XCTFail("Expected .rateLimited")
        }
    }

    func test_given500Status_whenMapped_thenFallsBackToHttpStatus() {
        let error = APIError.from(statusCode: 500, serverMessage: "Server error")
        XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "Server error"))
    }

    // MARK: - Equality

    func test_givenIdenticalCases_whenCompared_thenAreEqual() {
        XCTAssertEqual(
            APIError.transport(message: "offline"),
            APIError.transport(message: "offline")
        )
    }

    func test_givenDifferentCases_whenCompared_thenAreNotEqual() {
        XCTAssertNotEqual(
            APIError.unauthorized(serverMessage: "a"),
            APIError.forbidden(serverMessage: "a")
        )
    }

    // MARK: - Server-message descriptions

    func test_givenForbiddenWithServerMessage_whenDescribed_thenReturnsServerMessage() {
        let error = APIError.forbidden(serverMessage: "Subscriber feature")
        XCTAssertEqual(error.errorDescription, "Subscriber feature")
        XCTAssertEqual(error.description, "Subscriber feature")
    }

    func test_givenUnauthorizedWithNoMessage_whenDescribed_thenReturnsFallback() {
        let error = APIError.unauthorized(serverMessage: nil)
        XCTAssertEqual(error.description, "Unauthorized")
    }

    // MARK: - User-facing vs. technical messages

    func test_givenDecodingError_whenUserFacing_thenHidesTechnicalDetail() {
        let error = APIError.decoding(type: "ListRowDTO", message: "keyNotFound(CodingKeys(stringValue: \"id\"))")

        // The UI (localizedDescription → errorDescription → userFacingMessage)
        // must not leak the decoder jargon…
        XCTAssertFalse(error.userFacingMessage.contains("ListRowDTO"))
        XCTAssertFalse(error.userFacingMessage.lowercased().contains("decoding"))
        XCTAssertFalse(error.userFacingMessage.lowercased().contains("keynotfound"))
        XCTAssertEqual(error.errorDescription, error.userFacingMessage)

        // …but the technical form (for the debug log) still carries it.
        XCTAssertTrue(error.description.contains("ListRowDTO"))
        XCTAssertTrue(error.description.contains("keyNotFound"))
    }

    func test_givenTransportError_whenUserFacing_thenIsFriendlyConnectionMessage() {
        let error = APIError.transport(message: "The request timed out.")
        XCTAssertFalse(error.userFacingMessage.lowercased().contains("network error"))
        XCTAssertTrue(error.userFacingMessage.contains("connection"))
        // Technical detail preserved for the log.
        XCTAssertEqual(error.description, "Network error: The request timed out.")
    }

    func test_givenServerMessage_whenUserFacing_thenPreservesItVerbatim() {
        // 4xx server messages are already human-written — keep them.
        XCTAssertEqual(
            APIError.forbidden(serverMessage: "Email not verified").userFacingMessage,
            "Email not verified"
        )
        XCTAssertEqual(
            APIError.badRequest(serverMessage: "Name is required").userFacingMessage,
            "Name is required"
        )
    }

    func test_givenStatusWithoutServerMessage_whenUserFacing_thenFriendlyFallback() {
        let error = APIError.httpStatus(code: 500, serverMessage: nil)
        XCTAssertFalse(error.userFacingMessage.contains("500"))
        XCTAssertEqual(error.description, "HTTP 500")
    }

    // MARK: - APIErrorBody decoding

    func test_givenErrorBodyJSON_whenDecoded_thenExtractsMessage() throws {
        // Given — the canonical {error: "..."} shape.
        let json = #"{"error":"Email not verified"}"#

        // When
        let body = try JSONDecoder().decode(APIErrorBody.self, from: Data(json.utf8))

        // Then
        XCTAssertEqual(body.error, "Email not verified")
    }

    func test_givenEmptyJSONBody_whenDecoded_thenFails() {
        // Boundary case: an empty `{}` carries no error field.
        let json = "{}"
        XCTAssertThrowsError(
            try JSONDecoder().decode(APIErrorBody.self, from: Data(json.utf8))
        )
    }

    // MARK: - Namespace marker

    func test_givenInterlinedKitNamespace_whenSchemaVersionRead_thenReturnsWave1Tag() {
        XCTAssertEqual(InterlinedKit.schemaVersion, "0.1.0-Wave1")
    }
}
