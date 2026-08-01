import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `LinkedInService` (the-gaps.md G11a).
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

        XCTAssertEqual(result.targets.map(\.kind), [.personal, .org])
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
}
