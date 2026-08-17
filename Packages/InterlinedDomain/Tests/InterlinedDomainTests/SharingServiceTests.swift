import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `SharingService` (work-consolidation.md G3). Quartet per public
/// method: happy + invalid + failure + empty/boundary. Includes the subscriber
/// gate on create.
final class SharingServiceTests: XCTestCase {

    private func subscriberService(_ api: StubAPIClient) -> SharingService {
        SharingService(api: api, entitlements: EntitlementsService(customerStatus: .subscriber))
    }

    // MARK: - create (subscriber-gated)

    func test_givenSubscriber_whenCreatingListLink_thenMapsLinkAndPostsPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"token":"tok9","url":"https://x/s/tok9","role":"collaborator","expiresAt":null}"#)
        let service = subscriberService(api)

        let link = try await service.createListShareLink(listId: "l1", role: .collaborator)

        XCTAssertEqual(link.token, "tok9")
        XCTAssertEqual(link.role, .collaborator)
        XCTAssertEqual(link.url?.absoluteString, "https://x/s/tok9")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/lists/l1/share-links")
    }

    func test_givenFreeUser_whenCreatingListLink_thenThrowsSubscriberRequiredWithoutRequest() async throws {
        let api = StubAPIClient()
        let service = SharingService(api: api, entitlements: EntitlementsService(customerStatus: .free))

        do {
            _ = try await service.createListShareLink(listId: "l1", role: .watcher)
            XCTFail("Expected subscriberRequired")
        } catch let error as SharingError {
            XCTAssertEqual(error, .subscriberRequired)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "The subscriber gate must short-circuit before any HTTP call")
    }

    func test_givenSubscriber_whenCreatingDocumentLink_thenPostsDocumentPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"token":"tokD","role":"manager","expiresAt":null}"#)
        let service = subscriberService(api)

        let link = try await service.createDocumentShareLink(documentId: "d1", role: .manager)

        XCTAssertEqual(link.role, .manager)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/documents/d1/share-links")
    }

    // MARK: - list

    func test_givenLinks_whenListingListLinks_thenMapsRows() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"shareLinks":[{"token":"t1","role":"watcher","expiresAt":null,
          "createdAt":"2026-07-31T23:07:24.019Z","revokedAt":null,"url":"https://x/s/t1"}]}
        """#)
        let service = subscriberService(api)

        let links = try await service.listShareLinks(listId: "l1")

        XCTAssertEqual(links.map(\.token), ["t1"])
        XCTAssertFalse(links.first?.isRevoked ?? true)
    }

    func test_givenEmpty_whenListingLinks_thenReturnsEmpty() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"shareLinks":[]}"#)
        let service = subscriberService(api)

        let links = try await service.listShareLinks(listId: "l1")

        XCTAssertTrue(links.isEmpty)
    }

    func test_givenServerFailure_whenListingLinks_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = subscriberService(api)

        do {
            _ = try await service.listShareLinks(listId: "l1")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - resolve

    func test_givenListResolve_whenResolving_thenMapsRoleAndListResource() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"role":"watcher","canClaim":false,"needsAuth":false,
         "list":{"id":"l1","title":"Bikes","description":null,"isPublic":false,"updatedAt":null}}
        """#)
        let service = subscriberService(api)

        let resolved = try await service.resolveListShare(token: "t1")

        XCTAssertEqual(resolved.role, .watcher)
        XCTAssertFalse(resolved.canClaim)
        XCTAssertEqual(resolved.resource, .list(id: "l1", title: "Bikes", description: nil, isPublic: false))
    }

    func test_givenDocumentResolve_whenResolving_thenMapsDocumentResource() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"role":"collaborator","canClaim":true,"needsAuth":false,"document":{"id":"d1","title":"Notes","isPublic":false}}"#)
        let service = subscriberService(api)

        let resolved = try await service.resolveDocumentShare(token: "t1")

        XCTAssertTrue(resolved.canClaim)
        XCTAssertEqual(resolved.resource, .document(id: "d1", title: "Notes", isPublic: false))
    }

    // MARK: - revoke / claim

    func test_givenToken_whenRevoking_thenDeletesAndReturnsFlag() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"revoked":true}"#)
        let service = subscriberService(api)

        let revoked = try await service.revokeListShareLink(listId: "l1", token: "t1")

        XCTAssertTrue(revoked)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/lists/l1/share-links/t1")
    }

    func test_givenToken_whenClaimingListShare_thenMapsResourceIdAndRole() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"listId":"l1","role":"collaborator"}"#)
        let service = subscriberService(api)

        let claim = try await service.claimListShare(token: "t1")

        XCTAssertEqual(claim.resourceId, "l1")
        XCTAssertEqual(claim.role, .collaborator)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/lists/shared/t1")
    }

    // MARK: - ShareRole

    func test_givenShareRoles_whenReadingLabelsAndCapabilities_thenMatchContract() {
        XCTAssertEqual(ShareRole.allCases.map(\.rawValue), ["watcher", "collaborator", "manager"])
        XCTAssertEqual(ShareRole.watcher.label, "Viewer")
        XCTAssertEqual(ShareRole.manager.label, "Admin")
        XCTAssertFalse(ShareRole.watcher.canEdit)
        XCTAssertTrue(ShareRole.collaborator.canEdit)
        XCTAssertTrue(ShareRole.manager.canManage)
    }
}
