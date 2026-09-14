import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for the Organizations + identities mappers and the two
/// forward-compatible enums `OrgRole` / `IdentityProvider` (PLAN.md §3
/// mapper-in-one-place convention, §6 M6). Includes round-trips and the
/// `.other(String)` fallback paths.
final class OrgMappersTests: XCTestCase {

    private let iso = ISO8601DateFormatter()

    // MARK: - OrgRole

    func test_givenKnownRoleTokens_whenMapping_thenRoundTrips() {
        for token in ["owner", "admin", "member"] {
            let role = OrgRole(wireToken: token)
            XCTAssertEqual(role.wireToken, token, "round-trip failed for \(token)")
        }
    }

    func test_givenMixedCaseRoleToken_whenMapping_thenNormalizes() {
        XCTAssertEqual(OrgRole(wireToken: "OWNER"), .owner)
        XCTAssertEqual(OrgRole(wireToken: "Administrator"), .admin)
    }

    func test_givenUnknownRoleToken_whenMapping_thenPreservesOtherVerbatim() {
        let role = OrgRole(wireToken: "billing-admin")
        XCTAssertEqual(role, .other("billing-admin"))
        // `.other` preserves casing and round-trips the raw value.
        XCTAssertEqual(role.wireToken, "billing-admin")
        XCTAssertEqual(OrgRole(wireToken: "Custom").wireToken, "Custom")
    }

    // MARK: - IdentityProvider

    func test_givenKnownProviderTokens_whenMapping_thenRoundTrips() {
        for token in ["github", "mastodon", "bluesky", "linkedin"] {
            let provider = IdentityProvider(wireToken: token)
            XCTAssertEqual(provider.wireToken, token, "round-trip failed for \(token)")
        }
    }

    func test_givenProviderAliases_whenMapping_thenNormalizes() {
        XCTAssertEqual(IdentityProvider(wireToken: "ATProto"), .bluesky)
        XCTAssertEqual(IdentityProvider(wireToken: "GitHub"), .github)
    }

    func test_givenUnknownProviderToken_whenMapping_thenPreservesOther() {
        let provider = IdentityProvider(wireToken: "threads")
        XCTAssertEqual(provider, .other("threads"))
        XCTAssertEqual(provider.wireToken, "threads")
    }

    // MARK: - Organization mapper

    func test_givenOrgDTO_whenMapping_thenProjectsAllFields() throws {
        let dto = OrganizationDTO(
            id: "o-1",
            name: "Acme",
            description: "We make things",
            isPublic: true,
            createdAt: iso.date(from: Fixtures.createdAtISO),
            updatedAt: iso.date(from: Fixtures.createdAtISO)
        )
        let org = Organization(from: dto)
        XCTAssertEqual(org.id, "o-1")
        XCTAssertEqual(org.name, "Acme")
        XCTAssertEqual(org.description, "We make things")
        XCTAssertTrue(org.isPublic)
        XCTAssertNotNil(org.createdAt)
    }

    func test_givenOrgDTOWithNilIsPublic_whenMapping_thenDefaultsToPrivate() {
        let dto = OrganizationDTO(id: "o-2", name: "Acme", isPublic: nil)
        let org = Organization(from: dto)
        XCTAssertFalse(org.isPublic, "absent isPublic should map to private")
    }

    // MARK: - OrgMember mapper

    func test_givenMemberListingDTO_whenMapping_thenHasNoMembershipId() {
        let dto = OrganizationMemberDTO(userId: "u-1", role: "member", active: true)
        let member = OrgMember(from: dto)
        XCTAssertEqual(member.userId, "u-1")
        XCTAssertEqual(member.role, .member)
        XCTAssertNil(member.membershipId, "listing rows carry no membership-record id")
    }

    func test_givenMembershipDTO_whenMapping_thenCarriesMembershipId() {
        let dto = OrganizationMembershipDTO(
            id: "m-9", userId: "u-1", organizationId: "o-1", role: "admin", active: false
        )
        let member = OrgMember(from: dto)
        XCTAssertEqual(member.membershipId, "m-9")
        XCTAssertEqual(member.role, .admin)
        XCTAssertEqual(member.active, false)
    }

    // MARK: - OrgUser mapper

    func test_givenOrgUserDTO_whenMapping_thenProjectsIdentityAndRole() {
        let dto = OrganizationUserDTO(
            id: "u-1", username: "ada", displayName: "Ada Lovelace",
            avatarUrl: "https://cdn/ada.png", role: "owner"
        )
        let user = OrgUser(from: dto)
        XCTAssertEqual(user.id, "u-1")
        XCTAssertEqual(user.summary.username, "ada")
        XCTAssertEqual(user.summary.displayName, "Ada Lovelace")
        XCTAssertEqual(user.summary.avatarURL?.absoluteString, "https://cdn/ada.png")
        XCTAssertEqual(user.role, .owner)
    }

    func test_givenOrgUserDTOWithNilFields_whenMapping_thenFallsBack() {
        // Boundary: server omits username / displayName / role.
        let dto = OrganizationUserDTO(id: "u-9", username: nil, displayName: nil, avatarUrl: nil, role: nil)
        let user = OrgUser(from: dto)
        // username falls back to id; displayName falls back to username (= id).
        XCTAssertEqual(user.summary.username, "u-9")
        XCTAssertEqual(user.summary.displayName, "u-9")
        XCTAssertNil(user.summary.avatarURL)
        // Absent role maps to `.other("")`.
        XCTAssertEqual(user.role, .other(""))
    }

    // MARK: - LinkedIdentity mapper

    func test_givenIdentityDTO_whenMapping_thenProjectsAllFields() {
        let dto = LinkedIdentityDTO(
            id: "i-1", provider: "github", providerUsername: "ada",
            profileUrl: "https://github.com/ada", avatarUrl: "https://cdn/ada.png",
            connectedAt: iso.date(from: Fixtures.createdAtISO),
            lastVerifiedAt: iso.date(from: Fixtures.createdAtISO)
        )
        let identity = LinkedIdentity(from: dto)
        XCTAssertEqual(identity.id, "i-1")
        XCTAssertEqual(identity.provider, .github)
        XCTAssertEqual(identity.handle, "ada")
        XCTAssertEqual(identity.profileURL?.absoluteString, "https://github.com/ada")
        XCTAssertEqual(identity.avatarURL?.absoluteString, "https://cdn/ada.png")
        XCTAssertNotNil(identity.connectedAt)
    }

    func test_givenIdentityDTOWithNilURLs_whenMapping_thenURLsAreNil() {
        let dto = LinkedIdentityDTO(id: "i-2", provider: "bluesky", providerUsername: nil, profileUrl: nil, avatarUrl: nil)
        let identity = LinkedIdentity(from: dto)
        XCTAssertNil(identity.handle)
        XCTAssertNil(identity.profileURL)
        XCTAssertNil(identity.avatarURL)
    }

    // MARK: - UserOrganization mapper

    func test_givenUserOrgDTO_whenMapping_thenProjectsOrgAndMembership() {
        let dto = UserOrganizationDTO(
            id: "o-1", name: "Acme", isPublic: true, createdAt: iso.date(from: Fixtures.createdAtISO),
            role: "admin", joinedAt: iso.date(from: Fixtures.createdAtISO)
        )
        let membership = UserOrganization(from: dto)
        XCTAssertEqual(membership.id, "o-1")
        XCTAssertEqual(membership.organization.name, "Acme")
        XCTAssertTrue(membership.organization.isPublic)
        XCTAssertEqual(membership.role, .admin)
        XCTAssertNotNil(membership.joinedAt)
    }

    func test_givenUserOrgDTOWithNilIsPublic_whenMapping_thenOrgIsPrivate() {
        let dto = UserOrganizationDTO(id: "o-2", name: "Acme", isPublic: nil, role: "member")
        let membership = UserOrganization(from: dto)
        XCTAssertFalse(membership.organization.isPublic)
        XCTAssertEqual(membership.role, .member)
    }

    // MARK: - Membership context (work-consolidation.md G25)

    func test_givenLiveOrgRow_whenMapping_thenCarriesSystemFlagAndMemberCount() {
        // Happy path: the fields the live collection routes add.
        let org = Organization(from: OrganizationDTO(
            id: "o1",
            name: "The Public",
            isPublic: true,
            slug: "the-public",
            isSystem: true,
            memberCount: 22
        ))

        XCTAssertTrue(org.isSystem)
        XCTAssertEqual(org.slug, "the-public")
        XCTAssertEqual(org.memberCount, 22)
    }

    func test_givenLeanOrgRow_whenMapping_thenDefaultsToOrdinaryLeavableOrg() {
        // Boundary: a response without the flag must not make an ordinary org
        // un-leavable.
        let org = Organization(from: OrganizationDTO(id: "o1", name: "Acme"))

        XCTAssertFalse(org.isSystem)
        XCTAssertNil(org.memberCount)
        XCTAssertNil(org.slug)
    }

    func test_givenRowWithOnlyUserRole_whenResolvingCallerRole_thenFallsBack() {
        // The live routes send `role` and `userRole` with the same value;
        // either alone still resolves.
        let byRole = Organization.callerRole(from: OrganizationDTO(id: "o", name: "n", role: "owner"))
        XCTAssertEqual(byRole, .owner)

        let byUserRole = Organization.callerRole(from: OrganizationDTO(id: "o", name: "n", userRole: "admin"))
        XCTAssertEqual(byUserRole, .admin)

        // Boundary: a non-member row carries neither.
        XCTAssertNil(Organization.callerRole(from: OrganizationDTO(id: "o", name: "n")))
    }

    func test_givenLiveMemberRow_whenMapping_thenCarriesIdentityAndSuspension() {
        // Happy path for the corrected members shape.
        let member = OrgMember(from: OrganizationMemberDTO(
            userId: "u1",
            role: "owner",
            active: false,
            username: "adron",
            displayName: "Adron Hall",
            avatar: "https://cdn/a.jpg",
            emailVerified: true
        ))

        XCTAssertEqual(member.displayLabel, "Adron Hall")
        XCTAssertEqual(member.username, "adron")
        XCTAssertEqual(member.avatarURL?.absoluteString, "https://cdn/a.jpg")
        XCTAssertTrue(member.isSuspended)
    }

    func test_givenBlankAvatarString_whenMapping_thenTreatsItAsAbsent() {
        // Boundary: the live rows use "" for "no avatar", not null.
        let member = OrgMember(from: OrganizationMemberDTO(
            userId: "u2", role: "member", avatar: ""
        ))

        XCTAssertNil(member.avatarURL)
    }

    func test_givenMemberWithNoNames_whenLabelling_thenFallsBackToId() {
        // Boundary: display name → handle → raw id, so a row is never blank.
        let onlyHandle = OrgMember(from: OrganizationMemberDTO(userId: "u3", role: "member", username: "solo"))
        XCTAssertEqual(onlyHandle.displayLabel, "solo")

        let bare = OrgMember(from: OrganizationMemberDTO(userId: "u4", role: "member"))
        XCTAssertEqual(bare.displayLabel, "u4")
    }

    func test_givenMissingActiveFlag_whenMapping_thenNotTreatedAsSuspended() {
        // Invalid/absent input: missing data must not paint a member as
        // suspended.
        let member = OrgMember(from: OrganizationMemberDTO(userId: "u5", role: "member"))
        XCTAssertFalse(member.isSuspended)
    }

    func test_givenSystemOrgMembership_whenCheckingLeavable_thenRefuses() {
        // The row-level half of the leave rule.
        let system = UserOrganization(
            organization: Organization(id: "p", name: "The Public", isSystem: true),
            role: .member
        )
        let ordinary = UserOrganization(
            organization: Organization(id: "o", name: "Acme"),
            role: .member
        )

        XCTAssertFalse(system.isLeavable)
        XCTAssertTrue(ordinary.isLeavable)
    }
}

