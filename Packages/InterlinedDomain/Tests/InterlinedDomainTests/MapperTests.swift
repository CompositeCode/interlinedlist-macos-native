import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// Verifies the DTO → domain boundary (PLAN.md §3): nullable fields resolve to
/// sensible defaults and no DTO leaks through.
final class MapperTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: UserSummary

    func test_givenSummaryWithDisplayName_whenMapped_thenUsesDisplayName() {
        // Given
        let dto = UserSummaryDTO(id: "1", username: "ada", displayName: "Ada", avatar: "https://x/a.png")

        // When
        let summary = UserSummary(from: dto)

        // Then
        XCTAssertEqual(summary.displayName, "Ada")
        XCTAssertEqual(summary.avatarURL, URL(string: "https://x/a.png"))
    }

    func test_givenSummaryMissingDisplayName_whenMapped_thenFallsBackToUsername() {
        // Given
        let dto = UserSummaryDTO(id: "1", username: "ada", displayName: nil, avatar: nil)

        // When
        let summary = UserSummary(from: dto)

        // Then
        XCTAssertEqual(summary.displayName, "ada")
        XCTAssertNil(summary.avatarURL)
    }

    // MARK: Message

    func test_givenMessageWithNullTags_whenMapped_thenTagsAreEmpty() {
        // Given
        let dto = makeMessageDTO(tags: nil)

        // When
        let message = Message(from: dto)

        // Then
        XCTAssertEqual(message.tags, [])
    }

    func test_givenPublicMessage_whenMapped_thenVisibilityIsPublic() {
        // Given / When
        let message = Message(from: makeMessageDTO(publiclyVisible: true))

        // Then
        XCTAssertEqual(message.visibility, .public)
        XCTAssertTrue(message.visibility.isPubliclyVisible)
    }

    func test_givenPrivateMessage_whenMapped_thenVisibilityIsPrivate() {
        // Given / When
        let message = Message(from: makeMessageDTO(publiclyVisible: false))

        // Then
        XCTAssertEqual(message.visibility, .private)
    }

    func test_givenMessageWithPushedMessage_whenMapped_thenCarriesRepost() {
        // Given
        let original = makeMessageDTO(id: "orig")
        let dto = makeMessageDTO(id: "repost", pushedMessage: PushedMessageBox(original))

        // When
        let message = Message(from: dto)

        // Then
        XCTAssertEqual(message.repost?.original.id, "orig")
    }

    func test_givenMessageWithoutPushedMessage_whenMapped_thenRepostIsNil() {
        // Given / When
        let message = Message(from: makeMessageDTO(pushedMessage: nil))

        // Then
        XCTAssertNil(message.repost)
    }

    func test_givenMessageDigState_whenMapped_thenPreservesDigCountAndFlag() {
        // Given / When
        let message = Message(from: makeMessageDTO(digCount: 7, dugByMe: true))

        // Then
        XCTAssertEqual(message.digCount, 7)
        XCTAssertTrue(message.didDig)
    }

    // MARK: CurrentUser

    func test_givenSubscriberUser_whenMapped_thenCustomerStatusIsSubscriber() {
        // Given / When
        let user = CurrentUser(from: makeUserDTO(customerStatus: "subscriber"))

        // Then
        XCTAssertEqual(user.customerStatus, .subscriber)
        XCTAssertEqual(user.email, "ada@example.com")
    }

    func test_givenUnknownCustomerStatus_whenMapped_thenPreservedAsOther() {
        // Given / When
        let user = CurrentUser(from: makeUserDTO(customerStatus: "trialing"))

        // Then
        XCTAssertEqual(user.customerStatus, .other("trialing"))
        XCTAssertFalse(user.customerStatus.isSubscriber)
    }

    // MARK: FollowCounts (decision 0003 — App-layer Kit-import policy)

    func test_givenCountsDTO_whenMapped_thenFollowersAndFollowingArePreserved() {
        // Given
        let dto = FollowCountsDTO(followerCount: 12, followingCount: 7)

        // When
        let counts = FollowCounts(from: dto)

        // Then
        XCTAssertEqual(counts.followers, 12)
        XCTAssertEqual(counts.following, 7)
        // And the DTO-shaped aliases continue to read the same values, so
        // call sites that read `.followerCount` against the DTO compile
        // unchanged against the domain value.
        XCTAssertEqual(counts.followerCount, 12)
        XCTAssertEqual(counts.followingCount, 7)
    }

    func test_givenZeroedCountsDTO_whenMapped_thenMatchesZeroBoundary() {
        // Given — boundary: a brand-new account with no follow relationships.
        let dto = FollowCountsDTO(followerCount: 0, followingCount: 0)

        // When
        let counts = FollowCounts(from: dto)

        // Then
        XCTAssertEqual(counts, .zero)
    }

    // MARK: TimelinePage

    func test_givenPaginationHasMore_whenMapped_thenNextOffsetAdvances() {
        // Given
        let paginated = Paginated(
            items: [makeMessageDTO(id: "a")],
            pagination: PaginationInfo(total: 40, limit: 20, offset: 0, hasMore: true)
        )

        // When
        let page = TimelinePage(from: paginated)

        // Then
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextOffset, 20)
    }

    func test_givenPaginationNoMore_whenMapped_thenNextOffsetIsNil() {
        // Given
        let paginated = Paginated(
            items: [makeMessageDTO(id: "a")],
            pagination: PaginationInfo(total: 1, limit: 20, offset: 0, hasMore: false)
        )

        // When
        let page = TimelinePage(from: paginated)

        // Then
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
    }

    // MARK: - Builders

    private func makeMessageDTO(
        id: String = "m1",
        publiclyVisible: Bool = true,
        tags: [String]? = ["swift"],
        digCount: Int = 3,
        dugByMe: Bool = false,
        pushedMessage: PushedMessageBox? = nil,
        linkMetadata: LinkMetadataDTO? = nil
    ) -> MessageDTO {
        MessageDTO(
            id: id,
            content: "hello",
            publiclyVisible: publiclyVisible,
            userId: "u1",
            linkMetadata: linkMetadata,
            tags: tags,
            createdAt: date,
            updatedAt: date,
            digCount: digCount,
            pushCount: 1,
            user: UserSummaryDTO(id: "u1", username: "ada", displayName: "Ada", avatar: nil),
            pushedMessage: pushedMessage,
            dugByMe: dugByMe
        )
    }

    private func makeUserDTO(customerStatus: String) -> UserDTO {
        UserDTO(
            id: "u1",
            email: "ada@example.com",
            username: "ada",
            displayName: "Ada",
            emailVerified: true,
            customerStatus: customerStatus,
            createdAt: date
        )
    }

    // MARK: FollowAction mapper (FollowActionResponse → FollowAction)

    func test_givenActiveStatusInActionResponse_whenMappingFollowAction_thenReturnsApproved() {
        // Happy path: the action response carries `"active"` — follow is live.
        let dto = FollowActionResponse(follow: .init(status: "active"))

        let action = FollowAction(from: dto)

        XCTAssertEqual(action, .approved)
    }

    func test_givenPendingStatusInActionResponse_whenMappingFollowAction_thenReturnsPending() {
        // Private-account scenario: request is queued for approval.
        let dto = FollowActionResponse(follow: .init(status: "pending"))

        let action = FollowAction(from: dto)

        XCTAssertEqual(action, .pending)
    }

    func test_givenMissingFollowKeyInActionResponse_whenMappingFollowAction_thenDefaultsToPending() {
        // Boundary / nil case: `follow` is absent (e.g. unfollow/approve/reject
        // responses that omit the key). Conservative default is `.pending`.
        let dto = FollowActionResponse(follow: nil)

        let action = FollowAction(from: dto)

        XCTAssertEqual(action, .pending)
    }

    func test_givenUnknownStatusInActionResponse_whenMappingFollowAction_thenDefaultsToPending() {
        // Future-proofing: any unrecognised status string falls back to `.pending`
        // so the UI renders "Requested" rather than silently assuming approval.
        let dto = FollowActionResponse(follow: .init(status: "unknown_future_value"))

        let action = FollowAction(from: dto)

        XCTAssertEqual(action, .pending)
    }

    // MARK: - CrossPostResult mapper (NW-2)

    func test_givenOkStatus_whenMappingCrossPostResult_thenStatusIsOk() throws {
        let dto = CrossPostResultDTO(platform: "bluesky", providerId: nil, status: "ok", externalUrl: "https://bsky.app/p/123", error: nil)
        let result = CrossPostResult(from: dto)
        XCTAssertEqual(result.platform, "bluesky")
        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.externalURL?.absoluteString, "https://bsky.app/p/123")
    }

    func test_givenFailedStatusWithReason_whenMappingCrossPostResult_thenStatusIsFailedWithReason() throws {
        let dto = CrossPostResultDTO(platform: "mastodon", providerId: "ada@m.social", status: "failed", externalUrl: nil, error: "rate_limited")
        let result = CrossPostResult(from: dto)
        XCTAssertEqual(result.status, .failed("rate_limited"))
        XCTAssertEqual(result.providerId, "ada@m.social")
    }

    func test_givenPendingStatus_whenMappingCrossPostResult_thenStatusIsPending() throws {
        let dto = CrossPostResultDTO(platform: "linkedin", providerId: nil, status: "pending", externalUrl: nil, error: nil)
        let result = CrossPostResult(from: dto)
        XCTAssertEqual(result.status, .pending)
    }

    func test_givenUnknownStatus_whenMappingCrossPostResult_thenStatusIsUnknown() throws {
        let dto = CrossPostResultDTO(platform: "threads", providerId: nil, status: "queued", externalUrl: nil, error: nil)
        let result = CrossPostResult(from: dto)
        if case .unknown(let raw) = result.status {
            XCTAssertEqual(raw, "queued")
        } else {
            XCTFail("Expected .unknown, got \(result.status)")
        }
    }

    // MARK: - LinkPreview mapper (feature-gaps §1.5)

    // Happy path: a fully-resolved preview with every field populated maps to a
    // single renderable `LinkPreview` on the message.
    func test_givenMessageWithFullLinkMetadata_whenMapped_thenCarriesRenderablePreview() throws {
        // Given
        let link = LinkPreviewDTO(
            url: "https://example.com/article",
            platform: "web",
            fetchStatus: "ready",
            title: "A Great Article",
            description: "All about widgets.",
            imageUrl: "https://cdn.example.com/thumb.png"
        )
        let dto = makeMessageDTO(linkMetadata: LinkMetadataDTO(links: [link]))

        // When
        let message = Message(from: dto)

        // Then
        XCTAssertEqual(message.linkPreviews.count, 1)
        let preview = try XCTUnwrap(message.linkPreviews.first)
        XCTAssertEqual(preview.url, URL(string: "https://example.com/article"))
        XCTAssertEqual(preview.platform, "web")
        XCTAssertEqual(preview.fetchStatus, "ready")
        XCTAssertEqual(preview.title, "A Great Article")
        XCTAssertEqual(preview.description, "All about widgets.")
        XCTAssertEqual(preview.imageURL, URL(string: "https://cdn.example.com/thumb.png"))
        XCTAssertEqual(preview.displayHost, "example.com")
        XCTAssertTrue(preview.isRenderable)
    }

    // Boundary: a bare URL with no title / image / ready status still maps
    // (the URL parses) but is reported as not worth rendering, so the UI shows
    // no card for it.
    func test_givenMessageWithBareURLOnlyLink_whenMapped_thenPreviewMapsButIsNotRenderable() throws {
        // Given — nothing but a URL; fetch not (yet) resolved.
        let link = LinkPreviewDTO(url: "https://example.com/pending", fetchStatus: "pending")
        let dto = makeMessageDTO(linkMetadata: LinkMetadataDTO(links: [link]))

        // When
        let message = Message(from: dto)

        // Then
        XCTAssertEqual(message.linkPreviews.count, 1)
        let preview = try XCTUnwrap(message.linkPreviews.first)
        XCTAssertNil(preview.title)
        XCTAssertNil(preview.imageURL)
        XCTAssertFalse(preview.isFetchStatusReady)
        XCTAssertFalse(preview.isRenderable)
    }

    // Invalid input: an entry whose `url` will not parse is dropped by the
    // mapper's `compactMap`, while a sibling valid entry survives.
    func test_givenMessageWithUnparseableLinkURL_whenMapped_thenThatEntryIsDropped() throws {
        // Given — an empty-string URL cannot form a `URL`; a valid sibling can.
        let bad = LinkPreviewDTO(url: "", title: "Broken")
        let good = LinkPreviewDTO(url: "https://example.com/ok", title: "Good", imageUrl: nil)
        let dto = makeMessageDTO(linkMetadata: LinkMetadataDTO(links: [bad, good]))

        // When
        let message = Message(from: dto)

        // Then — only the parseable entry survives.
        XCTAssertEqual(message.linkPreviews.count, 1)
        XCTAssertEqual(message.linkPreviews.first?.url, URL(string: "https://example.com/ok"))
    }

    // Empty / boundary: no `linkMetadata` at all collapses to an empty array
    // (never `nil`), matching the `crossPostResults` default.
    func test_givenMessageWithNoLinkMetadata_whenMapped_thenLinkPreviewsAreEmpty() {
        // Given / When
        let message = Message(from: makeMessageDTO(linkMetadata: nil))

        // Then
        XCTAssertEqual(message.linkPreviews, [])
    }

    // Unparseable image only: the entry is kept (its `url` parses) with a nil
    // image, so the card degrades to a thumbnail-less preview rather than being
    // dropped. An empty-string `imageUrl` will not form a `URL`.
    func test_givenLinkWithUnparseableImageURL_whenMapped_thenPreviewKeptWithoutImage() throws {
        // Given
        let link = LinkPreviewDTO(
            url: "https://example.com/story",
            fetchStatus: "ready",
            title: "Story",
            imageUrl: ""   // empty — not a valid URL
        )
        let dto = makeMessageDTO(linkMetadata: LinkMetadataDTO(links: [link]))

        // When
        let preview = try XCTUnwrap(Message(from: dto).linkPreviews.first)

        // Then
        XCTAssertNil(preview.imageURL)
        XCTAssertTrue(preview.isRenderable)   // title alone is enough
    }

    // MARK: - LinkPreview display rules (feature-gaps §1.5)

    // A recognised success status renders even when title/image are absent —
    // the client is forward-compatible about which token means "ready".
    func test_givenReadyFetchStatusWithoutTitleOrImage_whenEvaluated_thenIsRenderable() {
        // Given
        let preview = LinkPreview(url: URL(string: "https://example.com")!, fetchStatus: "SUCCESS")

        // Then — case-insensitive match on a known success token.
        XCTAssertTrue(preview.isFetchStatusReady)
        XCTAssertTrue(preview.isRenderable)
    }

    // An image with no title still renders (image is a human-meaningful field).
    func test_givenImageOnlyPreview_whenEvaluated_thenIsRenderable() {
        // Given
        let preview = LinkPreview(
            url: URL(string: "https://example.com")!,
            imageURL: URL(string: "https://cdn.example.com/i.png")!
        )

        // Then
        XCTAssertTrue(preview.isRenderable)
    }

    // Whitespace-only title is treated as absent for rendering purposes.
    func test_givenWhitespaceOnlyTitleAndNoImage_whenEvaluated_thenIsNotRenderable() {
        // Given
        let preview = LinkPreview(url: URL(string: "https://example.com")!, title: "   ")

        // Then
        XCTAssertFalse(preview.isRenderable)
    }

    // `www.` is stripped from the display host; a URL without a host falls back
    // to the full string.
    func test_givenHostWithWWWPrefix_whenReadingDisplayHost_thenPrefixStripped() {
        // Given
        let preview = LinkPreview(url: URL(string: "https://www.example.com/x")!)

        // Then
        XCTAssertEqual(preview.displayHost, "example.com")
    }
}
