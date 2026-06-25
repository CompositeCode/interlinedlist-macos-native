// OrganizationDetailViewModelTests
//
// BDD-named tests for the M6 org detail view model. Quartet for load
// (happy / failure-keeps-initial) and save (happy / invalid-input-no-call
// / failure). Also asserts the save replaces the rendered org with the
// server's authoritative return value rather than the locally-edited copy.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class OrganizationDetailViewModelTests: XCTestCase {

    private func makeViewModel(
        orgId: String = "o1",
        initial: Organization? = nil
    ) -> (OrganizationDetailViewModel, StubOrgService) {
        let orgs = StubOrgService()
        let vm = OrganizationDetailViewModel(orgService: orgs, orgId: orgId, initial: initial)
        return (vm, orgs)
    }

    // MARK: - load

    func test_givenOrg_whenLoading_thenRendersAuthoritativeFields() async {
        let (vm, orgs) = makeViewModel()
        await orgs.enqueueOrganization(success: Organization(id: "o1", name: "Acme", description: "d", isPublic: true))

        await vm.load()

        XCTAssertEqual(vm.organization?.name, "Acme")
        XCTAssertEqual(vm.organization?.isPublic, true)
        XCTAssertNil(vm.loadError)
    }

    func test_givenLoadFails_whenLoading_thenSurfacesErrorAndKeepsInitial() async {
        let initial = Organization(id: "o1", name: "Cached")
        let (vm, orgs) = makeViewModel(initial: initial)
        await orgs.enqueueOrganization(failure: TestError.upstream("net"))

        await vm.load()

        XCTAssertEqual(vm.loadError as? TestError, .upstream("net"))
        // Optimistic-paint value survives a failed reload.
        XCTAssertEqual(vm.organization?.name, "Cached")
    }

    // MARK: - save

    func test_givenEditedFields_whenSaving_thenReplacesWithServerReturnValue() async {
        let (vm, orgs) = makeViewModel(initial: Organization(id: "o1", name: "Old"))
        // Server canonicalizes the name (e.g. trims / normalizes) — the VM
        // must trust the return value, not the locally-typed string.
        await orgs.enqueueUpdate(success: Organization(id: "o1", name: "New Co (canonical)", isPublic: true))

        let ok = await vm.save(name: "New Co", description: "desc", isPublic: true)

        XCTAssertTrue(ok)
        XCTAssertEqual(vm.organization?.name, "New Co (canonical)")
        XCTAssertNil(vm.saveError)
    }

    func test_givenBlankName_whenSaving_thenRejectsBeforeServiceCall() async {
        let (vm, orgs) = makeViewModel(initial: Organization(id: "o1", name: "Old"))

        let ok = await vm.save(name: "   ", description: "", isPublic: false)

        XCTAssertFalse(ok)
        XCTAssertEqual(vm.saveError as? OrganizationDetailError, .emptyName)
        let recorded = await orgs.recorded
        XCTAssertFalse(recorded.contains { if case .update = $0.kind { return true } else { return false } },
                       "save must not call update on a blank name")
    }

    func test_givenSaveFails_whenSaving_thenSurfacesError() async {
        let (vm, orgs) = makeViewModel(initial: Organization(id: "o1", name: "Old"))
        await orgs.enqueueUpdate(failure: TestError.upstream("boom"))

        let ok = await vm.save(name: "New", description: "", isPublic: false)

        XCTAssertFalse(ok)
        XCTAssertEqual(vm.saveError as? TestError, .upstream("boom"))
        // The rendered org is unchanged on a failed save.
        XCTAssertEqual(vm.organization?.name, "Old")
    }
}
