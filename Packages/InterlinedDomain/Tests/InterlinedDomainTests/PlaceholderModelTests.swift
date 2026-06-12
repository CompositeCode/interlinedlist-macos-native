import XCTest
@testable import InterlinedDomain

final class PlaceholderModelTests: XCTestCase {
    func test_givenIdAndLabel_whenInitialized_thenHoldsValues() {
        // Given
        let id = "msg-42"
        let label = "Hello, InterlinedList"

        // When
        let model = PlaceholderModel(id: id, label: label)

        // Then
        XCTAssertEqual(model.id, "msg-42")
        XCTAssertEqual(model.label, "Hello, InterlinedList")
    }

    func test_givenTwoModelsWithSameValues_whenCompared_thenAreEqual() {
        // Given
        let a = PlaceholderModel(id: "1", label: "Inbox")
        let b = PlaceholderModel(id: "1", label: "Inbox")

        // When / Then
        XCTAssertEqual(a, b)
    }

    func test_givenDomainNamespace_whenKitSchemaQueried_thenMatchesKitConstant() {
        // The domain module must be built against a known kit version so
        // accidental version skew between local packages surfaces at test time.
        XCTAssertEqual(InterlinedDomain.kitSchemaVersion, "0.0.1-M0")
    }
}
