// OrgMembersViewModelTests
//
// BDD-named tests for the M6 org member roster view model. Covers load
// (happy / empty / failure), pagination (hasMore / nextOffset surfaced +
// zero-item page boundary), and the three optimistic mutations
// (role-change / add / remove) with their required snapshot-rollback
// paths. Also asserts `OrgRole.other` round-trips through a role change
// and that invalid add-input is rejected before any service call.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class OrgMembersViewModelTests: XCTestCase {

    private func makeViewModel(orgId: String = "o1") -> (OrgMembersViewModel, StubOrgService, StubUserService) {
        let orgs = StubOrgService()
        let users = StubUserService()
        let vm = OrgMembersViewModel(orgService: orgs, userService: users, orgId: orgId)
        return (vm, orgs, users)
    }

    private func member(_ id: String, role: OrgRole = .member) -> OrgMember {
        OrgMember(userId: id, membershipId: "m-\(id)", role: role, active: true)
    }

    // MARK: - load + pagination

    func test_givenPopulatedPage_whenLoading_thenRendersAndSurfacesPagination() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(
            members: [member("u1"), member("u2")],
            hasMore: true,
            nextOffset: 2
        ))

        await vm.load(reset: true)

        XCTAssertEqual(vm.members.map(\.userId), ["u1", "u2"])
        XCTAssertTrue(vm.hasMore)
        XCTAssertEqual(vm.nextOffset, 2)
        XCTAssertNil(vm.loadError)
    }

    func test_givenZeroItemPage_whenLoading_thenEmptyAndNoMore() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage.empty)

        await vm.load(reset: true)

        XCTAssertTrue(vm.members.isEmpty)
        XCTAssertFalse(vm.hasMore)
        XCTAssertNil(vm.nextOffset)
    }

    func test_givenSecondPage_whenLoadingMore_thenAppends() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(members: [member("u1")], hasMore: true, nextOffset: 1))
        await orgs.enqueueMembers(success: OrgMembersPage(members: [member("u2")], hasMore: false, nextOffset: nil))

        await vm.load(reset: true)
        await vm.load(reset: false)

        XCTAssertEqual(vm.members.map(\.userId), ["u1", "u2"])
        XCTAssertFalse(vm.hasMore)
    }

    func test_givenMembersEndpointFails_whenLoading_thenSurfacesError() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(failure: TestError.upstream("net"))

        await vm.load(reset: true)

        XCTAssertTrue(vm.members.isEmpty)
        XCTAssertEqual(vm.loadError as? TestError, .upstream("net"))
    }

    // MARK: - changeRole (optimistic)

    func test_givenMember_whenChangingRole_thenUsesServerAuthoritativeRole() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(members: [member("u1", role: .member)], hasMore: false, nextOffset: nil))
        await orgs.enqueueUpdateMember(success: OrgMember(userId: "u1", membershipId: "m-u1", role: .admin, active: true))
        await vm.load(reset: true)

        let error = await vm.changeRole(of: vm.members[0], to: .admin)

        XCTAssertNil(error)
        XCTAssertEqual(vm.members.first?.role, .admin)
        XCTAssertFalse(vm.pendingOperations.contains("u1"))
    }

    func test_givenChangeRoleFails_whenChangingRole_thenRollsBackSnapshot() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(members: [member("u1", role: .member)], hasMore: false, nextOffset: nil))
        await orgs.enqueueUpdateMember(failure: TestError.upstream("boom"))
        await vm.load(reset: true)

        let error = await vm.changeRole(of: vm.members[0], to: .admin)

        XCTAssertEqual(error as? TestError, .upstream("boom"))
        // Rollback: role restored to the pre-mutation snapshot.
        XCTAssertEqual(vm.members.first?.role, .member)
        XCTAssertEqual(vm.actionError as? TestError, .upstream("boom"))
        XCTAssertFalse(vm.pendingOperations.contains("u1"))
    }

    func test_givenSameRole_whenChangingRole_thenNoOpAndNoServiceCall() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(members: [member("u1", role: .admin)], hasMore: false, nextOffset: nil))
        await vm.load(reset: true)

        let error = await vm.changeRole(of: vm.members[0], to: .admin)

        XCTAssertNil(error)
        let recorded = await orgs.recorded
        XCTAssertFalse(recorded.contains { if case .updateMember = $0.kind { return true } else { return false } })
    }

    func test_givenOtherRoleMember_whenChangingToKnownRole_thenServerRolePreserved() async {
        // OrgRole.other round-trips: a member arrives with an unrecognized
        // role and is promoted to admin; the server's return value is used.
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(members: [member("u1", role: .other("guest"))], hasMore: false, nextOffset: nil))
        await orgs.enqueueUpdateMember(success: OrgMember(userId: "u1", membershipId: "m-u1", role: .admin, active: true))
        await vm.load(reset: true)

        XCTAssertEqual(vm.members.first?.role, .other("guest"))
        let error = await vm.changeRole(of: vm.members[0], to: .admin)

        XCTAssertNil(error)
        XCTAssertEqual(vm.members.first?.role, .admin)
    }

    // MARK: - addMember (optimistic)

    func test_givenValidUserId_whenAddingMember_thenAppendsServerMembership() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage.empty)
        await orgs.enqueueAddMember(success: OrgMember(userId: "u9", membershipId: "m-u9", role: .member, active: true))
        await vm.load(reset: true)

        let error = await vm.addMember(userId: "u9", role: .member)

        XCTAssertNil(error)
        XCTAssertEqual(vm.members.map(\.userId), ["u9"])
        XCTAssertEqual(vm.members.first?.membershipId, "m-u9")
    }

    func test_givenBlankUserId_whenAddingMember_thenRejectsBeforeServiceCall() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage.empty)
        await vm.load(reset: true)

        let error = await vm.addMember(userId: "   ", role: .member)

        XCTAssertEqual(error as? OrgMembersError, .emptyUserId)
        let recorded = await orgs.recorded
        XCTAssertFalse(recorded.contains { if case .addMember = $0.kind { return true } else { return false } })
    }

    func test_givenAlreadyMember_whenAddingMember_thenRejectsBeforeServiceCall() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(members: [member("u1")], hasMore: false, nextOffset: nil))
        await vm.load(reset: true)

        let error = await vm.addMember(userId: "u1", role: .admin)

        XCTAssertEqual(error as? OrgMembersError, .alreadyMember)
        let recorded = await orgs.recorded
        XCTAssertFalse(recorded.contains { if case .addMember = $0.kind { return true } else { return false } })
    }

    func test_givenAddFails_whenAddingMember_thenRollsBackProvisionalRow() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage.empty)
        await orgs.enqueueAddMember(failure: TestError.upstream("boom"))
        await vm.load(reset: true)

        let error = await vm.addMember(userId: "u9", role: .member)

        XCTAssertEqual(error as? TestError, .upstream("boom"))
        // Rollback: the provisional row is gone.
        XCTAssertTrue(vm.members.isEmpty)
        XCTAssertEqual(vm.actionError as? TestError, .upstream("boom"))
    }

    // MARK: - removeMember (optimistic)

    func test_givenMember_whenRemoving_thenDropsRow() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(members: [member("u1"), member("u2")], hasMore: false, nextOffset: nil))
        await orgs.enqueueRemoveMemberSuccess()
        await vm.load(reset: true)

        let error = await vm.removeMember(vm.members[0])

        XCTAssertNil(error)
        XCTAssertEqual(vm.members.map(\.userId), ["u2"])
    }

    func test_givenRemoveFails_whenRemoving_thenRollsBackSnapshot() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(members: [member("u1"), member("u2")], hasMore: false, nextOffset: nil))
        await orgs.enqueueRemoveMember(failure: TestError.upstream("boom"))
        await vm.load(reset: true)

        let error = await vm.removeMember(vm.members[0])

        XCTAssertEqual(error as? TestError, .upstream("boom"))
        // Rollback: both members restored.
        XCTAssertEqual(vm.members.map(\.userId), ["u1", "u2"])
        XCTAssertEqual(vm.actionError as? TestError, .upstream("boom"))
    }

    // MARK: - lookupUser (NW-6)

    func test_givenValidHandle_whenLookingUpUser_thenPopulatesFoundUser() async {
        let (vm, orgs, users) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage.empty)
        let found = UserSearchResult(id: "u9", username: "ada", displayName: "Ada Lovelace")
        users.enqueueLookupUser(success: found)
        await vm.load(reset: true)

        await vm.lookupUser(handle: "ada")

        XCTAssertEqual(vm.foundUser?.id, "u9")
        XCTAssertNil(vm.actionError)
    }

    func test_givenUnknownHandle_whenLookingUpUser_thenSetsNotFoundError() async {
        let (vm, orgs, users) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage.empty)
        users.enqueueLookupUser(success: nil)
        await vm.load(reset: true)

        await vm.lookupUser(handle: "ghost")

        XCTAssertNil(vm.foundUser)
        XCTAssertEqual(vm.actionError as? OrgMembersError, .handleNotFound("ghost"))
    }

    func test_givenAPIFailure_whenLookingUpUser_thenSurfacesError() async {
        let (vm, orgs, users) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage.empty)
        users.enqueueLookupUser(failure: TestError.upstream("net"))
        await vm.load(reset: true)

        await vm.lookupUser(handle: "ada")

        XCTAssertNil(vm.foundUser)
        XCTAssertEqual(vm.actionError as? TestError, .upstream("net"))
    }

    func test_givenEmptyHandle_whenLookingUpUser_thenRejectsBeforeServiceCall() async {
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage.empty)
        await vm.load(reset: true)

        await vm.lookupUser(handle: "  ")

        XCTAssertNil(vm.foundUser)
        XCTAssertEqual(vm.actionError as? OrgMembersError, .emptyHandle)
    }

    // MARK: - Suspend / restore (work-consolidation.md G25)

    func test_givenActiveMember_whenSuspending_thenOptimisticallyMarksSuspended() async {
        // Happy path: the row flips, the service is called, and the server's
        // authoritative membership replaces the optimistic copy.
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(
            members: [member("u1", role: .owner), member("u2")],
            hasMore: false,
            nextOffset: nil
        ))
        await vm.load(reset: true)
        await orgs.enqueueSetSuspended(success: OrgMember(
            userId: "u2", membershipId: "m-u2", role: .member, active: false
        ))

        let error = await vm.setSuspended(vm.members[1], suspended: true)

        XCTAssertNil(error)
        XCTAssertTrue(vm.members[1].isSuspended)
        let recorded = await orgs.recorded
        XCTAssertTrue(recorded.contains { $0.kind == .setMemberSuspended(orgId: "o1", userId: "u2", suspended: true) })
    }

    func test_givenSuspendedMember_whenRestoring_thenMarksActiveAgain() async {
        // Happy path in reverse — restoring is never gated.
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(
            members: [OrgMember(userId: "u2", role: .member, active: false)],
            hasMore: false,
            nextOffset: nil
        ))
        await vm.load(reset: true)
        await orgs.enqueueSetSuspended(success: OrgMember(userId: "u2", role: .member, active: true))

        let error = await vm.setSuspended(vm.members[0], suspended: false)

        XCTAssertNil(error)
        XCTAssertFalse(vm.members[0].isSuspended)
    }

    func test_givenLastOwner_whenSuspending_thenRejectedBeforeAnyServiceCall() async {
        // Invalid input: suspending the only owner strands the org.
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(
            members: [member("u1", role: .owner), member("u2")],
            hasMore: false,
            nextOffset: nil
        ))
        await vm.load(reset: true)
        let callsBefore = await orgs.recorded.count

        let error = await vm.setSuspended(vm.members[0], suspended: true)

        XCTAssertEqual(error as? OrgLifecycleError, .lastOwnerCannotBeSuspended)
        XCTAssertFalse(vm.members[0].isSuspended, "The row must not flip on a rejected suspend")
        let callsAfter = await orgs.recorded.count
        XCTAssertEqual(callsAfter, callsBefore, "A rejected suspend must not hit the service")
    }

    func test_givenSuspendFails_whenSuspending_thenRollsBackAndSurfacesError() async {
        // Upstream API failure: the optimistic flip is reverted.
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(
            members: [member("u1", role: .owner), member("u2")],
            hasMore: false,
            nextOffset: nil
        ))
        await vm.load(reset: true)
        await orgs.enqueueSetSuspended(failure: URLError(.badServerResponse))

        let error = await vm.setSuspended(vm.members[1], suspended: true)

        XCTAssertNotNil(error)
        XCTAssertFalse(vm.members[1].isSuspended, "Optimistic state rolled back")
        XCTAssertNotNil(vm.actionError)
    }

    func test_givenMemberAlreadyInTargetState_whenSuspending_thenNoOp() async {
        // Boundary: a redundant suspend is a no-op, not a wasted round-trip.
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(
            members: [OrgMember(userId: "u2", role: .member, active: false)],
            hasMore: false,
            nextOffset: nil
        ))
        await vm.load(reset: true)
        let callsBefore = await orgs.recorded.count

        let error = await vm.setSuspended(vm.members[0], suspended: true)

        XCTAssertNil(error)
        let callsAfter = await orgs.recorded.count
        XCTAssertEqual(callsAfter, callsBefore)
    }

    // MARK: - Last-owner protection on the existing mutations

    func test_givenLastOwner_whenDemoting_thenRejectedBeforeAnyServiceCall() async {
        // Invalid input: "The last remaining owner cannot be demoted."
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(
            members: [member("u1", role: .owner), member("u2")],
            hasMore: false,
            nextOffset: nil
        ))
        await vm.load(reset: true)
        let callsBefore = await orgs.recorded.count

        let error = await vm.changeRole(of: vm.members[0], to: .member)

        XCTAssertEqual(error as? OrgLifecycleError, .lastOwnerCannotBeDemoted)
        XCTAssertEqual(vm.members[0].role, .owner, "The row keeps the owner role")
        let callsAfter = await orgs.recorded.count
        XCTAssertEqual(callsAfter, callsBefore)
    }

    func test_givenLastOwner_whenRemoving_thenRejectedBeforeAnyServiceCall() async {
        // Invalid input: "…cannot be demoted or removed."
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(
            members: [member("u1", role: .owner), member("u2")],
            hasMore: false,
            nextOffset: nil
        ))
        await vm.load(reset: true)
        let callsBefore = await orgs.recorded.count

        let error = await vm.removeMember(vm.members[0])

        XCTAssertEqual(error as? OrgLifecycleError, .lastOwnerCannotBeDemoted)
        XCTAssertEqual(vm.members.count, 2, "The row must not disappear on a rejected remove")
        let callsAfter = await orgs.recorded.count
        XCTAssertEqual(callsAfter, callsBefore)
    }

    func test_givenTwoOwners_whenDemotingOne_thenAllowed() async {
        // Boundary: the rule releases as soon as a second owner exists.
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(
            members: [member("u1", role: .owner), member("u2", role: .owner)],
            hasMore: false,
            nextOffset: nil
        ))
        await vm.load(reset: true)
        await orgs.enqueueUpdateMember(success: OrgMember(userId: "u1", role: .member, active: true))

        let error = await vm.changeRole(of: vm.members[0], to: .member)

        XCTAssertNil(error)
        XCTAssertEqual(vm.members[0].role, .member)
    }

    func test_givenSingleOwnerRoster_whenAskingWhatIsAllowed_thenGatesMatchTheRules() async {
        // The UI reads these to enable/disable controls; they must agree with
        // what the mutations actually enforce.
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(
            members: [member("u1", role: .owner), member("u2")],
            hasMore: false,
            nextOffset: nil
        ))
        await vm.load(reset: true)

        XCTAssertFalse(vm.canSuspend(vm.members[0]))
        XCTAssertFalse(vm.canRemove(vm.members[0]))
        XCTAssertFalse(vm.canChangeRole(of: vm.members[0], to: .member))
        XCTAssertTrue(vm.canSuspend(vm.members[1]))
        XCTAssertTrue(vm.canRemove(vm.members[1]))
        XCTAssertTrue(vm.canChangeRole(of: vm.members[1], to: .admin))
    }

    // MARK: - Identity survives a mutation

    func test_givenNamedMember_whenChangingRole_thenIdentityIsNotBlanked() async {
        // The membership envelope the server returns on a role change carries
        // no username or avatar. Adopting it wholesale would blank the row, so
        // the view model keeps the identity it already had.
        let (vm, orgs, _) = makeViewModel()
        await orgs.enqueueMembers(success: OrgMembersPage(
            members: [
                member("u1", role: .owner),
                OrgMember(
                    userId: "u2",
                    role: .member,
                    active: true,
                    username: "hubcity",
                    displayName: "HubCity",
                    avatarURL: URL(string: "https://cdn/h.jpg")
                )
            ],
            hasMore: false,
            nextOffset: nil
        ))
        await vm.load(reset: true)
        // The server's answer — identity-free, exactly as the real envelope is.
        await orgs.enqueueUpdateMember(success: OrgMember(userId: "u2", role: .admin, active: true))

        await vm.changeRole(of: vm.members[1], to: .admin)

        XCTAssertEqual(vm.members[1].role, .admin, "Server role is adopted")
        XCTAssertEqual(vm.members[1].displayName, "HubCity", "Identity is preserved")
        XCTAssertEqual(vm.members[1].username, "hubcity")
        XCTAssertEqual(vm.members[1].displayLabel, "HubCity")
    }
}

