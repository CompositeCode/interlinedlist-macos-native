// OrganizationsListViewModelTests
//
// BDD-named tests for the M6 Organizations master-list view model.
// Quartet per behavior: load (happy / empty / failure) and create
// (happy / invalid-input-no-call / failure). The invalid-input case
// asserts no service call was made (decision: validate before the
// network round-trip).

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class OrganizationsListViewModelTests: XCTestCase {

    private func makeViewModel() -> (OrganizationsListViewModel, StubOrgService, StubUserService) {
        let orgs = StubOrgService()
        let user = StubUserService()
        let vm = OrganizationsListViewModel(orgService: orgs, userService: user)
        return (vm, orgs, user)
    }

    private func membership(id: String, name: String, role: OrgRole = .member) -> UserOrganization {
        UserOrganization(organization: Organization(id: id, name: name), role: role)
    }

    // MARK: - load

    func test_givenMemberships_whenLoading_thenRendersList() async {
        let (vm, _, user) = makeViewModel()
        user.enqueueOrganizations(success: [
            membership(id: "o1", name: "Acme", role: .owner),
            membership(id: "o2", name: "Globex", role: .member)
        ])

        await vm.load()

        XCTAssertEqual(vm.memberships.map(\.id), ["o1", "o2"])
        XCTAssertNil(vm.loadError)
    }

    func test_givenNoMemberships_whenLoading_thenListIsEmpty() async {
        let (vm, _, user) = makeViewModel()
        user.enqueueOrganizations(success: [])

        await vm.load()

        XCTAssertTrue(vm.memberships.isEmpty)
        XCTAssertNil(vm.loadError)
    }

    func test_givenOrganizationsEndpointFails_whenLoading_thenSurfacesError() async {
        let (vm, _, user) = makeViewModel()
        user.enqueueOrganizations(failure: TestError.upstream("net"))

        await vm.load()

        XCTAssertTrue(vm.memberships.isEmpty)
        XCTAssertEqual(vm.loadError as? TestError, .upstream("net"))
    }

    // MARK: - create

    func test_givenValidName_whenCreating_thenPrependsCreatedOrgAsOwner() async {
        let (vm, orgs, user) = makeViewModel()
        user.enqueueOrganizations(success: [membership(id: "o1", name: "Acme")])
        await orgs.enqueueCreate(success: Organization(id: "o9", name: "New Co", isPublic: true))
        await vm.load()

        let created = await vm.create(name: "New Co", description: "desc", isPublic: true)

        XCTAssertEqual(created?.id, "o9")
        XCTAssertEqual(vm.memberships.first?.id, "o9")
        XCTAssertEqual(vm.memberships.first?.role, .owner)
        XCTAssertNil(vm.createError)
    }

    func test_givenBlankName_whenCreating_thenRejectsBeforeServiceCall() async {
        let (vm, orgs, _) = makeViewModel()

        let created = await vm.create(name: "   ", description: "", isPublic: false)

        XCTAssertNil(created)
        XCTAssertEqual(vm.createError as? OrganizationsListError, .emptyName)
        let recorded = await orgs.recorded
        XCTAssertTrue(recorded.isEmpty, "create must not call the service on a blank name")
    }

    func test_givenCreateFails_whenCreating_thenSurfacesErrorAndDoesNotInsert() async {
        let (vm, orgs, user) = makeViewModel()
        user.enqueueOrganizations(success: [])
        await orgs.enqueueCreate(failure: TestError.upstream("boom"))
        await vm.load()

        let created = await vm.create(name: "New Co", description: "", isPublic: false)

        XCTAssertNil(created)
        XCTAssertEqual(vm.createError as? TestError, .upstream("boom"))
        XCTAssertTrue(vm.memberships.isEmpty)
    }
}
