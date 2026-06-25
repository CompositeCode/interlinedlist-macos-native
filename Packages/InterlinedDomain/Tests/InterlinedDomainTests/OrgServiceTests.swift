import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `OrgService` (PLAN.md §1 "Organizations", §6 M6,
/// §7 testing). Quartet per public method: happy + invalid input + upstream
/// API failure + empty/boundary. All nine Organizations endpoints are covered.
final class OrgServiceTests: XCTestCase {

    // MARK: - organizations (list)

    func test_givenTwoOrgs_whenListing_thenMapsPageAndForwardsFilters() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedOrganizations(
            ids: ["o-1", "o-2"], limit: 20, offset: 0, hasMore: true
        ))
        let service = OrgService(api: api)

        // When
        let page = try await service.organizations(isPublic: true, userId: "u-9", limit: 20, offset: 0)

        // Then — items mapped, pagination surfaced.
        XCTAssertEqual(page.organizations.map(\.id), ["o-1", "o-2"])
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextOffset, 20)

        // And — filters forwarded onto the query.
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/organizations")
        XCTAssertEqual(recorded.first?.query["public"], "true")
        XCTAssertEqual(recorded.first?.query["userId"], "u-9")
    }

    func test_givenMalformedListEnvelope_whenListing_thenThrows() async throws {
        // Given — invalid input: the `data` collection is the wrong shape.
        // The paginated read goes through `sendRaw` + `PaginatedDecoder`, which
        // surfaces a `DecodingError` (not wrapped in `APIError`); assert that
        // the malformed envelope fails rather than being silently accepted.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"data":{"oops":true},"pagination":{"total":0,"limit":20,"offset":0,"hasMore":false}}"#)
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.organizations(isPublic: nil, userId: nil, limit: 20, offset: 0)
            XCTFail("Expected the malformed envelope to throw")
        } catch {
            // expected — decode failed on the malformed `data` collection.
        }
    }

    func test_givenListEndpointFails_whenListing_thenThrows() async throws {
        // Given — upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.organizations(isPublic: nil, userId: nil, limit: 20, offset: 0)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    func test_givenNoOrgs_whenListing_thenReturnsEmptyPage() async throws {
        // Given — boundary: zero-item page.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedOrganizations(ids: [], hasMore: false))
        let service = OrgService(api: api)

        // When
        let page = try await service.organizations(isPublic: nil, userId: nil, limit: 20, offset: 0)

        // Then
        XCTAssertTrue(page.organizations.isEmpty)
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
    }

    // MARK: - create

    func test_givenValidFields_whenCreating_thenPostsBodyAndMapsOrg() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.organizationObject(id: "o-new", name: "Acme", isPublic: false))
        let service = OrgService(api: api)

        // When
        let org = try await service.create(name: "Acme", description: "We make things", isPublic: false)

        // Then
        XCTAssertEqual(org.id, "o-new")
        XCTAssertEqual(org.name, "Acme")
        XCTAssertFalse(org.isPublic)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/organizations")
    }

    func test_givenMalformedCreateResponse_whenCreating_thenThrowsDecoding() async throws {
        // Given — invalid input: response missing required `name`.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"id":"o-new"}"#)
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.create(name: "Acme", description: "d", isPublic: true)
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("Expected .decoding, got \(error)") }
        }
    }

    func test_givenCreateForbidden_whenCreating_thenThrowsForbidden() async throws {
        // Given — upstream API failure (e.g. quota / permissions).
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "not allowed"))
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.create(name: "Acme", description: "d", isPublic: true)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "not allowed"))
        }
    }

    func test_givenEmptyDescription_whenCreating_thenStillSucceeds() async throws {
        // Given — boundary: empty description string is accepted by the API.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.organizationObject(id: "o-2", description: nil))
        let service = OrgService(api: api)

        // When
        let org = try await service.create(name: "Acme", description: "", isPublic: true)

        // Then — maps with a nil domain description.
        XCTAssertEqual(org.id, "o-2")
        XCTAssertNil(org.description)
    }

    // MARK: - organization (get)

    func test_givenExistingId_whenGetting_thenMapsOrg() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.organizationObject(id: "o-7", name: "Globex"))
        let service = OrgService(api: api)

        // When
        let org = try await service.organization(id: "o-7")

        // Then
        XCTAssertEqual(org.id, "o-7")
        XCTAssertEqual(org.name, "Globex")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o-7")
    }

    func test_givenMissingId_whenGetting_thenThrowsNotFound() async throws {
        // Given — upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no such org"))
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.organization(id: "missing")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "no such org"))
        }
    }

    func test_givenMalformedGetResponse_whenGetting_thenThrowsDecoding() async throws {
        // Given — invalid input.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"oops":true}"#)
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.organization(id: "o-7")
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("Expected .decoding, got \(error)") }
        }
    }

    func test_givenOrgWithoutTimestamps_whenGetting_thenMapsNilDates() async throws {
        // Given — boundary: server omits createdAt / updatedAt.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.organizationObject(id: "o-8", includeTimestamps: false))
        let service = OrgService(api: api)

        // When
        let org = try await service.organization(id: "o-8")

        // Then
        XCTAssertNil(org.createdAt)
        XCTAssertNil(org.updatedAt)
    }

    // MARK: - update (patch)

    func test_givenPartialPatch_whenUpdating_thenPatchesAndMaps() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.organizationObject(id: "o-7", name: "Renamed"))
        let service = OrgService(api: api)

        // When — only `name` changes.
        let org = try await service.update(id: "o-7", name: "Renamed", description: nil, isPublic: nil)

        // Then
        XCTAssertEqual(org.name, "Renamed")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PATCH")
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o-7")
    }

    func test_givenUpdateFails_whenUpdating_thenThrows() async throws {
        // Given — upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "bad name"))
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.update(id: "o-7", name: "", description: nil, isPublic: nil)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "bad name"))
        }
    }

    func test_givenMalformedUpdateResponse_whenUpdating_thenThrowsDecoding() async throws {
        // Given — invalid input.
        let api = StubAPIClient()
        await api.enqueue(json: #"not json"#)
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.update(id: "o-7", name: "x", description: nil, isPublic: nil)
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("Expected .decoding, got \(error)") }
        }
    }

    func test_givenAllFieldsNil_whenUpdating_thenStillRoundTrips() async throws {
        // Given — boundary: a no-op patch (all fields nil).
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.organizationObject(id: "o-7"))
        let service = OrgService(api: api)

        // When
        let org = try await service.update(id: "o-7", name: nil, description: nil, isPublic: nil)

        // Then
        XCTAssertEqual(org.id, "o-7")
    }

    // MARK: - members (list)

    func test_givenMembers_whenListing_thenMapsRolesAndPagination() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedOrgMembers(
            userIds: ["u-1", "u-2"], role: "admin", limit: 10, offset: 0, hasMore: true
        ))
        let service = OrgService(api: api)

        // When
        let page = try await service.members(of: "o-7", limit: 10, offset: 0)

        // Then — roles narrowed, no membership id on listing rows, pagination surfaced.
        XCTAssertEqual(page.members.map(\.userId), ["u-1", "u-2"])
        XCTAssertEqual(page.members.first?.role, .admin)
        XCTAssertNil(page.members.first?.membershipId)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextOffset, 10)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o-7/members")
    }

    func test_givenMembersFails_whenListing_thenThrows() async throws {
        // Given — upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "not a member"))
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.members(of: "o-7", limit: 10, offset: 0)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "not a member"))
        }
    }

    func test_givenMalformedMembersEnvelope_whenListing_thenThrows() async throws {
        // Given — invalid input. Paginated read → `sendRaw` + `PaginatedDecoder`
        // surfaces a `DecodingError`; assert the malformed envelope throws.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"data":"nope"}"#)
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.members(of: "o-7", limit: 10, offset: 0)
            XCTFail("Expected the malformed envelope to throw")
        } catch {
            // expected — decode failed on the malformed `data` collection.
        }
    }

    func test_givenNoMembers_whenListing_thenReturnsEmptyPage() async throws {
        // Given — boundary: zero-item page.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedOrgMembers(userIds: [], hasMore: false))
        let service = OrgService(api: api)

        // When
        let page = try await service.members(of: "o-7", limit: 10, offset: 0)

        // Then
        XCTAssertTrue(page.members.isEmpty)
        XCTAssertNil(page.nextOffset)
    }

    // MARK: - addMember

    func test_givenUserAndRole_whenAddingMember_thenPostsAndReturnsMembershipId() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.orgMembershipResponse(
            membershipId: "m-1", userId: "u-3", organizationId: "o-7", role: "member"
        ))
        let service = OrgService(api: api)

        // When
        let member = try await service.addMember(to: "o-7", userId: "u-3", role: .member)

        // Then — the membership record id is surfaced.
        XCTAssertEqual(member.userId, "u-3")
        XCTAssertEqual(member.membershipId, "m-1")
        XCTAssertEqual(member.role, .member)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o-7/members")
    }

    func test_givenAddMemberFails_whenAdding_thenThrows() async throws {
        // Given — upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "already a member"))
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.addMember(to: "o-7", userId: "u-3", role: .member)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "already a member"))
        }
    }

    func test_givenMalformedAddResponse_whenAdding_thenThrowsDecoding() async throws {
        // Given — invalid input: missing `membership`.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"message":"ok"}"#)
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.addMember(to: "o-7", userId: "u-3", role: .member)
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("Expected .decoding, got \(error)") }
        }
    }

    func test_givenUnknownRoleEcho_whenAdding_thenPreservesOtherRole() async throws {
        // Given — boundary: server echoes a role the client does not type.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.orgMembershipResponse(
            membershipId: "m-2", userId: "u-4", organizationId: "o-7", role: "billing-admin"
        ))
        let service = OrgService(api: api)

        // When
        let member = try await service.addMember(to: "o-7", userId: "u-4", role: .member)

        // Then — the unrecognised role round-trips under `.other`.
        XCTAssertEqual(member.role, .other("billing-admin"))
    }

    // MARK: - updateMember (PUT role)

    func test_givenNewRole_whenUpdatingMember_thenPutsAndMaps() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.orgMembershipResponse(
            membershipId: "m-1", userId: "u-3", organizationId: "o-7", role: "admin"
        ))
        let service = OrgService(api: api)

        // When
        let member = try await service.updateMember(in: "o-7", userId: "u-3", role: .admin, active: true)

        // Then
        XCTAssertEqual(member.role, .admin)
        XCTAssertEqual(member.active, true)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PUT")
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o-7/members/u-3")
    }

    func test_givenUpdateMemberForbidden_whenUpdating_thenThrows() async throws {
        // Given — upstream API failure (e.g. caller is not an owner).
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "owners only"))
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.updateMember(in: "o-7", userId: "u-3", role: .owner, active: nil)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "owners only"))
        }
    }

    func test_givenMalformedUpdateMemberResponse_whenUpdating_thenThrowsDecoding() async throws {
        // Given — invalid input.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"membership":{"id":"m-1"}}"#)
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.updateMember(in: "o-7", userId: "u-3", role: .admin, active: nil)
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("Expected .decoding, got \(error)") }
        }
    }

    func test_givenNilActive_whenUpdatingMember_thenMapsNilActive() async throws {
        // Given — boundary: server returns null active.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.orgMembershipResponse(
            membershipId: "m-1", userId: "u-3", organizationId: "o-7", role: "member", active: nil
        ))
        let service = OrgService(api: api)

        // When
        let member = try await service.updateMember(in: "o-7", userId: "u-3", role: .member, active: nil)

        // Then
        XCTAssertNil(member.active)
    }

    // MARK: - removeMember (DELETE)

    func test_givenMember_whenRemoving_thenDeletesAtMemberPath() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: #"{}"#)
        let service = OrgService(api: api)

        // When
        try await service.removeMember(from: "o-7", userId: "u-3")

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o-7/members/u-3")
    }

    func test_givenRemoveFails_whenRemoving_thenThrows() async throws {
        // Given — upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "not a member"))
        let service = OrgService(api: api)

        // When / Then
        do {
            try await service.removeMember(from: "o-7", userId: "u-3")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "not a member"))
        }
    }

    func test_givenEmptyUserId_whenRemoving_thenAPIBadRequestPropagates() async throws {
        // Given — invalid input boundary: empty user id → server 400.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "missing user id"))
        let service = OrgService(api: api)

        // When / Then
        do {
            try await service.removeMember(from: "o-7", userId: "")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "missing user id"))
        }
    }

    // MARK: - users (with roles)

    func test_givenUsersWithRoles_whenLoading_thenMapsIdentityAndRole() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.orgUsersArray([
            (id: "u-1", role: "owner"),
            (id: "u-2", role: "member")
        ]))
        let service = OrgService(api: api)

        // When
        let users = try await service.users(of: "o-7")

        // Then
        XCTAssertEqual(users.map(\.id), ["u-1", "u-2"])
        XCTAssertEqual(users.first?.role, .owner)
        XCTAssertEqual(users.first?.summary.username, "ada")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o-7/users")
    }

    func test_givenUsersFails_whenLoading_thenThrows() async throws {
        // Given — upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 503, serverMessage: "down"))
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.users(of: "o-7")
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 503, serverMessage: "down"))
        }
    }

    func test_givenMalformedUsersArray_whenLoading_thenThrowsDecoding() async throws {
        // Given — invalid input: object where an array is expected.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"users":[]}"#)
        let service = OrgService(api: api)

        // When / Then
        do {
            _ = try await service.users(of: "o-7")
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("Expected .decoding, got \(error)") }
        }
    }

    func test_givenEmptyUsersArray_whenLoading_thenReturnsEmpty() async throws {
        // Given — boundary: empty roster.
        let api = StubAPIClient()
        await api.enqueue(json: "[]")
        let service = OrgService(api: api)

        // When
        let users = try await service.users(of: "o-7")

        // Then
        XCTAssertTrue(users.isEmpty)
    }
}
