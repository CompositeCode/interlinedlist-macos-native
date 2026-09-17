import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for the organization **lifecycle** verbs added in
/// work-consolidation.md G25: delete, leave, and suspend/restore a member —
/// plus the client-side preconditions (`OrgOwnershipRules`) that make the
/// last-owner and system-org rules produce a specific message instead of a
/// bare server rejection.
///
/// The rules under test come from `/help/organizations`:
/// - "The last remaining owner cannot be demoted or removed."
/// - "You cannot leave the system 'The Public' organization."
/// - "Only an owner can delete an organization."
final class OrgLifecycleServiceTests: XCTestCase {

    // MARK: - Fixtures

    private func org(
        id: String = "o1",
        name: String = "Bikey Life",
        isSystem: Bool = false
    ) -> Organization {
        Organization(id: id, name: name, isPublic: true, isSystem: isSystem)
    }

    private func member(
        _ id: String,
        _ role: OrgRole,
        active: Bool? = true,
        displayName: String? = nil
    ) -> OrgMember {
        OrgMember(userId: id, role: role, active: active, displayName: displayName)
    }

    private var publicOrg: Organization {
        org(id: "00000000-0000-0000-0000-000000000001", name: "The Public", isSystem: true)
    }

    // MARK: - delete

    func test_givenOwner_whenDeletingOrg_thenSendsDeleteToTheOrgPath() async throws {
        // Happy path.
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = OrgService(api: api)

        try await service.delete(id: "o1", callerRole: .owner)

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o1")
    }

    func test_givenAdmin_whenDeletingOrg_thenRejectsBeforeAnyServiceCall() async throws {
        // Invalid input: delete is owner-only. Assert no request was made —
        // the point of the precondition is to not ask the server at all.
        let api = StubAPIClient()
        let service = OrgService(api: api)

        do {
            try await service.delete(id: "o1", callerRole: .admin)
            XCTFail("Expected onlyOwnerCanDelete")
        } catch let error as OrgLifecycleError {
            XCTAssertEqual(error, .onlyOwnerCanDelete)
        }

        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "A rejected delete must not hit the network")
    }

    func test_givenUnknownRole_whenDeletingOrg_thenRejects() async throws {
        // Boundary: an unknown caller role is not an owner.
        let api = StubAPIClient()
        let service = OrgService(api: api)

        do {
            try await service.delete(id: "o1", callerRole: nil)
            XCTFail("Expected onlyOwnerCanDelete")
        } catch let error as OrgLifecycleError {
            XCTAssertEqual(error, .onlyOwnerCanDelete)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenServerFailure_whenDeletingOrg_thenSurfacesAPIError() async throws {
        // Upstream API failure: the typed APIError reaches the caller intact.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = OrgService(api: api)

        do {
            try await service.delete(id: "o1", callerRole: .owner)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - leave

    func test_givenOrdinaryOrg_whenLeaving_thenDeletesOwnMembership() async throws {
        // Happy path. There is no /leave route — leaving is removing yourself,
        // which is exactly what the web client does.
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = OrgService(api: api)

        try await service.leave(
            organization: org(),
            userId: "u1",
            members: [member("u1", .member), member("u2", .owner)]
        )

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o1/members/u1")
    }

    func test_givenSystemOrg_whenLeaving_thenRejectsBeforeAnyServiceCall() async throws {
        // Invalid input: nobody leaves "The Public".
        let api = StubAPIClient()
        let service = OrgService(api: api)

        do {
            try await service.leave(
                organization: publicOrg,
                userId: "u1",
                members: [member("u1", .member)]
            )
            XCTFail("Expected cannotLeaveSystemOrganization")
        } catch let error as OrgLifecycleError {
            XCTAssertEqual(error, .cannotLeaveSystemOrganization(name: "The Public"))
        }

        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "Leaving the system org must not hit the network")
    }

    func test_givenLastOwner_whenLeaving_thenRejectsBeforeAnyServiceCall() async throws {
        // Invalid input: the last owner cannot leave until another owner exists.
        let api = StubAPIClient()
        let service = OrgService(api: api)

        do {
            try await service.leave(
                organization: org(),
                userId: "u1",
                members: [member("u1", .owner), member("u2", .member)]
            )
            XCTFail("Expected lastOwnerCannotLeave")
        } catch let error as OrgLifecycleError {
            XCTAssertEqual(error, .lastOwnerCannotLeave)
        }

        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenSecondOwnerExists_whenOwnerLeaves_thenAllowed() async throws {
        // Boundary: exactly two owners — the rule releases at the second one.
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = OrgService(api: api)

        try await service.leave(
            organization: org(),
            userId: "u1",
            members: [member("u1", .owner), member("u2", .owner)]
        )

        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    func test_givenUnloadedRoster_whenLeaving_thenDefersToTheServer() async throws {
        // Boundary: an empty roster means "unknown", not "no owners". The
        // precondition must not block on data the client does not have.
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = OrgService(api: api)

        try await service.leave(organization: org(), userId: "u1", members: [])

        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1, "An unknown roster lets the server decide")
    }

    func test_givenBlankUserId_whenLeaving_thenRejectsBeforeAnyServiceCall() async throws {
        // Invalid input: no signed-in user id to remove.
        let api = StubAPIClient()
        let service = OrgService(api: api)

        do {
            try await service.leave(organization: org(), userId: "", members: [])
            XCTFail("Expected unknownCurrentUser")
        } catch let error as OrgLifecycleError {
            XCTAssertEqual(error, .unknownCurrentUser)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenServerFailure_whenLeaving_thenSurfacesAPIError() async throws {
        // Upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = OrgService(api: api)

        do {
            try await service.leave(organization: org(), userId: "u1", members: [])
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - suspend / restore

    func test_givenActiveMember_whenSuspending_thenSendsActiveFalseWithExistingRole() async throws {
        // Happy path. The update body requires a role; re-sending the member's
        // current role is what keeps a suspend from changing it by omission.
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"message":"ok","membership":{"id":"m1","userId":"u2","organizationId":"o1",
                                      "role":"admin","active":false}}
        """#)
        let service = OrgService(api: api)
        let target = member("u2", .admin, displayName: "Bea")

        let updated = try await service.setMemberSuspended(
            in: "o1",
            member: target,
            suspended: true,
            members: [member("u1", .owner), target]
        )

        XCTAssertTrue(updated.isSuspended)
        XCTAssertEqual(updated.role, .admin)
        XCTAssertEqual(updated.displayName, "Bea", "Identity survives the membership envelope")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PUT")
        XCTAssertEqual(recorded.first?.path, "/api/organizations/o1/members/u2")
    }

    func test_givenSuspendedMember_whenRestoring_thenSendsActiveTrue() async throws {
        // Happy path in the other direction; restoring is never blocked.
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"message":"ok","membership":{"id":"m1","userId":"u1","organizationId":"o1",
                                      "role":"owner","active":true}}
        """#)
        let service = OrgService(api: api)
        let onlyOwner = member("u1", .owner, active: false)

        let updated = try await service.setMemberSuspended(
            in: "o1",
            member: onlyOwner,
            suspended: false,
            members: [onlyOwner]
        )

        XCTAssertFalse(updated.isSuspended)
    }

    func test_givenLastOwner_whenSuspending_thenRejectsBeforeAnyServiceCall() async throws {
        // Invalid input: suspending the only owner strands the org.
        let api = StubAPIClient()
        let service = OrgService(api: api)
        let onlyOwner = member("u1", .owner)

        do {
            _ = try await service.setMemberSuspended(
                in: "o1",
                member: onlyOwner,
                suspended: true,
                members: [onlyOwner, member("u2", .member)]
            )
            XCTFail("Expected lastOwnerCannotBeSuspended")
        } catch let error as OrgLifecycleError {
            XCTAssertEqual(error, .lastOwnerCannotBeSuspended)
        }

        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenServerFailure_whenSuspending_thenSurfacesAPIError() async throws {
        // Upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = OrgService(api: api)

        do {
            _ = try await service.setMemberSuspended(
                in: "o1",
                member: member("u2", .member),
                suspended: true,
                members: [member("u1", .owner), member("u2", .member)]
            )
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - OrgOwnershipRules (the pure predicates)

    func test_givenOneOwnerAndOneMember_whenCheckingRules_thenOnlyTheOwnerIsProtected() {
        // Boundary case the issue calls out explicitly: exactly one owner,
        // one member.
        let owner = member("u1", .owner)
        let plain = member("u2", .member)
        let roster = [owner, plain]

        XCTAssertEqual(OrgOwnershipRules.ownerCount(in: roster), 1)
        XCTAssertTrue(OrgOwnershipRules.isLastOwner(userId: "u1", in: roster))
        XCTAssertFalse(OrgOwnershipRules.isLastOwner(userId: "u2", in: roster))

        XCTAssertEqual(
            OrgOwnershipRules.validateRoleChange(member: owner, to: .member, members: roster),
            .lastOwnerCannotBeDemoted
        )
        XCTAssertEqual(
            OrgOwnershipRules.validateRemoval(member: owner, members: roster),
            .lastOwnerCannotBeDemoted
        )
        XCTAssertNil(OrgOwnershipRules.validateRemoval(member: plain, members: roster))
    }

    func test_givenLastOwner_whenPromotingThem_thenAllowed() {
        // A no-op / promotion is never a demotion.
        let owner = member("u1", .owner)
        XCTAssertNil(
            OrgOwnershipRules.validateRoleChange(member: owner, to: .owner, members: [owner])
        )
    }

    func test_givenRosterWithNoOwner_whenCheckingLastOwner_thenDoesNotBlock() {
        // Boundary: a partial roster (no owner on this page) must not be read
        // as "there are no owners".
        let roster = [member("u2", .member), member("u3", .admin)]
        XCTAssertFalse(OrgOwnershipRules.isLastOwner(userId: "u2", in: roster))
        XCTAssertNil(OrgOwnershipRules.validateRemoval(member: roster[0], members: roster))
    }

    func test_givenSuspendedLastOwner_whenCountingOwners_thenStillCounts() {
        // A suspended owner still holds the role, so they still protect the
        // org from being left ownerless.
        let roster = [member("u1", .owner, active: false), member("u2", .member)]
        XCTAssertEqual(OrgOwnershipRules.ownerCount(in: roster), 1)
        XCTAssertTrue(OrgOwnershipRules.isLastOwner(userId: "u1", in: roster))
    }

    func test_givenEveryLifecycleError_whenDescribed_thenHasAUserFacingSentence() {
        // Boundary: no error may reach the UI without a message, since these
        // exist purely to be shown to the user.
        let errors: [OrgLifecycleError] = [
            .cannotLeaveSystemOrganization(name: "The Public"),
            .lastOwnerCannotLeave,
            .lastOwnerCannotBeDemoted,
            .lastOwnerCannotBeSuspended,
            .onlyOwnerCanDelete,
            .unknownCurrentUser,
            .linkedInRequiresOwnerOrAdmin
        ]
        for error in errors {
            XCTAssertFalse(
                (error.errorDescription ?? "").isEmpty,
                "\(error) has no user-facing description"
            )
        }
    }
}
