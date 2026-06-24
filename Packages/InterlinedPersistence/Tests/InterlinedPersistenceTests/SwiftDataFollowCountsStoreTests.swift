import XCTest
import InterlinedDomain
@testable import InterlinedPersistence

/// BDD-named coverage for `SwiftDataFollowCountsStore` (PLAN.md §1 "Follow
/// system", §5 stale-while-revalidate, §6 M5, §7 testing).
final class SwiftDataFollowCountsStoreTests: XCTestCase {

    // MARK: - Round-trip

    func test_givenCachedFollowCounts_whenReading_thenReturnsFollowSide() async throws {
        // Given
        let store = try SwiftDataFollowCountsStore.inMemory()

        // When
        await store.cacheFollowCounts(
            FollowCounts(followers: 42, following: 7),
            for: "user-1"
        )

        // Then
        let cached = await store.cached(userID: "user-1")
        XCTAssertEqual(cached?.follow, FollowCounts(followers: 42, following: 7))
        // Mutual side defaults to zero when only follow counts were written.
        XCTAssertEqual(cached?.mutual, .zero)
        XCTAssertEqual(cached?.userID, "user-1")
    }

    func test_givenCachedMutualCounts_whenReading_thenReturnsMutualSide() async throws {
        // Given
        let store = try SwiftDataFollowCountsStore.inMemory()

        // When
        await store.cacheMutualCounts(
            MutualCounts(mutualFollowers: 12, mutualFollowing: 5),
            for: "user-1"
        )

        // Then
        let cached = await store.cached(userID: "user-1")
        XCTAssertEqual(cached?.mutual, MutualCounts(mutualFollowers: 12, mutualFollowing: 5))
        XCTAssertEqual(cached?.follow, .zero)
    }

    func test_givenBothSidesWritten_whenReading_thenReturnsCombined() async throws {
        // Given
        let store = try SwiftDataFollowCountsStore.inMemory()

        // When
        await store.cacheFollowCounts(
            FollowCounts(followers: 100, following: 50),
            for: "user-1"
        )
        await store.cacheMutualCounts(
            MutualCounts(mutualFollowers: 4, mutualFollowing: 3),
            for: "user-1"
        )

        // Then — both sides land on the same record.
        let cached = await store.cached(userID: "user-1")
        XCTAssertEqual(cached?.follow.followers, 100)
        XCTAssertEqual(cached?.follow.following, 50)
        XCTAssertEqual(cached?.mutual.mutualFollowers, 4)
        XCTAssertEqual(cached?.mutual.mutualFollowing, 3)
    }

    func test_givenSecondWrite_whenReading_thenLatestWins() async throws {
        // Given
        let store = try SwiftDataFollowCountsStore.inMemory()
        await store.cacheFollowCounts(FollowCounts(followers: 1, following: 1), for: "user-1")

        // When
        await store.cacheFollowCounts(FollowCounts(followers: 9, following: 9), for: "user-1")

        // Then — upsert semantics, not duplicate.
        let cached = await store.cached(userID: "user-1")
        XCTAssertEqual(cached?.follow.followers, 9)
        XCTAssertEqual(cached?.follow.following, 9)
    }

    // MARK: - Per-user isolation

    func test_givenTwoUsers_whenReadingEach_thenIsolatedFromEachOther() async throws {
        // Given
        let store = try SwiftDataFollowCountsStore.inMemory()
        await store.cacheFollowCounts(FollowCounts(followers: 10, following: 5), for: "user-1")
        await store.cacheFollowCounts(FollowCounts(followers: 200, following: 1), for: "user-2")
        await store.cacheMutualCounts(MutualCounts(mutualFollowers: 3, mutualFollowing: 1), for: "user-2")

        // When
        let a = await store.cached(userID: "user-1")
        let b = await store.cached(userID: "user-2")

        // Then
        XCTAssertEqual(a?.follow, FollowCounts(followers: 10, following: 5))
        XCTAssertEqual(a?.mutual, .zero)
        XCTAssertEqual(b?.follow, FollowCounts(followers: 200, following: 1))
        XCTAssertEqual(b?.mutual, MutualCounts(mutualFollowers: 3, mutualFollowing: 1))
    }

    // MARK: - Empty / boundary

    func test_givenEmptyStore_whenReading_thenReturnsNil() async throws {
        // Given
        let store = try SwiftDataFollowCountsStore.inMemory()

        // When
        let cached = await store.cached(userID: "user-1")

        // Then
        XCTAssertNil(cached)
    }

    // MARK: - remove

    func test_givenCachedUser_whenRemoving_thenSubsequentReadIsNil() async throws {
        // Given
        let store = try SwiftDataFollowCountsStore.inMemory()
        await store.cacheFollowCounts(FollowCounts(followers: 1, following: 1), for: "user-1")

        // When
        await store.remove(userID: "user-1")

        // Then
        let cached = await store.cached(userID: "user-1")
        XCTAssertNil(cached)
    }

    func test_givenMissingUser_whenRemoving_thenNoOp() async throws {
        // Given — boundary: empty store; remove is a no-op (no throw).
        let store = try SwiftDataFollowCountsStore.inMemory()

        // When / Then
        await store.remove(userID: "ghost")
    }

    // MARK: - clear

    func test_givenPopulatedStore_whenCleared_thenAllRowsEmpty() async throws {
        // Given
        let store = try SwiftDataFollowCountsStore.inMemory()
        await store.cacheFollowCounts(FollowCounts(followers: 1, following: 1), for: "user-1")
        await store.cacheFollowCounts(FollowCounts(followers: 2, following: 2), for: "user-2")

        // When
        await store.clear()

        // Then
        let a = await store.cached(userID: "user-1")
        let b = await store.cached(userID: "user-2")
        XCTAssertNil(a)
        XCTAssertNil(b)
    }
}
