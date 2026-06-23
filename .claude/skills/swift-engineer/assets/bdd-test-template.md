# BDD-Style XCTest Template

## Naming Pattern
- test_givenCondition_whenAction_thenExpectedResult

## Example Skeleton
```swift
func test_givenValidToken_whenFetchingLists_thenReturnsLists() async throws {
    // Given
    let api = APIClientStub(response: .success([ListDTO(id: "1", name: "Inbox")]))
    let service = ListsService(apiClient: api)

    // When
    let lists = try await service.fetchLists()

    // Then
    XCTAssertEqual(lists.count, 1)
    XCTAssertEqual(lists.first?.name, "Inbox")
}
```

## Minimum Coverage
- Happy path
- Invalid input
- Upstream API failure
- Empty response or boundary case

## Pattern-Specific Additions (when applicable)

- **Optimistic UI** — rollback test that asserts the snapshot was restored on failure.
- **Cache fallback** — empty-cache (throws) + populated-cache (returns cached) cases.
- **Pagination** — `hasMore` / `nextOffset` assertion + zero-item-page boundary.
- **AsyncStream consumers** — cancellation test (consumer drops; producer stops).
- **Event-bus subscribers** — event for matching id mutates; event for non-matching id is a no-op.

## App-target tests

- Test view models, not SwiftUI views. View correctness is verified by build + hand-check.
- Use a hosted XCTest bundle (`BUNDLE_LOADER` + `TEST_HOST`) so view models can be tested with `@testable import` of the app module.
- Stubs live under `AppTests/Support/` (e.g., `StubMessagesService`, `StubSessionManaging`); reuse them across suites.
