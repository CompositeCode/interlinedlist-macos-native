// OrgLinkedInViewModelTests
//
// BDD-named tests for the organization LinkedIn section (work-consolidation.md
// G25): credential status, page sync, per-member page assignment, disconnect.
//
// The upstream-failure case the issue calls out explicitly gets its own test:
// when `sync-pages` fails, the previously-loaded page list must stay on screen
// so the assignment UI remains usable, with the error surfaced separately.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class OrgLinkedInViewModelTests: XCTestCase {

    private func makeViewModel(
        role: OrgRole = .owner,
        orgId: String = "o1"
    ) -> (OrgLinkedInViewModel, StubOrgService) {
        let orgs = StubOrgService()
        let vm = OrgLinkedInViewModel(orgService: orgs, orgId: orgId, membershipRole: role)
        return (vm, orgs)
    }

    private func page(_ id: String, _ name: String) -> OrgLinkedInPage {
        OrgLinkedInPage(id: id, name: name)
    }

    private func connected(
        pages: [OrgLinkedInPage] = [],
        assignments: [OrgLinkedInAssignment] = [],
        role: OrgRole = .owner
    ) -> OrgLinkedInStatus {
        OrgLinkedInStatus(
            isConnected: true,
            callerRole: role,
            pages: pages,
            assignments: assignments
        )
    }

    // MARK: - load

    func test_givenConnectedOrg_whenLoading_thenRendersPagesAndAssignments() async {
        // Happy path.
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueLinkedInStatus(success: connected(
            pages: [page("p1", "Acme Corp")],
            assignments: [OrgLinkedInAssignment(userId: "u2", pageId: "p1")]
        ))

        await vm.load()

        XCTAssertTrue(vm.isConnected)
        XCTAssertEqual(vm.pages.map(\.name), ["Acme Corp"])
        XCTAssertEqual(vm.assignedPage(for: "u2")?.name, "Acme Corp")
        XCTAssertNil(vm.assignedPage(for: "u3"))
        XCTAssertTrue(vm.canManage)
    }

    func test_givenDisconnectedOrg_whenLoading_thenReportsNotConnected() async {
        // Boundary: the live shape on a tenant with no org credential.
        let (vm, orgs) = makeViewModel(role: .member)
        await orgs.enqueueLinkedInStatus(success: OrgLinkedInStatus(
            isConnected: false,
            callerRole: .member
        ))

        await vm.load()

        XCTAssertFalse(vm.isConnected)
        XCTAssertTrue(vm.pages.isEmpty)
        XCTAssertFalse(vm.canManage, "A plain member gets no management controls")
    }

    func test_givenStatusFails_whenLoading_thenSurfacesLoadError() async {
        // Upstream API failure.
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueLinkedInStatus(failure: URLError(.badServerResponse))

        await vm.load()

        XCTAssertNotNil(vm.loadError)
        XCTAssertNil(vm.status)
    }

    func test_givenMemberRole_whenNotYetLoaded_thenGatesFromMembershipRole() async {
        // Boundary: before the status read lands, the membership role decides,
        // so the section does not flash controls a member can't use.
        let (memberVM, _) = makeViewModel(role: .member)
        let (adminVM, _) = makeViewModel(role: .admin)
        let (unknownVM, _) = makeViewModel(role: .other("guest"))

        XCTAssertFalse(memberVM.canManage)
        XCTAssertTrue(adminVM.canManage)
        XCTAssertFalse(unknownVM.canManage)
    }

    // MARK: - sync pages

    func test_givenOwner_whenSyncingPages_thenReplacesThePageList() async {
        // Happy path.
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueLinkedInStatus(success: connected(pages: [page("p1", "Acme Corp")]))
        await vm.load()
        await orgs.enqueueSyncPages(success: connected(
            pages: [page("p1", "Acme Corp"), page("p2", "Acme Labs")]
        ))

        let error = await vm.syncPages()

        XCTAssertNil(error)
        XCTAssertEqual(vm.pages.map(\.name), ["Acme Corp", "Acme Labs"])
        XCTAssertFalse(vm.syncFailedWithStalePages)
    }

    func test_givenSyncFails_whenSyncingPages_thenKeepsStalePagesUsable() async {
        // Upstream API failure — the case the issue names: "sync-pages fails →
        // assignments UI stays usable with the stale page list, error surfaced."
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueLinkedInStatus(success: connected(pages: [page("p1", "Acme Corp")]))
        await vm.load()
        await orgs.enqueueSyncPages(failure: URLError(.badServerResponse))

        let error = await vm.syncPages()

        XCTAssertNotNil(error)
        XCTAssertEqual(vm.pages.map(\.name), ["Acme Corp"], "Stale pages stay on screen")
        XCTAssertTrue(vm.syncFailedWithStalePages)
        XCTAssertNotNil(vm.actionError)
    }

    func test_givenSyncFailsWithNoPagesYet_whenSyncing_thenDoesNotClaimStalePages() async {
        // Boundary: nothing to keep, so the "showing stale pages" hint must
        // not appear.
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueLinkedInStatus(success: connected(pages: []))
        await vm.load()
        await orgs.enqueueSyncPages(failure: URLError(.badServerResponse))

        await vm.syncPages()

        XCTAssertFalse(vm.syncFailedWithStalePages)
        XCTAssertTrue(vm.pages.isEmpty)
    }

    func test_givenMember_whenSyncingPages_thenRejectedByTheRoleGate() async {
        // Invalid input: sync is owner/admin only.
        let (vm, orgs) = makeViewModel(role: .member)
        await orgs.enqueueLinkedInStatus(success: OrgLinkedInStatus(isConnected: true, callerRole: .member))
        await vm.load()

        let error = await vm.syncPages()

        XCTAssertEqual(error as? OrgLifecycleError, .linkedInRequiresOwnerOrAdmin)
    }

    // MARK: - assign

    func test_givenOwner_whenAssigningPage_thenRereadsStatusForTheNewAssignment() async {
        // Happy path. There is no read route for assignments, so the view model
        // re-reads status rather than trusting a local mutation.
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueLinkedInStatus(success: connected(pages: [page("p1", "Acme Corp")]))
        await vm.load()
        await orgs.enqueueAssignPageSuccess()
        await orgs.enqueueLinkedInStatus(success: connected(
            pages: [page("p1", "Acme Corp")],
            assignments: [OrgLinkedInAssignment(userId: "u2", pageId: "p1")]
        ))

        let error = await vm.assign(userId: "u2", pageId: "p1")

        XCTAssertNil(error)
        XCTAssertEqual(vm.assignedPage(for: "u2")?.id, "p1")
        let recorded = await orgs.recorded
        XCTAssertTrue(recorded.contains {
            $0.kind == .assignLinkedInPage(orgId: "o1", userId: "u2", pageId: "p1", callerRole: "owner")
        })
    }

    func test_givenNilPageId_whenAssigning_thenClearsTheAssignment() async {
        // Boundary: clearing sends a nil page reference and the member falls
        // back to their personal LinkedIn.
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueLinkedInStatus(success: connected(
            pages: [page("p1", "Acme Corp")],
            assignments: [OrgLinkedInAssignment(userId: "u2", pageId: "p1")]
        ))
        await vm.load()
        await orgs.enqueueAssignPageSuccess()
        await orgs.enqueueLinkedInStatus(success: connected(pages: [page("p1", "Acme Corp")]))

        await vm.assign(userId: "u2", pageId: nil)

        XCTAssertNil(vm.assignedPage(for: "u2"))
        let recorded = await orgs.recorded
        XCTAssertTrue(recorded.contains {
            $0.kind == .assignLinkedInPage(orgId: "o1", userId: "u2", pageId: nil, callerRole: "owner")
        })
    }

    func test_givenMember_whenAssigningPage_thenRejectedByTheRoleGate() async {
        // Invalid input: assignment is owner/admin only.
        let (vm, orgs) = makeViewModel(role: .member)
        await orgs.enqueueLinkedInStatus(success: OrgLinkedInStatus(isConnected: true, callerRole: .member))
        await vm.load()

        let error = await vm.assign(userId: "u2", pageId: "p1")

        XCTAssertEqual(error as? OrgLifecycleError, .linkedInRequiresOwnerOrAdmin)
    }

    func test_givenAssignFails_whenAssigning_thenSurfacesErrorAndKeepsPages() async {
        // Upstream API failure: the page list is untouched so the editor stays
        // usable and the user can retry.
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueLinkedInStatus(success: connected(pages: [page("p1", "Acme Corp")]))
        await vm.load()
        await orgs.enqueueAssignPage(failure: URLError(.badServerResponse))

        let error = await vm.assign(userId: "u2", pageId: "p1")

        XCTAssertNotNil(error)
        XCTAssertNotNil(vm.actionError)
        XCTAssertEqual(vm.pages.count, 1)
    }

    // MARK: - disconnect

    func test_givenOwner_whenDisconnecting_thenRereadsStatusAsDisconnected() async {
        // Happy path.
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueLinkedInStatus(success: connected(
            pages: [page("p1", "Acme Corp")],
            assignments: [OrgLinkedInAssignment(userId: "u2", pageId: "p1")]
        ))
        await vm.load()
        await orgs.enqueueDisconnectSuccess()
        await orgs.enqueueLinkedInStatus(success: OrgLinkedInStatus(isConnected: false, callerRole: .owner))

        let error = await vm.disconnect()

        XCTAssertNil(error)
        XCTAssertFalse(vm.isConnected)
        XCTAssertTrue(vm.pages.isEmpty)
    }

    func test_givenAssignedMembers_whenAboutToDisconnect_thenCountsWhoIsAffected() async {
        // The confirmation names this count, because the consequence lands on
        // people other than the person clicking.
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueLinkedInStatus(success: connected(
            pages: [page("p1", "Acme Corp")],
            assignments: [
                OrgLinkedInAssignment(userId: "u2", pageId: "p1"),
                OrgLinkedInAssignment(userId: "u3", pageId: "p1"),
                // An assignment with no page is not an affected member.
                OrgLinkedInAssignment(userId: "u4", pageId: nil)
            ]
        ))
        await vm.load()

        XCTAssertEqual(vm.assignedMemberCount, 2)
    }

    func test_givenNoAssignments_whenCountingAffectedMembers_thenZero() async {
        // Boundary: nobody is affected, so the confirmation says so instead of
        // naming a count.
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueLinkedInStatus(success: connected(pages: [page("p1", "Acme Corp")]))
        await vm.load()

        XCTAssertEqual(vm.assignedMemberCount, 0)
    }

    func test_givenMember_whenDisconnecting_thenRejectedByTheRoleGate() async {
        // Invalid input: disconnect is owner/admin only.
        let (vm, orgs) = makeViewModel(role: .member)
        await orgs.enqueueLinkedInStatus(success: OrgLinkedInStatus(isConnected: true, callerRole: .member))
        await vm.load()

        let error = await vm.disconnect()

        XCTAssertEqual(error as? OrgLifecycleError, .linkedInRequiresOwnerOrAdmin)
    }

    func test_givenDisconnectFails_whenDisconnecting_thenStaysConnectedAndSurfacesError() async {
        // Upstream API failure: the section must not paint "disconnected" for
        // a disconnect that did not happen.
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueLinkedInStatus(success: connected(pages: [page("p1", "Acme Corp")]))
        await vm.load()
        await orgs.enqueueDisconnect(failure: URLError(.badServerResponse))

        let error = await vm.disconnect()

        XCTAssertNotNil(error)
        XCTAssertTrue(vm.isConnected)
        XCTAssertNotNil(vm.actionError)
    }

    // MARK: - authorize URL

    func test_givenOrgId_whenReadingAuthorizeURL_thenTargetsTheOrgAuthorizeRoute() {
        // Connecting is a browser redirect flow, not an API call.
        let (vm, _) = makeViewModel()

        let url = vm.authorizeURL

        XCTAssertEqual(url?.path, "/api/auth/linkedin/org-authorize")
        XCTAssertEqual(url?.query, "organizationId=o1")
    }
}
