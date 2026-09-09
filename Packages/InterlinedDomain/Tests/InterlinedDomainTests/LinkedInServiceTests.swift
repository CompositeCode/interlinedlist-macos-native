import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `LinkedInService` (work-consolidation.md G11a).
final class LinkedInServiceTests: XCTestCase {

    func test_givenTargets_whenLoading_thenMapsAndFlagsOrgScope() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"targets":[
           {"kind":"personal","label":"Adron Hall","avatarUrl":"https://cdn/a.png","enabled":true},
           {"kind":"org","label":"Bikey Life","avatarUrl":null,"enabled":false}
         ],"orgScopeMissing":true}
        """#)
        let service = LinkedInService(api: api)

        let result = try await service.postingTargets()

        XCTAssertEqual(result.targets.map(\.kind), [.personal, .orgPage])
        XCTAssertTrue(result.targets.first?.isEnabled ?? false)
        XCTAssertTrue(result.orgScopeMissing)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/linkedin/posting-targets")
    }

    func test_givenEmpty_whenLoading_thenReturnsEmptyTargets() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"targets":[]}"#)
        let service = LinkedInService(api: api)

        let result = try await service.postingTargets()

        XCTAssertTrue(result.targets.isEmpty)
        XCTAssertFalse(result.orgScopeMissing)
    }

    func test_givenServerFailure_whenLoading_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = LinkedInService(api: api)

        do {
            _ = try await service.postingTargets()
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    func test_givenUnknownKind_whenMapping_thenFallsBackToOther() {
        let target = LinkedInTarget(from: LinkedInTargetDTO(kind: "showcase", label: "X"))
        XCTAssertEqual(target.kind, .other)
    }

    // MARK: - Default destination (work-consolidation.md G25)
    //
    // /help/organizations: "For a member who has an assignment, the assigned
    // org page also becomes their default LinkedIn destination: if they enable
    // LinkedIn cross-posting without picking a specific destination, the post
    // goes to the assigned page rather than their personal profile."

    func test_givenRealWireKinds_whenMapping_thenDecodesPageIdentity() async throws {
        // Happy path: the three documented kinds and their page identifiers.
        // `orgPage` used to fall through to `.other`, dropping pageId entirely.
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"targets":[
           {"kind":"personal","label":"Alice Example","avatarUrl":null,"enabled":true},
           {"kind":"orgPage","pageId":"page-1","linkedInPageId":"12345678",
            "label":"Acme Corp","logoUrl":"https://cdn/l.png","enabled":true},
           {"kind":"personalPage","personalPageId":"page-2","linkedInPageId":"87654321",
            "label":"Alice's Studio","logoUrl":null,"enabled":false}
         ],"orgScopeMissing":false}
        """#)
        let service = LinkedInService(api: api)

        let result = try await service.postingTargets()

        XCTAssertEqual(result.targets.map(\.kind), [.personal, .orgPage, .personalPage])
        XCTAssertEqual(result.targets[1].pageRecordId, "page-1")
        XCTAssertEqual(result.targets[1].linkedInPageId, "12345678")
        XCTAssertEqual(result.targets[1].avatarURL?.absoluteString, "https://cdn/l.png")
        XCTAssertEqual(result.targets[2].pageRecordId, "page-2")
        XCTAssertTrue(result.targets[1].isCompanyPage)
        XCTAssertFalse(result.targets[0].isCompanyPage)
    }

    func test_givenEnabledOrgPage_whenResolvingDefault_thenPrefersCompanyPage() {
        // The behaviour the composer's "Posting as …" line depends on: an
        // assigned org page outranks the personal profile.
        let targets = LinkedInPostingTargets(targets: [
            LinkedInTarget(kind: .personal, label: "Alice Example", isEnabled: true),
            LinkedInTarget(kind: .orgPage, label: "Acme Corp", isEnabled: true, pageRecordId: "page-1")
        ])

        XCTAssertEqual(targets.defaultDestination?.kind, .orgPage)
        XCTAssertEqual(targets.defaultDestination?.label, "Acme Corp")
    }

    func test_givenDisabledOrgPage_whenResolvingDefault_thenFallsBackToPersonal() {
        // Invalid-for-this-purpose input: a switched-off page is not where the
        // post goes, so naming it would be the same lie in reverse.
        let targets = LinkedInPostingTargets(targets: [
            LinkedInTarget(kind: .personal, label: "Alice Example", isEnabled: true),
            LinkedInTarget(kind: .orgPage, label: "Acme Corp", isEnabled: false, pageRecordId: "page-1")
        ])

        XCTAssertEqual(targets.defaultDestination?.kind, .personal)
    }

    func test_givenNoTargets_whenResolvingDefault_thenReturnsNil() {
        // Boundary: an unconnected account has no destination to name.
        XCTAssertNil(LinkedInPostingTargets.empty.defaultDestination)
    }

    func test_givenOnlyUnknownKind_whenResolvingDefault_thenStillNamesSomething() {
        // Boundary: an unrecognised kind is still a destination the server
        // will post to, so the line shows it rather than going blank.
        let targets = LinkedInPostingTargets(targets: [
            LinkedInTarget(kind: .other, label: "Mystery", isEnabled: true)
        ])

        XCTAssertEqual(targets.defaultDestination?.label, "Mystery")
    }

    func test_givenTwoPagesSharingALabel_whenListed_thenIdentitiesStayDistinct() {
        // Boundary: identity keys on the record id, so same-named pages do not
        // collapse into one row in an Identifiable list.
        let a = LinkedInTarget(kind: .orgPage, label: "Acme", pageRecordId: "page-1")
        let b = LinkedInTarget(kind: .orgPage, label: "Acme", pageRecordId: "page-2")

        XCTAssertNotEqual(a.id, b.id)
    }
}

