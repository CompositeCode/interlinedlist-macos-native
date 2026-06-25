import XCTest
import InterlinedDomain
@testable import InterlinedPersistence

/// BDD-named coverage for `SwiftDataOrgStore` (PLAN.md §1 "Organizations",
/// §5 stale-while-revalidate, §6 M6, §7 testing).
final class SwiftDataOrgStoreTests: XCTestCase {

    // MARK: - Organization round-trip

    func test_givenCachedOrganization_whenReadingByID_thenRoundTripsEveryField() async throws {
        // Given
        let store = try SwiftDataOrgStore.inMemory()
        let org = sampleOrg(
            id: "org-1",
            name: "Acme",
            description: "A test org",
            isPublic: true,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            updatedAt: Date(timeIntervalSince1970: 2_000_000)
        )

        // When
        await store.cacheOrganization(org)

        // Then
        let cached = await store.cachedOrganization(id: "org-1")
        XCTAssertEqual(cached, org)
    }

    func test_givenSeveralCachedOrgs_whenReadingAll_thenAllReturned() async throws {
        // Given
        let store = try SwiftDataOrgStore.inMemory()
        await store.cacheOrganizations([
            sampleOrg(id: "org-1", name: "Acme"),
            sampleOrg(id: "org-2", name: "Globex"),
            sampleOrg(id: "org-3", name: "Initech")
        ])

        // When
        let cached = await store.cachedOrganizations()

        // Then
        XCTAssertEqual(Set(cached.map(\.id)), ["org-1", "org-2", "org-3"])
    }

    func test_givenOrgCachedTwice_whenReading_thenLatestWins() async throws {
        // Given
        let store = try SwiftDataOrgStore.inMemory()
        await store.cacheOrganization(sampleOrg(id: "org-1", name: "Old Name", isPublic: false))

        // When — second write supersedes, not duplicates.
        await store.cacheOrganization(sampleOrg(id: "org-1", name: "New Name", isPublic: true))

        // Then
        let all = await store.cachedOrganizations()
        XCTAssertEqual(all.count, 1)
        let cached = await store.cachedOrganization(id: "org-1")
        XCTAssertEqual(cached?.name, "New Name")
        XCTAssertEqual(cached?.isPublic, true)
    }

    // MARK: - Member round-trip + role

    func test_givenCachedMembers_whenReading_thenRoundTripsEveryField() async throws {
        // Given
        let store = try SwiftDataOrgStore.inMemory()
        let member = OrgMember(
            userId: "user-1",
            membershipId: "mem-1",
            role: .admin,
            active: true,
            createdAt: Date(timeIntervalSince1970: 1_234_567)
        )

        // When
        await store.cacheMembers([member], of: "org-1")

        // Then
        let cached = await store.cachedMembers(of: "org-1")
        XCTAssertEqual(cached, [member])
    }

    func test_givenEveryKnownRole_whenRoundTripping_thenRolePreserved() async throws {
        // Given — one member per typed role.
        let store = try SwiftDataOrgStore.inMemory()
        let members = [
            OrgMember(userId: "u-owner", role: .owner),
            OrgMember(userId: "u-admin", role: .admin),
            OrgMember(userId: "u-member", role: .member)
        ]
        await store.cacheMembers(members, of: "org-1")

        // When
        let cached = await store.cachedMembers(of: "org-1")

        // Then
        let byID = Dictionary(uniqueKeysWithValues: cached.map { ($0.userId, $0.role) })
        XCTAssertEqual(byID["u-owner"], .owner)
        XCTAssertEqual(byID["u-admin"], .admin)
        XCTAssertEqual(byID["u-member"], .member)
    }

    func test_givenOtherRole_whenRoundTripping_thenWireTokenPreserved() async throws {
        // Given — a role token the client does not yet recognise.
        let store = try SwiftDataOrgStore.inMemory()
        await store.cacheMembers(
            [OrgMember(userId: "user-1", role: .other("billing_admin"))],
            of: "org-1"
        )

        // When
        let cached = await store.cachedMembers(of: "org-1")

        // Then — the original wire token survives the round-trip.
        XCTAssertEqual(cached.first?.role, .other("billing_admin"))
    }

    // MARK: - Per-org member isolation

    func test_givenMembersInTwoOrgs_whenReadingEach_thenIsolatedFromEachOther() async throws {
        // Given
        let store = try SwiftDataOrgStore.inMemory()
        await store.cacheMembers(
            [OrgMember(userId: "user-1", role: .owner)],
            of: "org-1"
        )
        await store.cacheMembers(
            [
                OrgMember(userId: "user-2", role: .member),
                OrgMember(userId: "user-3", role: .admin)
            ],
            of: "org-2"
        )

        // When
        let a = await store.cachedMembers(of: "org-1")
        let b = await store.cachedMembers(of: "org-2")

        // Then
        XCTAssertEqual(a.map(\.userId), ["user-1"])
        XCTAssertEqual(Set(b.map(\.userId)), ["user-2", "user-3"])
    }

    func test_givenSameUserInTwoOrgs_whenReadingEach_thenRoleMayDifferPerOrg() async throws {
        // Given — the composite (orgID, userId) identity means the same user
        // can hold a different role in two orgs without collision.
        let store = try SwiftDataOrgStore.inMemory()
        await store.cacheMembers([OrgMember(userId: "user-1", role: .owner)], of: "org-1")
        await store.cacheMembers([OrgMember(userId: "user-1", role: .member)], of: "org-2")

        // When
        let inOrg1 = await store.cachedMembers(of: "org-1").first
        let inOrg2 = await store.cachedMembers(of: "org-2").first

        // Then
        XCTAssertEqual(inOrg1?.role, .owner)
        XCTAssertEqual(inOrg2?.role, .member)
    }

    // MARK: - Member second-write-wins

    func test_givenMembersReplaced_whenReading_thenOnlyLatestSliceRemains() async throws {
        // Given
        let store = try SwiftDataOrgStore.inMemory()
        await store.cacheMembers(
            [OrgMember(userId: "old-1", role: .member), OrgMember(userId: "old-2", role: .member)],
            of: "org-1"
        )

        // When — page replace: removed members disappear.
        await store.cacheMembers([OrgMember(userId: "new-1", role: .admin)], of: "org-1")

        // Then
        let cached = await store.cachedMembers(of: "org-1")
        XCTAssertEqual(cached.map(\.userId), ["new-1"])
    }

    func test_givenUpsertMemberRoleChange_whenReading_thenRoleUpdatedNotDuplicated() async throws {
        // Given — a member already cached as `.member`.
        let store = try SwiftDataOrgStore.inMemory()
        await store.cacheMembers([OrgMember(userId: "user-1", role: .member)], of: "org-1")

        // When — a role-update response upserts the same pair as `.admin`.
        await store.upsertMember(OrgMember(userId: "user-1", role: .admin), in: "org-1")

        // Then — one row, updated role.
        let cached = await store.cachedMembers(of: "org-1")
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached.first?.role, .admin)
    }

    func test_givenUpsertNewMember_whenReading_thenAppendedToOrg() async throws {
        // Given
        let store = try SwiftDataOrgStore.inMemory()
        await store.cacheMembers([OrgMember(userId: "user-1", role: .owner)], of: "org-1")

        // When — add-member response upserts a brand-new pair.
        await store.upsertMember(OrgMember(userId: "user-2", role: .member), in: "org-1")

        // Then
        let cached = await store.cachedMembers(of: "org-1")
        XCTAssertEqual(Set(cached.map(\.userId)), ["user-1", "user-2"])
    }

    // MARK: - remove member

    func test_givenCachedMember_whenRemoving_thenGoneFromOrgOnly() async throws {
        // Given
        let store = try SwiftDataOrgStore.inMemory()
        await store.cacheMembers(
            [OrgMember(userId: "user-1", role: .member), OrgMember(userId: "user-2", role: .admin)],
            of: "org-1"
        )

        // When
        await store.removeMember(userId: "user-1", from: "org-1")

        // Then
        let cached = await store.cachedMembers(of: "org-1")
        XCTAssertEqual(cached.map(\.userId), ["user-2"])
    }

    func test_givenMissingMember_whenRemoving_thenNoOp() async throws {
        // Given — boundary: empty org.
        let store = try SwiftDataOrgStore.inMemory()

        // When / Then — no throw.
        await store.removeMember(userId: "ghost", from: "org-1")
        let cached = await store.cachedMembers(of: "org-1")
        XCTAssertTrue(cached.isEmpty)
    }

    // MARK: - remove organization (clear-cascade for one org)

    func test_givenOrgWithMembers_whenRemovingOrg_thenOrgAndItsMembersGone() async throws {
        // Given
        let store = try SwiftDataOrgStore.inMemory()
        await store.cacheOrganization(sampleOrg(id: "org-1", name: "Acme"))
        await store.cacheOrganization(sampleOrg(id: "org-2", name: "Globex"))
        await store.cacheMembers([OrgMember(userId: "user-1", role: .owner)], of: "org-1")
        await store.cacheMembers([OrgMember(userId: "user-2", role: .owner)], of: "org-2")

        // When
        await store.removeOrganization(id: "org-1")

        // Then — org-1 and its members gone; org-2 untouched.
        let org1 = await store.cachedOrganization(id: "org-1")
        let org1Members = await store.cachedMembers(of: "org-1")
        let org2 = await store.cachedOrganization(id: "org-2")
        let org2Members = await store.cachedMembers(of: "org-2")
        XCTAssertNil(org1)
        XCTAssertTrue(org1Members.isEmpty)
        XCTAssertNotNil(org2)
        XCTAssertEqual(org2Members.map(\.userId), ["user-2"])
    }

    func test_givenMissingOrg_whenRemovingOrg_thenNoOp() async throws {
        // Given — boundary: empty store.
        let store = try SwiftDataOrgStore.inMemory()

        // When / Then — no throw.
        await store.removeOrganization(id: "ghost")
        let all = await store.cachedOrganizations()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - clear (cascade)

    func test_givenPopulatedStore_whenCleared_thenOrgsAndMembersBothEmpty() async throws {
        // Given
        let store = try SwiftDataOrgStore.inMemory()
        await store.cacheOrganizations([
            sampleOrg(id: "org-1", name: "Acme"),
            sampleOrg(id: "org-2", name: "Globex")
        ])
        await store.cacheMembers([OrgMember(userId: "user-1", role: .owner)], of: "org-1")
        await store.cacheMembers([OrgMember(userId: "user-2", role: .owner)], of: "org-2")

        // When
        await store.clear()

        // Then
        let orgs = await store.cachedOrganizations()
        let m1 = await store.cachedMembers(of: "org-1")
        let m2 = await store.cachedMembers(of: "org-2")
        XCTAssertTrue(orgs.isEmpty)
        XCTAssertTrue(m1.isEmpty)
        XCTAssertTrue(m2.isEmpty)
    }

    // MARK: - Empty / boundary reads

    func test_givenEmptyStore_whenReadingOrgByID_thenReturnsNil() async throws {
        // Given
        let store = try SwiftDataOrgStore.inMemory()

        // When
        let cached = await store.cachedOrganization(id: "org-1")

        // Then
        XCTAssertNil(cached)
    }

    func test_givenEmptyStore_whenReadingMembers_thenReturnsEmptyArray() async throws {
        // Given
        let store = try SwiftDataOrgStore.inMemory()

        // When
        let cached = await store.cachedMembers(of: "org-1")

        // Then
        XCTAssertTrue(cached.isEmpty)
    }

    func test_givenEmptyMemberSlice_whenCaching_thenOrgHasNoMembers() async throws {
        // Given — boundary: caching an empty member page (an org with no
        // members on this page) must clear the prior slice cleanly.
        let store = try SwiftDataOrgStore.inMemory()
        await store.cacheMembers([OrgMember(userId: "user-1", role: .owner)], of: "org-1")

        // When
        await store.cacheMembers([], of: "org-1")

        // Then
        let cached = await store.cachedMembers(of: "org-1")
        XCTAssertTrue(cached.isEmpty)
    }

    // MARK: - Helpers

    private func sampleOrg(
        id: String,
        name: String,
        description: String? = nil,
        isPublic: Bool = false,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) -> Organization {
        Organization(
            id: id,
            name: name,
            description: description,
            isPublic: isPublic,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
