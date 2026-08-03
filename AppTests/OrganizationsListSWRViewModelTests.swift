// OrganizationsListSWRViewModelTests
//
// Stale-while-revalidate (SWR) view-model tests for the Organizations
// master list (PLAN.md §5, PASS 2). Exercises the cache-first paint added
// in PASS 2 via `StubUserService.setCachedOrganizations`. View-model only.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class OrganizationsListSWRViewModelTests: XCTestCase {

    private func makeViewModel() -> (OrganizationsListViewModel, StubOrgService, StubUserService) {
        let orgs = StubOrgService()
        let user = StubUserService()
        let vm = OrganizationsListViewModel(orgService: orgs, userService: user)
        return (vm, orgs, user)
    }

    private func membership(id: String, name: String, role: OrgRole = .member) -> UserOrganization {
        UserOrganization(organization: Organization(id: id, name: name), role: role)
    }

    // MARK: - Cache present

    func test_givenCachedMemberships_whenLoading_thenPaintsCacheWithoutBlockingSpinner() async {
        // Given
        let (vm, _, user) = makeViewModel()
        user.setCachedOrganizations([membership(id: "o1", name: "Cached")])
        user.enqueueOrganizations(success: [
            membership(id: "o1", name: "Fresh", role: .owner),
            membership(id: "o2", name: "New")
        ])

        // When
        await vm.load()

        // Then
        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isRefreshing)
        XCTAssertEqual(vm.memberships.map(\.id), ["o1", "o2"])
        XCTAssertNil(vm.loadError)
        XCTAssertNotNil(vm.lastRefreshedAt)
    }

    // MARK: - Cold cache

    func test_givenEmptyCache_whenLoading_thenUsesBlockingSpinnerThenData() async {
        // Given
        let (vm, _, user) = makeViewModel()
        user.enqueueOrganizations(success: [membership(id: "o1", name: "Acme")])

        // When
        await vm.load()

        // Then
        XCTAssertEqual(vm.memberships.map(\.id), ["o1"])
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isRefreshing)
        XCTAssertFalse(vm.refreshFailed)
    }

    // MARK: - Refresh error with cache

    func test_givenCachedMembershipsAndRefreshFails_whenLoading_thenKeepsRowsAndSetsRefreshFailed() async {
        // Given
        let (vm, _, user) = makeViewModel()
        user.setCachedOrganizations([membership(id: "o1", name: "Cached")])
        user.enqueueOrganizations(failure: TestError.upstream("revalidate down"))

        // When
        await vm.load()

        // Then — rows kept; non-blocking flag set; blocking loadError unset.
        XCTAssertEqual(vm.memberships.map(\.id), ["o1"])
        XCTAssertTrue(vm.refreshFailed)
        XCTAssertNil(vm.loadError)
    }

    // MARK: - Cold cache + failure → blocking error

    func test_givenEmptyCacheAndNetworkFails_whenLoading_thenSurfacesBlockingError() async {
        // Given
        let (vm, _, user) = makeViewModel()
        user.enqueueOrganizations(failure: TestError.upstream("net"))

        // When
        await vm.load()

        // Then
        XCTAssertTrue(vm.memberships.isEmpty)
        XCTAssertEqual(vm.loadError as? TestError, .upstream("net"))
        XCTAssertFalse(vm.refreshFailed)
    }

    // MARK: - Freshness TTL

    func test_givenFreshlyRefreshed_whenCheckingShouldRefresh_thenSkipsRevalidation() async {
        let (vm, _, user) = makeViewModel()
        user.enqueueOrganizations(success: [membership(id: "o1", name: "Acme")])
        await vm.load()
        XCTAssertFalse(vm.shouldRefresh)
    }
}
