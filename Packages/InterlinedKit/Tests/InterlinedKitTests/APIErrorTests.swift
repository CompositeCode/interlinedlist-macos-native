import XCTest
@testable import InterlinedKit

final class APIErrorTests: XCTestCase {
    func test_givenMessage_whenInitialized_thenHoldsMessageValue() {
        // Given
        let message = "unauthorized"

        // When
        let error = APIError(message: message)

        // Then
        XCTAssertEqual(error.message, "unauthorized")
        XCTAssertEqual(error.description, "unauthorized")
    }

    func test_givenTwoErrorsWithSameMessage_whenCompared_thenAreEqual() {
        // Given
        let a = APIError(message: "rate limited")
        let b = APIError(message: "rate limited")

        // When / Then
        XCTAssertEqual(a, b)
    }

    func test_givenTwoErrorsWithDifferentMessages_whenCompared_thenAreNotEqual() {
        // Given
        let a = APIError(message: "not found")
        let b = APIError(message: "forbidden")

        // When / Then
        XCTAssertNotEqual(a, b)
    }

    func test_givenInterlinedKitNamespace_whenSchemaVersionRead_thenReturnsM0Tag() {
        XCTAssertEqual(InterlinedKit.schemaVersion, "0.0.1-M0")
    }
}
