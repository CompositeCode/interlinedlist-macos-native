import XCTest
@testable import InterlinedDomain

/// Coverage for the `accountStatus` model (GitHub #42).
///
/// The wire field is an open string — `GET /api/openapi.json` declares it as a
/// bare `{"type":"string"}` with no enum — so the fail-open behaviour on
/// unrecognised values is the load-bearing property here, not a nicety.
final class AccountStatusTests: XCTestCase {

    // MARK: - Happy path

    func test_givenDocumentedStatusStrings_whenMapped_thenClassifiedExactly() {
        XCTAssertEqual(AccountStatus(raw: "new"), .new)
        XCTAssertEqual(AccountStatus(raw: "active"), .active)
        XCTAssertEqual(AccountStatus(raw: "restricted"), .restricted)
        XCTAssertEqual(AccountStatus(raw: "suspended"), .suspended)
        XCTAssertEqual(AccountStatus(raw: "banned"), .banned)
    }

    func test_givenMixedCaseAndPaddedStatus_whenMapped_thenStillClassified() {
        // The live payload is lowercase, but a case or whitespace change on the
        // server must not silently degrade every account to `.unknown`.
        XCTAssertEqual(AccountStatus(raw: "ACTIVE"), .active)
        XCTAssertEqual(AccountStatus(raw: "  Restricted "), .restricted)
    }

    // MARK: - Invalid / unrecognised input

    func test_givenUnrecognisedStatus_whenMapped_thenPreservedAsUnknown() {
        // Given a value this client has never seen.
        let status = AccountStatus(raw: "shadowbanned")

        // Then — preserved verbatim for display and telemetry.
        XCTAssertEqual(status, .unknown("shadowbanned"))
        XCTAssertEqual(status.rawValue, "shadowbanned")
    }

    /// The rule that keeps a server-side rename from bricking a paying user:
    /// an unknown status must disable nothing and show nothing.
    func test_givenUnrecognisedStatus_whenAskingCapabilities_thenBehavesAsActive() {
        let status = AccountStatus(raw: "some-future-state")

        XCTAssertFalse(status.isWriteRestricted)
        XCTAssertFalse(status.isOnProbation)
        XCTAssertFalse(status.warrantsBanner)
    }

    // MARK: - Upstream failure / absent field

    func test_givenAbsentOrBlankStatus_whenMapped_thenTreatedAsActive() {
        // An older server, or a payload that simply omits the field.
        XCTAssertEqual(AccountStatus(raw: nil), .active)
        XCTAssertEqual(AccountStatus(raw: ""), .active)
        XCTAssertEqual(AccountStatus(raw: "   "), .active)
    }

    // MARK: - Boundary

    func test_givenEachStatus_whenAskingForBanner_thenOnlyLimitedStatusesShowOne() {
        // `/help/account`: the banner explains a new or locked account. `.active`
        // is silent, and `.banned` cannot sign in so it never reaches a banner.
        XCTAssertTrue(AccountStatus.new.warrantsBanner)
        XCTAssertTrue(AccountStatus.restricted.warrantsBanner)
        XCTAssertTrue(AccountStatus.suspended.warrantsBanner)
        XCTAssertFalse(AccountStatus.active.warrantsBanner)
        XCTAssertFalse(AccountStatus.banned.warrantsBanner)
    }

    func test_givenReadOnlyStatuses_whenAskingWriteRestriction_thenOnlyRestrictedAndSuspended() {
        XCTAssertTrue(AccountStatus.restricted.isWriteRestricted)
        XCTAssertTrue(AccountStatus.suspended.isWriteRestricted)
        // `.new` is rate-limited, not read-only — it must stay able to post.
        XCTAssertFalse(AccountStatus.new.isWriteRestricted)
        XCTAssertFalse(AccountStatus.active.isWriteRestricted)
    }

    func test_givenEveryStatus_whenRoundTripped_thenRawValueMapsBack() {
        let statuses: [AccountStatus] = [.new, .active, .restricted, .suspended, .banned]
        for status in statuses {
            XCTAssertEqual(AccountStatus(raw: status.rawValue), status)
        }
    }
}
