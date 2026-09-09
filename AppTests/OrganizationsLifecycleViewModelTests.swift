// OrganizationsLifecycleViewModelTests
//
// BDD-named tests for the My Organizations lifecycle intents added in
// work-consolidation.md G25: join, leave, and delete, plus the client-side
// rules that decide whether those controls render at all.
//
// The two rules under test come from `/help/organizations`:
// - "You cannot leave the system 'The Public' organization."
// - Deleting an organization is owner-only.
//
// Each optimistic mutation is checked for its rollback path, and each
// precondition is checked for *not calling the service at all* — the whole
// point of enforcing them client-side is to answer immediately.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class OrganizationsLifecycleViewModelTests: XCTestCase {

    private func makeViewModel(
        currentUserId: String? = "me"
    ) -> (OrganizationsListViewModel, StubOrgService, StubUserService) {
        let orgs = StubOrgService()
        let users = StubUserService()
        let vm = OrganizationsListViewModel(
            orgService: orgs,
            userService: users,
            currentUserId: currentUserId
        )
        return (vm, orgs, users)
    }

    private func membership(
        id: String = "o1",
        name: String = "Bikey Life",
        role: OrgRole = .member,
        isSystem: Bool = false,
        memberCount: Int? = 3
    ) -> UserOrganization {
        UserOrganization(
            organization: Organization(
                id: id,
                name: name,
                isPublic: true,
                isSystem: isSystem,
                memberCount: memberCount
            ),
            role: role,
            joinedAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    private var publicMembership: UserOrganization {
        membership(
            id: "00000000-0000-0000-0000-000000000001",
            name: "The Public",
            isSystem: true,
            memberCount: 22
        )
    }

    private func load(_ vm: OrganizationsListViewModel, _ users: StubUserService, _ memberships: [UserOrganization]) async {
        await users.enqueueOrganizations(success: memberships)
        await vm.load()
    }

    // MARK: - leave

    func test_givenOrdinaryOrg_whenLeaving_thenRowDisappearsAndServiceCalled() async {
        // Happy path.
        let (vm, orgs, users) = makeViewModel()
        await load(vm, users, [membership(), membership(id: "o2", name: "Coding")])
        await orgs.enqueueLeaveSuccess()

        let error = await vm.leave(vm.memberships[0])

        XCTAssertNil(error)
        XCTAssertEqual(vm.memberships.map(\.organization.id), ["o2"])
        let recorded = await orgs.recorded
        XCTAssertTrue(recorded.contains { $0.kind == .leave(orgId: "o1", userId: "me") })
    }

    func test_givenSystemOrg_whenLeaving_thenRejectedBeforeAnyServiceCall() async {
        // Invalid input: nobody leaves "The Public".
        let (vm, orgs, users) = makeViewModel()
        await load(vm, users, [publicMembership])

        let error = await vm.leave(vm.memberships[0])

        XCTAssertEqual(
            error as? OrgLifecycleError,
            .cannotLeaveSystemOrganization(name: "The Public")
        )
        XCTAssertEqual(vm.memberships.count, 1, "The row stays")
        let recorded = await orgs.recorded
        XCTAssertFalse(recorded.contains { if case .leave = $0.kind { return true } else { return false } })
    }

    func test_givenNoSignedInUser_whenLeaving_thenRejectedBeforeAnyServiceCall() async {
        // Invalid input: leaving needs to know which membership to remove.
        let (vm, orgs, users) = makeViewModel(currentUserId: nil)
        await load(vm, users, [membership()])

        let error = await vm.leave(vm.memberships[0])

        XCTAssertEqual(error as? OrgLifecycleError, .unknownCurrentUser)
        let recorded = await orgs.recorded
        XCTAssertFalse(recorded.contains { if case .leave = $0.kind { return true } else { return false } })
    }

    func test_givenLeaveFails_whenLeaving_thenRestoresTheRowAndSurfacesError() async {
        // Upstream API failure: the optimistic removal is rolled back. This is
        // also how the server-side last-owner rejection reaches the user, since
        // this surface does not hold the roster.
        let (vm, orgs, users) = makeViewModel()
        await load(vm, users, [membership(), membership(id: "o2", name: "Coding")])
        await orgs.enqueueLeave(failure: URLError(.badServerResponse))

        let error = await vm.leave(vm.memberships[0])

        XCTAssertNotNil(error)
        XCTAssertEqual(vm.memberships.map(\.organization.id), ["o1", "o2"], "Row restored")
        XCTAssertNotNil(vm.actionError)
    }

    func test_givenOnlyMembership_whenLeaving_thenListGoesEmpty() async {
        // Boundary: leaving the last org empties the list rather than leaving
        // a stale row behind.
        let (vm, orgs, users) = makeViewModel()
        await load(vm, users, [membership()])
        await orgs.enqueueLeaveSuccess()

        await vm.leave(vm.memberships[0])

        XCTAssertTrue(vm.memberships.isEmpty)
    }

    // MARK: - delete

    func test_givenOwnedOrg_whenDeleting_thenRowDisappearsAndServiceCalled() async {
        // Happy path.
        let (vm, orgs, users) = makeViewModel()
        await load(vm, users, [membership(role: .owner), membership(id: "o2", name: "Coding")])
        await orgs.enqueueDeleteSuccess()

        let error = await vm.delete(vm.memberships[0])

        XCTAssertNil(error)
        XCTAssertEqual(vm.memberships.map(\.organization.id), ["o2"])
        let recorded = await orgs.recorded
        XCTAssertTrue(recorded.contains { $0.kind == .delete(orgId: "o1", callerRole: "owner") })
    }

    func test_givenNonOwnedOrg_whenDeleting_thenRejectedAndRowRestored() async {
        // Invalid input: delete is owner-only. The stub applies the same
        // precondition the real service does.
        let (vm, orgs, users) = makeViewModel()
        await load(vm, users, [membership(role: .admin)])

        let error = await vm.delete(vm.memberships[0])

        XCTAssertEqual(error as? OrgLifecycleError, .onlyOwnerCanDelete)
        XCTAssertEqual(vm.memberships.count, 1, "Row restored after the rejection")
        XCTAssertNotNil(vm.actionError)
        _ = orgs
    }

    func test_givenDeleteFails_whenDeleting_thenRestoresTheRowAndSurfacesError() async {
        // Upstream API failure.
        let (vm, orgs, users) = makeViewModel()
        await load(vm, users, [membership(role: .owner)])
        await orgs.enqueueDelete(failure: URLError(.badServerResponse))

        let error = await vm.delete(vm.memberships[0])

        XCTAssertNotNil(error)
        XCTAssertEqual(vm.memberships.count, 1, "Row restored")
    }

    func test_givenAnyRoster_whenAskingWhichControlsRender_thenMatchesTheRules() async {
        // Boundary: ownership-gated controls are hidden, not disabled, and the
        // system org never offers Leave.
        let (vm, _, users) = makeViewModel()
        await load(vm, users, [
            membership(role: .owner),
            membership(id: "o2", name: "Coding", role: .member),
            publicMembership
        ])

        XCTAssertTrue(vm.canDelete(vm.memberships[0]))
        XCTAssertFalse(vm.canDelete(vm.memberships[1]))
        XCTAssertTrue(vm.canLeave(vm.memberships[0]))
        XCTAssertTrue(vm.canLeave(vm.memberships[1]))
        XCTAssertFalse(vm.canLeave(vm.memberships[2]), "The Public can never be left")
    }

    func test_givenNoSession_whenAskingWhetherLeaveRenders_thenHidesIt() async {
        // Boundary: with no resolved session there is nothing to leave *as*.
        let (vm, _, users) = makeViewModel(currentUserId: nil)
        await load(vm, users, [membership()])

        XCTAssertFalse(vm.canLeave(vm.memberships[0]))
    }

    // MARK: - join

    func test_givenPublicOrg_whenJoining_thenAdoptsTheServersMembershipList() async {
        // Happy path: the row comes from the server's re-read, not a guess.
        let (vm, _, users) = makeViewModel()
        await load(vm, users, [])
        await users.enqueueJoinOrganization(success: [membership(id: "o9", name: "Metals")])

        let error = await vm.join(organizationId: "o9")

        XCTAssertNil(error)
        XCTAssertEqual(vm.memberships.map(\.organization.id), ["o9"])
    }

    func test_givenBlankOrgId_whenJoining_thenRejectedBeforeAnyServiceCall() async {
        // Invalid input.
        let (vm, _, users) = makeViewModel()

        let error = await vm.join(organizationId: "   ")

        XCTAssertEqual(error as? OrganizationsListError, .emptyOrganizationId)
        let recorded = await users.recorded
        XCTAssertFalse(recorded.contains { if case .joinOrganization = $0.kind { return true } else { return false } })
    }

    func test_givenJoinFails_whenJoining_thenKeepsTheListAndSurfacesError() async {
        // Upstream API failure: a failed join must not disturb the list.
        let (vm, _, users) = makeViewModel()
        await load(vm, users, [membership()])
        await users.enqueueJoinOrganization(failure: URLError(.badServerResponse))

        let error = await vm.join(organizationId: "o9")

        XCTAssertNotNil(error)
        XCTAssertEqual(vm.memberships.map(\.organization.id), ["o1"])
        XCTAssertNotNil(vm.actionError)
    }

    func test_givenAlreadyJoinedOrgs_whenBrowsing_thenExcludesThem() async {
        // Boundary: the browse list must never offer a Join that would fail.
        let (vm, orgs, users) = makeViewModel()
        await load(vm, users, [membership(id: "o1", name: "Bikey Life")])
        await orgs.enqueueOrganizations(success: OrgsPage(
            organizations: [
                Organization(id: "o1", name: "Bikey Life", isPublic: true),
                Organization(id: "o2", name: "Metals", isPublic: true)
            ],
            hasMore: false,
            nextOffset: nil
        ))

        await vm.browse()

        XCTAssertEqual(vm.browsableOrganizations.map(\.id), ["o2"])
    }

    func test_givenBrowseFails_whenBrowsing_thenSurfacesErrorWithEmptyList() async {
        // Upstream API failure on the browse read.
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueOrganizations(failure: URLError(.badServerResponse))

        await vm.browse()

        XCTAssertNotNil(vm.browseError)
        XCTAssertTrue(vm.browsableOrganizations.isEmpty)
    }

    func test_givenJoinSucceeds_whenBrowsing_thenTheJoinedRowLeavesTheBrowseList() async {
        // Boundary: the browse sheet stays consistent after a join.
        let (vm, orgs, users) = makeViewModel()
        await load(vm, users, [])
        await orgs.enqueueOrganizations(success: OrgsPage(
            organizations: [Organization(id: "o2", name: "Metals", isPublic: true)],
            hasMore: false,
            nextOffset: nil
        ))
        await vm.browse()
        await users.enqueueJoinOrganization(success: [membership(id: "o2", name: "Metals")])

        await vm.join(organizationId: "o2")

        XCTAssertTrue(vm.browsableOrganizations.isEmpty)
        XCTAssertEqual(vm.memberships.map(\.organization.id), ["o2"])
    }
}
