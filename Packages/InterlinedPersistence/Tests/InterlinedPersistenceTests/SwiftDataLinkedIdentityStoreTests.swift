import XCTest
import InterlinedDomain
@testable import InterlinedPersistence

/// BDD-named coverage for `SwiftDataLinkedIdentityStore` (PLAN.md §1
/// "Profile & account / linked identities", §5 stale-while-revalidate,
/// §6 M6, §7 testing).
final class SwiftDataLinkedIdentityStoreTests: XCTestCase {

    // MARK: - Round-trip

    func test_givenCachedIdentity_whenReadingByID_thenRoundTripsEveryField() async throws {
        // Given
        let store = try SwiftDataLinkedIdentityStore.inMemory()
        let identity = LinkedIdentity(
            id: "id-1",
            provider: .github,
            handle: "octocat",
            profileURL: URL(string: "https://github.com/octocat"),
            avatarURL: URL(string: "https://cdn/octocat.png"),
            connectedAt: Date(timeIntervalSince1970: 1_000_000),
            lastVerifiedAt: Date(timeIntervalSince1970: 2_000_000)
        )

        // When
        await store.replaceIdentities([identity])

        // Then
        let cached = await store.cachedIdentity(id: "id-1")
        XCTAssertEqual(cached, identity)
    }

    func test_givenEveryKnownProvider_whenRoundTripping_thenProviderPreserved() async throws {
        // Given — one identity per typed provider.
        let store = try SwiftDataLinkedIdentityStore.inMemory()
        let identities = [
            sampleIdentity(id: "i-gh", provider: .github),
            sampleIdentity(id: "i-md", provider: .mastodon),
            sampleIdentity(id: "i-bs", provider: .bluesky),
            sampleIdentity(id: "i-li", provider: .linkedin)
        ]
        await store.replaceIdentities(identities)

        // When
        let cached = await store.cachedIdentities()

        // Then
        let byID = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0.provider) })
        XCTAssertEqual(byID["i-gh"], .github)
        XCTAssertEqual(byID["i-md"], .mastodon)
        XCTAssertEqual(byID["i-bs"], .bluesky)
        XCTAssertEqual(byID["i-li"], .linkedin)
    }

    func test_givenOtherProvider_whenRoundTripping_thenWireTokenPreserved() async throws {
        // Given — a provider token the client does not yet recognise.
        let store = try SwiftDataLinkedIdentityStore.inMemory()
        await store.replaceIdentities([sampleIdentity(id: "i-x", provider: .other("pixelfed"))])

        // When
        let cached = await store.cachedIdentity(id: "i-x")

        // Then
        XCTAssertEqual(cached?.provider, .other("pixelfed"))
    }

    func test_givenIdentityWithNilURLsAndDates_whenRoundTripping_thenNilsPreserved() async throws {
        // Given — boundary: every optional omitted.
        let store = try SwiftDataLinkedIdentityStore.inMemory()
        let bare = LinkedIdentity(id: "i-bare", provider: .github)

        // When
        await store.replaceIdentities([bare])

        // Then
        let cached = await store.cachedIdentity(id: "i-bare")
        XCTAssertEqual(cached, bare)
        XCTAssertNil(cached?.handle)
        XCTAssertNil(cached?.profileURL)
        XCTAssertNil(cached?.avatarURL)
        XCTAssertNil(cached?.connectedAt)
        XCTAssertNil(cached?.lastVerifiedAt)
    }

    // MARK: - Full-replace semantics (second-write-wins)

    func test_givenReplacedTwice_whenReading_thenOnlyLatestSetRemains() async throws {
        // Given
        let store = try SwiftDataLinkedIdentityStore.inMemory()
        await store.replaceIdentities([
            sampleIdentity(id: "old-1", provider: .github),
            sampleIdentity(id: "old-2", provider: .mastodon)
        ])

        // When — full replace: the prior set is wiped.
        await store.replaceIdentities([sampleIdentity(id: "new-1", provider: .bluesky)])

        // Then
        let cached = await store.cachedIdentities()
        XCTAssertEqual(cached.map(\.id), ["new-1"])
    }

    // MARK: - remove

    func test_givenCachedIdentity_whenRemoving_thenSubsequentReadIsNil() async throws {
        // Given
        let store = try SwiftDataLinkedIdentityStore.inMemory()
        await store.replaceIdentities([
            sampleIdentity(id: "i-1", provider: .github),
            sampleIdentity(id: "i-2", provider: .mastodon)
        ])

        // When
        await store.removeIdentity(id: "i-1")

        // Then
        let removed = await store.cachedIdentity(id: "i-1")
        let kept = await store.cachedIdentity(id: "i-2")
        XCTAssertNil(removed)
        XCTAssertNotNil(kept)
    }

    func test_givenMissingIdentity_whenRemoving_thenNoOp() async throws {
        // Given — boundary: empty store.
        let store = try SwiftDataLinkedIdentityStore.inMemory()

        // When / Then — no throw.
        await store.removeIdentity(id: "ghost")
        let cached = await store.cachedIdentities()
        XCTAssertTrue(cached.isEmpty)
    }

    // MARK: - clear

    func test_givenPopulatedStore_whenCleared_thenAllRowsGone() async throws {
        // Given
        let store = try SwiftDataLinkedIdentityStore.inMemory()
        await store.replaceIdentities([
            sampleIdentity(id: "i-1", provider: .github),
            sampleIdentity(id: "i-2", provider: .mastodon)
        ])

        // When
        await store.clear()

        // Then
        let cached = await store.cachedIdentities()
        XCTAssertTrue(cached.isEmpty)
    }

    // MARK: - Empty / boundary reads

    func test_givenEmptyStore_whenReadingByID_thenReturnsNil() async throws {
        // Given
        let store = try SwiftDataLinkedIdentityStore.inMemory()

        // When
        let cached = await store.cachedIdentity(id: "i-1")

        // Then
        XCTAssertNil(cached)
    }

    func test_givenEmptyStore_whenReadingAll_thenReturnsEmptyArray() async throws {
        // Given
        let store = try SwiftDataLinkedIdentityStore.inMemory()

        // When
        let cached = await store.cachedIdentities()

        // Then
        XCTAssertTrue(cached.isEmpty)
    }

    func test_givenEmptyPayload_whenReplacing_thenStoreIsEmpty() async throws {
        // Given — boundary: replacing with an empty list (account unlinked
        // everything) clears the cache cleanly.
        let store = try SwiftDataLinkedIdentityStore.inMemory()
        await store.replaceIdentities([sampleIdentity(id: "i-1", provider: .github)])

        // When
        await store.replaceIdentities([])

        // Then
        let cached = await store.cachedIdentities()
        XCTAssertTrue(cached.isEmpty)
    }

    // MARK: - Helpers

    private func sampleIdentity(
        id: String,
        provider: IdentityProvider
    ) -> LinkedIdentity {
        LinkedIdentity(
            id: id,
            provider: provider,
            handle: "handle-\(id)",
            profileURL: URL(string: "https://example.com/\(id)"),
            avatarURL: URL(string: "https://cdn/\(id).png"),
            connectedAt: Date(timeIntervalSince1970: 1_000_000),
            lastVerifiedAt: Date(timeIntervalSince1970: 1_500_000)
        )
    }
}
