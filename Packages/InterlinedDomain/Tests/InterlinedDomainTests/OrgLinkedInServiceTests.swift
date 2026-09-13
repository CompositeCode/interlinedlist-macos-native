import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for the **organization** LinkedIn surface
/// (work-consolidation.md G25): credential status, page sync, per-member page
/// assignment, and disconnect.
///
/// Two shapes of the status body are exercised deliberately. Only the first
/// was observed live (`{"credential":null,"role":"member"}` — the test account
/// is a plain member of an org with no shared credential); the second is the
/// one `/help/api/organizations` documents (`{connected, expiresAt}` plus
/// pages). The client accepts both rather than betting on either.
final class OrgLinkedInServiceTests: XCTestCase {

    // MARK: - status

    func test_givenConnectedOrg_whenReadingStatus_thenMapsPagesAndAssignments() async throws {
        // Happy path, documented shape.
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"connected":true,"expiresAt":"2026-12-01T00:00:00.000Z","role":"owner",
         "pages":[{"id":"p1","linkedInPageId":"12345678","pageName":"Acme Corp",
                   "pageLogoUrl":"https://cdn/l.png"}],
         "assignments":[{"userId":"u2","pageId":"p1","pageName":"Acme Corp"}]}
        """#)
        let service = OrgService(api: api)

        let status = try await service.linkedInStatus(of: "o1")

        XCTAssertTrue(status.isConnected)
        XCTAssertEqual(status.callerRole, .owner)
        XCTAssertTrue(status.callerCanManage)
        XCTAssertEqual(status.pages.map(\.name), ["Acme Corp"])
        XCTAssertEqual(status.pages.first?.linkedInPageId, "12345678")
        XCTAssertEqual(status.assignedPage(for: "u2")?.id, "p1")
        XCTAssertNil(status.assignedPage(for: "u3"))

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "GET")
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o1/linkedin/status")
    }

    func test_givenLiveDisconnectedShape_whenReadingStatus_thenReportsDisconnected() async throws {
        // Boundary: the exact body observed live. A null credential with no
        // `connected` boolean must read as "not connected", and a member must
        // not be offered the management controls.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"credential":null,"role":"member"}"#)
        let service = OrgService(api: api)

        let status = try await service.linkedInStatus(of: "o1")

        XCTAssertFalse(status.isConnected)
        XCTAssertEqual(status.callerRole, .member)
        XCTAssertFalse(status.callerCanManage)
        XCTAssertTrue(status.pages.isEmpty)
        XCTAssertTrue(status.assignments.isEmpty)
    }

    func test_givenNestedCredential_whenReadingStatus_thenInfersConnectedAndExpiry() async throws {
        // Boundary between the observed and documented spellings.
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"credential":{"expiresAt":"2026-12-01T00:00:00.000Z"},"role":"admin","pages":[]}
        """#)
        let service = OrgService(api: api)

        let status = try await service.linkedInStatus(of: "o1")

        XCTAssertTrue(status.isConnected)
        XCTAssertNotNil(status.expiresAt)
        XCTAssertTrue(status.callerCanManage, "Admins manage the org credential too")
    }

    func test_givenServerFailure_whenReadingStatus_thenSurfacesAPIError() async throws {
        // Upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 502, serverMessage: "linkedin down"))
        let service = OrgService(api: api)

        do {
            _ = try await service.linkedInStatus(of: "o1")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 502, serverMessage: "linkedin down"))
        }
    }

    func test_givenUnknownRoleInStatus_whenGating_thenHidesManagement() async throws {
        // Boundary: an unrecognised role is not a manager. Management controls
        // stay hidden rather than rendering an action the server will reject.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"credential":null,"role":"guest"}"#)
        let service = OrgService(api: api)

        let status = try await service.linkedInStatus(of: "o1")

        XCTAssertEqual(status.callerRole, .other("guest"))
        XCTAssertFalse(status.callerCanManage)
    }

    // MARK: - sync-pages

    func test_givenOwner_whenSyncingPages_thenPostsThenRereadsStatus() async throws {
        // Happy path. The 201 body is unmodelled upstream, so the service
        // ignores it and re-reads status — the only route that returns pages.
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        await api.enqueue(json: #"""
        {"connected":true,"role":"owner",
         "pages":[{"id":"p1","pageName":"Acme Corp"},{"id":"p2","pageName":"Acme Labs"}]}
        """#)
        let service = OrgService(api: api)

        let status = try await service.syncLinkedInPages(of: "o1", callerRole: .owner)

        XCTAssertEqual(status.pages.map(\.name), ["Acme Corp", "Acme Labs"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.map(\.method), ["POST", "GET"])
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o1/linkedin/sync-pages")
        XCTAssertEqual(recorded.last?.path, "/api/organizations/o1/linkedin/status")
    }

    func test_givenMember_whenSyncingPages_thenRejectsBeforeAnyServiceCall() async throws {
        // Invalid input: sync is owner/admin only.
        let api = StubAPIClient()
        let service = OrgService(api: api)

        do {
            _ = try await service.syncLinkedInPages(of: "o1", callerRole: .member)
            XCTFail("Expected linkedInRequiresOwnerOrAdmin")
        } catch let error as OrgLifecycleError {
            XCTAssertEqual(error, .linkedInRequiresOwnerOrAdmin)
        }

        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "A rejected sync must not hit the network")
    }

    func test_givenSyncFailure_whenSyncingPages_thenSurfacesAPIErrorAndDoesNotReread() async throws {
        // Upstream API failure: the follow-up read must not run after a failed
        // sync, so the caller can keep showing its stale page list.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 502, serverMessage: "linkedin down"))
        let service = OrgService(api: api)

        do {
            _ = try await service.syncLinkedInPages(of: "o1", callerRole: .owner)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 502, serverMessage: "linkedin down"))
        }

        let recorded = await api.recorded
        XCTAssertEqual(recorded.map(\.method), ["POST"], "No status re-read after a failed sync")
    }

    func test_givenSyncReturningNoPages_whenSyncing_thenReturnsEmptyPageList() async throws {
        // Boundary: a connected credential that administers zero pages.
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        await api.enqueue(json: #"{"connected":true,"role":"owner","pages":[]}"#)
        let service = OrgService(api: api)

        let status = try await service.syncLinkedInPages(of: "o1", callerRole: .owner)

        XCTAssertTrue(status.pages.isEmpty)
        XCTAssertTrue(status.isConnected)
    }

    // MARK: - assignments

    func test_givenAdmin_whenAssigningPage_thenPutsUserIdAndPageId() async throws {
        // Happy path.
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = OrgService(api: api)

        try await service.assignLinkedInPage(in: "o1", userId: "u2", pageId: "p1", callerRole: .admin)

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PUT")
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o1/linkedin/assignments")
    }

    func test_givenNilPageId_whenAssigning_thenClearsTheAssignment() async throws {
        // Boundary: clearing an assignment sends a null page reference.
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = OrgService(api: api)

        try await service.assignLinkedInPage(in: "o1", userId: "u2", pageId: nil, callerRole: .owner)

        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    func test_givenMember_whenAssigningPage_thenRejectsBeforeAnyServiceCall() async throws {
        // Invalid input: assignment is owner/admin only.
        let api = StubAPIClient()
        let service = OrgService(api: api)

        do {
            try await service.assignLinkedInPage(in: "o1", userId: "u2", pageId: "p1", callerRole: .member)
            XCTFail("Expected linkedInRequiresOwnerOrAdmin")
        } catch let error as OrgLifecycleError {
            XCTAssertEqual(error, .linkedInRequiresOwnerOrAdmin)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenBlankUserId_whenAssigningPage_thenRejectsBeforeAnyServiceCall() async throws {
        // Invalid input: an assignment needs someone to assign to.
        let api = StubAPIClient()
        let service = OrgService(api: api)

        do {
            try await service.assignLinkedInPage(in: "o1", userId: "", pageId: "p1", callerRole: .owner)
            XCTFail("Expected unknownCurrentUser")
        } catch let error as OrgLifecycleError {
            XCTAssertEqual(error, .unknownCurrentUser)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenServerFailure_whenAssigningPage_thenSurfacesAPIError() async throws {
        // Upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "unknown page"))
        let service = OrgService(api: api)

        do {
            try await service.assignLinkedInPage(in: "o1", userId: "u2", pageId: "nope", callerRole: .owner)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "unknown page"))
        }
    }

    // MARK: - disconnect

    func test_givenOwner_whenDisconnecting_thenDeletesTheCredential() async throws {
        // Happy path.
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = OrgService(api: api)

        try await service.disconnectLinkedIn(from: "o1", callerRole: .owner)

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o1/linkedin/credential")
    }

    func test_givenMember_whenDisconnecting_thenRejectsBeforeAnyServiceCall() async throws {
        // Invalid input: disconnect is owner/admin only — and it silently
        // redirects every assigned member's cross-posts, so the gate matters.
        let api = StubAPIClient()
        let service = OrgService(api: api)

        do {
            try await service.disconnectLinkedIn(from: "o1", callerRole: .member)
            XCTFail("Expected linkedInRequiresOwnerOrAdmin")
        } catch let error as OrgLifecycleError {
            XCTAssertEqual(error, .linkedInRequiresOwnerOrAdmin)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenServerFailure_whenDisconnecting_thenSurfacesAPIError() async throws {
        // Upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = OrgService(api: api)

        do {
            try await service.disconnectLinkedIn(from: "o1", callerRole: .owner)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - page mapping + authorize URL

    func test_givenPageWithoutAName_whenMapping_thenFallsBackSoRowIsNeverBlank() {
        // Boundary: name → LinkedIn page id → record id.
        let named = OrgLinkedInPage(from: OrgLinkedInPageDTO(id: "p1", pageName: "Acme"))
        XCTAssertEqual(named.name, "Acme")

        let byLinkedInId = OrgLinkedInPage(from: OrgLinkedInPageDTO(id: "p2", linkedInPageId: "999"))
        XCTAssertEqual(byLinkedInId.name, "999")

        let bare = OrgLinkedInPage(from: OrgLinkedInPageDTO(id: "p3"))
        XCTAssertEqual(bare.name, "p3")
    }

    func test_givenOrgId_whenBuildingAuthorizeURL_thenTargetsOrgAuthorizeRoute() throws {
        // The connect flow is a browser redirect (x-auth-type: none), so the
        // client opens this URL rather than calling it.
        let url = try XCTUnwrap(
            OrgLinkedInAuthorization.url(
                baseURL: URL(string: "https://interlinedlist.com")!,
                organizationId: "o1"
            )
        )
        XCTAssertEqual(url.path, "/api/auth/linkedin/org-authorize")
        XCTAssertEqual(url.query, "organizationId=o1")
    }
}
