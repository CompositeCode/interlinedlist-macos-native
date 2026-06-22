import XCTest
@testable import InterlinedPersistence

final class InterlinedPersistenceTests: XCTestCase {
    func test_givenPersistenceNamespace_whenBuiltAgainstDomainVersionRead_thenIsNotEmpty() {
        // Surfaces the cross-package version pin so accidental local-package
        // skew is visible at a glance (PLAN.md §3 — three packages, one
        // schema baseline).
        XCTAssertFalse(InterlinedPersistence.builtAgainstDomainVersion.isEmpty)
    }
}
