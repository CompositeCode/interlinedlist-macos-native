import XCTest
@testable import InterlinedPersistence

final class InterlinedPersistenceTests: XCTestCase {
    func test_givenPersistenceNamespace_whenSchemaVersionRead_thenMatchesDomainConstant() {
        // Given / When
        let version = InterlinedPersistence.domainKitSchemaVersion

        // Then
        XCTAssertEqual(version, "0.0.1-M0")
    }

    func test_givenPersistenceNamespace_whenSchemaVersionRead_thenIsNotEmpty() {
        XCTAssertFalse(InterlinedPersistence.domainKitSchemaVersion.isEmpty)
    }
}
