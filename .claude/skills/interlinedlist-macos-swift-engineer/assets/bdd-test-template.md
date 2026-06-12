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
