import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for the `MessagesService` M6 write surface (PLAN.md §6
/// M6 — "Subscriber & orgs", §8 entitlement gating, §7 testing). The M2
/// surface and its tests in `MessagesServiceTests` are unchanged; this suite
/// covers only the additive M6 methods.
///
/// Quartet per behavior (happy / invalid input / API failure / boundary), plus
/// the required entitlement-gate "no service call" assertions: every gated
/// path must throw `MessagesError.subscriberRequired` *before* any HTTP call,
/// asserted via `recorded.isEmpty`.
final class MessagesServiceM6Tests: XCTestCase {

    /// A service whose entitlements grant every subscriber feature.
    private func subscriberService(_ api: StubAPIClient) -> MessagesService {
        MessagesService(api: api, entitlements: EntitlementsService(customerStatus: .subscriber))
    }

    /// A service whose entitlements grant nothing (free account).
    private func freeService(_ api: StubAPIClient) -> MessagesService {
        MessagesService(api: api, entitlements: EntitlementsService(customerStatus: .free))
    }

    // MARK: - createPost (plain — ungated)

    func test_givenPlainTextPost_whenCreating_thenPostsRegardlessOfEntitlement() async throws {
        // Given — a free account creating a plain post (no media/schedule/cross-post).
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "m-1", content: "hello"))
        let service = freeService(api)

        // When
        let message = try await service.createPost(
            body: "hello", tags: [], visibility: .public,
            imageURLs: [], videoURLs: [], scheduledAt: nil,
            mastodonProviderIds: [], crossPostToBluesky: false, crossPostToLinkedIn: false
        )

        // Then — the post is created; no gate fires for a plain post.
        XCTAssertEqual(message.id, "m-1")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/messages")
    }

    // MARK: - createPost media gate

    func test_givenSubscriberWithImages_whenCreating_thenPostsWithMedia() async throws {
        // Given — happy path: subscriber attaches media.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "m-2"))
        let service = subscriberService(api)

        // When
        let message = try await service.createPost(
            body: "look", tags: [], visibility: .public,
            imageURLs: ["https://cdn/a.png"], videoURLs: [], scheduledAt: nil,
            mastodonProviderIds: [], crossPostToBluesky: false, crossPostToLinkedIn: false
        )

        // Then
        XCTAssertEqual(message.id, "m-2")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    func test_givenFreeAccountWithImages_whenCreating_thenThrowsSubscriberRequiredBeforeCall() async throws {
        // Given — invalid (un-entitled) input: free account attaching media.
        let api = StubAPIClient()
        let service = freeService(api)

        // When / Then
        do {
            _ = try await service.createPost(
                body: "look", tags: [], visibility: .public,
                imageURLs: ["https://cdn/a.png"], videoURLs: [], scheduledAt: nil,
                mastodonProviderIds: [], crossPostToBluesky: false, crossPostToLinkedIn: false
            )
            XCTFail("Expected MessagesError.subscriberRequired")
        } catch let error as MessagesError {
            XCTAssertEqual(error, .subscriberRequired(.mediaAttachments))
        }
        // And — the gate fired before any HTTP call.
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "Gated create must not hit the API.")
    }

    // MARK: - createPost scheduled gate

    func test_givenSubscriberSchedulingPost_whenCreating_thenPostsScheduledAndDoesNotCache() async throws {
        // Given — happy path: subscriber schedules a post.
        let api = StubAPIClient()
        let store = InMemoryMessageStore()
        await api.enqueue(json: Fixtures.messageObject(id: "m-3", scheduledAt: "2026-07-01T09:00:00Z"))
        let service = MessagesService(
            api: api, store: store, entitlements: EntitlementsService(customerStatus: .subscriber)
        )
        let when = Date(timeIntervalSince1970: 1_800_000_000)

        // When
        let message = try await service.createPost(
            body: "later", tags: [], visibility: .public,
            imageURLs: [], videoURLs: [], scheduledAt: when,
            mastodonProviderIds: [], crossPostToBluesky: false, crossPostToLinkedIn: false
        )

        // Then — created, but not written to the by-id cache (not yet published).
        XCTAssertEqual(message.id, "m-3")
        let cached = await store.cachedMessage(id: "m-3")
        XCTAssertNil(cached, "A scheduled post must not be cached as a published message.")
    }

    func test_givenFreeAccountSchedulingPost_whenCreating_thenThrowsSubscriberRequiredBeforeCall() async throws {
        // Given — un-entitled: free account schedules.
        let api = StubAPIClient()
        let service = freeService(api)

        // When / Then
        do {
            _ = try await service.createPost(
                body: "later", tags: [], visibility: .public,
                imageURLs: [], videoURLs: [], scheduledAt: Date(),
                mastodonProviderIds: [], crossPostToBluesky: false, crossPostToLinkedIn: false
            )
            XCTFail("Expected MessagesError.subscriberRequired")
        } catch let error as MessagesError {
            XCTAssertEqual(error, .subscriberRequired(.scheduledPosts))
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - createPost cross-post gate

    func test_givenFreeAccountCrossPosting_whenCreating_thenThrowsSubscriberRequiredBeforeCall() async throws {
        // Given — un-entitled: free account requests Bluesky cross-post.
        let api = StubAPIClient()
        let service = freeService(api)

        // When / Then
        do {
            _ = try await service.createPost(
                body: "fan out", tags: [], visibility: .public,
                imageURLs: [], videoURLs: [], scheduledAt: nil,
                mastodonProviderIds: [], crossPostToBluesky: true, crossPostToLinkedIn: false
            )
            XCTFail("Expected MessagesError.subscriberRequired")
        } catch let error as MessagesError {
            XCTAssertEqual(error, .subscriberRequired(.crossPosting))
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenSubscriberCrossPostingToMastodon_whenCreating_thenPosts() async throws {
        // Given — happy path: subscriber fans out to Mastodon instances.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "m-4"))
        let service = subscriberService(api)

        // When
        let message = try await service.createPost(
            body: "fan out", tags: [], visibility: .public,
            imageURLs: [], videoURLs: [], scheduledAt: nil,
            mastodonProviderIds: ["p-1", "p-2"], crossPostToBluesky: false, crossPostToLinkedIn: true
        )

        // Then
        XCTAssertEqual(message.id, "m-4")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    // MARK: - createPost API failure + boundary

    func test_givenCreatePostUpstreamFails_whenCreating_thenSurfacesAPIError() async throws {
        // Given — upstream API failure after the gate passes.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = subscriberService(api)

        // When / Then
        do {
            _ = try await service.createPost(
                body: "look", tags: [], visibility: .public,
                imageURLs: ["https://cdn/a.png"], videoURLs: [], scheduledAt: nil,
                mastodonProviderIds: [], crossPostToBluesky: false, crossPostToLinkedIn: false
            )
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    func test_givenEmptyBodyPlainPost_whenCreating_thenStillPosts() async throws {
        // Given — boundary: empty body (a bare repost-style post). Ungated.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "m-5", content: ""))
        let service = freeService(api)

        // When
        let message = try await service.createPost(
            body: "", tags: [], visibility: .public,
            imageURLs: [], videoURLs: [], scheduledAt: nil,
            mastodonProviderIds: [], crossPostToBluesky: false, crossPostToLinkedIn: false
        )

        // Then
        XCTAssertEqual(message.id, "m-5")
        XCTAssertEqual(message.text, "")
    }

    // MARK: - scheduledPosts (read, ungated)

    func test_givenScheduledPosts_whenLoading_thenMapsMessagesWithScheduledAt() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.scheduledMessagesEnvelope(ids: ["s-1", "s-2"]))
        let service = freeService(api)

        // When
        let posts = try await service.scheduledPosts()

        // Then
        XCTAssertEqual(posts.map(\.id), ["s-1", "s-2"])
        XCTAssertNotNil(posts.first?.scheduledAt)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/messages/scheduled")
    }

    func test_givenMalformedScheduledEnvelope_whenLoading_thenThrowsDecoding() async throws {
        // Given — invalid input: missing `messages` key.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"items":[]}"#)
        let service = freeService(api)

        // When / Then
        do {
            _ = try await service.scheduledPosts()
            XCTFail("Expected an APIError.decoding")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("Expected .decoding, got \(error)") }
        }
    }

    func test_givenScheduledEndpointFails_whenLoading_thenThrows() async throws {
        // Given — upstream API failure.
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "subscriber only"))
        let service = freeService(api)

        // When / Then
        do {
            _ = try await service.scheduledPosts()
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "subscriber only"))
        }
    }

    func test_givenNoScheduledPosts_whenLoading_thenReturnsEmpty() async throws {
        // Given — boundary: nothing scheduled.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.scheduledMessagesEnvelope(ids: []))
        let service = freeService(api)

        // When
        let posts = try await service.scheduledPosts()

        // Then
        XCTAssertTrue(posts.isEmpty)
    }

    // MARK: - uploadImage

    func test_givenSubscriberAndValidImage_whenUploading_thenPreparesAndReturnsURL() async throws {
        // Given — happy path: a tiny valid PNG, subscriber account.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.mediaUploadResponse(url: "https://cdn/uploaded.png"))
        let service = subscriberService(api)

        // When
        let url = try await service.uploadImage(Fixtures.tinyPNGData)

        // Then
        XCTAssertEqual(url, "https://cdn/uploaded.png")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/messages/images/upload")
    }

    func test_givenFreeAccount_whenUploadingImage_thenThrowsSubscriberRequiredBeforePrep() async throws {
        // Given — un-entitled: free account uploads. Gate fires before prep + HTTP.
        let api = StubAPIClient()
        let service = freeService(api)

        // When / Then
        do {
            _ = try await service.uploadImage(Fixtures.tinyPNGData)
            XCTFail("Expected MessagesError.subscriberRequired")
        } catch let error as MessagesError {
            XCTAssertEqual(error, .subscriberRequired(.mediaAttachments))
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "Gated upload must not hit the API.")
    }

    func test_givenUndecodableImageBytes_whenUploading_thenThrowsImagePrepError() async throws {
        // Given — invalid input: bytes that are not an image. Gate passes; prep fails.
        let api = StubAPIClient()
        let service = subscriberService(api)

        // When / Then
        do {
            _ = try await service.uploadImage(Data("not an image".utf8))
            XCTFail("Expected ImagePrepError")
        } catch let error as ImagePrepError {
            XCTAssertEqual(error, .undecodable)
        }
        // No upload happened — prep threw first.
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenImageUploadUpstreamFails_whenUploading_thenSurfacesAPIError() async throws {
        // Given — boundary: prep succeeds, the upload itself fails upstream.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 413, serverMessage: "too large"))
        let service = subscriberService(api)

        // When / Then
        do {
            _ = try await service.uploadImage(Fixtures.tinyPNGData)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 413, serverMessage: "too large"))
        }
    }

    // MARK: - uploadVideo

    func test_givenSubscriberAndInBudgetVideo_whenUploading_thenReturnsURL() async throws {
        // Given — happy path: small video under the 3 MB budget.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.mediaUploadResponse(url: "https://cdn/uploaded.mp4"))
        let service = subscriberService(api)
        let bytes = Data(repeating: 0, count: 1_024) // 1 KB

        // When
        let url = try await service.uploadVideo(bytes, contentType: "video/mp4")

        // Then
        XCTAssertEqual(url, "https://cdn/uploaded.mp4")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/messages/videos/upload")
    }

    func test_givenFreeAccount_whenUploadingVideo_thenThrowsSubscriberRequiredBeforeCall() async throws {
        // Given — un-entitled: gate fires before the budget check + HTTP.
        let api = StubAPIClient()
        let service = freeService(api)

        // When / Then
        do {
            _ = try await service.uploadVideo(Data(repeating: 0, count: 1_024), contentType: "video/mp4")
            XCTFail("Expected MessagesError.subscriberRequired")
        } catch let error as MessagesError {
            XCTAssertEqual(error, .subscriberRequired(.mediaAttachments))
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenOversizeVideo_whenUploading_thenThrowsMediaTooLargeBeforeCall() async throws {
        // Given — invalid input: a subscriber's video exceeds the 3 MB budget.
        let api = StubAPIClient()
        let service = subscriberService(api)
        let oversize = Data(repeating: 0, count: MessagesService.maxVideoBytes + 1)

        // When / Then
        do {
            _ = try await service.uploadVideo(oversize, contentType: "video/mp4")
            XCTFail("Expected MessagesError.mediaTooLarge")
        } catch let error as MessagesError {
            XCTAssertEqual(error, .mediaTooLarge(byteCount: oversize.count, limit: MessagesService.maxVideoBytes))
        }
        // And — never shipped the oversize bytes.
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenVideoExactlyAtLimit_whenUploading_thenSucceeds() async throws {
        // Given — boundary: a video exactly at the budget is accepted.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.mediaUploadResponse(url: "https://cdn/edge.mp4"))
        let service = subscriberService(api)
        let atLimit = Data(repeating: 0, count: MessagesService.maxVideoBytes)

        // When
        let url = try await service.uploadVideo(atLimit, contentType: "video/mp4")

        // Then
        XCTAssertEqual(url, "https://cdn/edge.mp4")
    }

    // MARK: - Entitlements provider (Deliverable B — live gating, PLAN.md §8)
    //
    // The App composition root injects a `@Sendable` provider closure that
    // reads the *current* user's entitlements so the domain backstop tracks the
    // live `customerStatus` rather than a snapshot taken at construction. These
    // assert the provider is consulted at call time, and that a subscriber is
    // not wrongly blocked even when the service outlives the moment sign-in
    // resolved.

    func test_givenSubscriberProvider_whenCreatingWithMedia_thenPosts() async throws {
        // Given — the provider closure resolves to a subscriber.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "m-prov-sub"))
        let service = MessagesService(
            api: api,
            entitlementsProvider: { EntitlementsService(customerStatus: .subscriber) }
        )

        // When
        let message = try await service.createPost(
            body: "look", tags: [], visibility: .public,
            imageURLs: ["https://cdn/a.png"], videoURLs: [], scheduledAt: nil,
            mastodonProviderIds: [], crossPostToBluesky: false, crossPostToLinkedIn: false
        )

        // Then — the live provider grants media, so the post is created.
        XCTAssertEqual(message.id, "m-prov-sub")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    func test_givenFreeProvider_whenCreatingWithMedia_thenThrowsSubscriberRequiredBeforeCall() async throws {
        // Given — the provider closure resolves to a free account.
        let api = StubAPIClient()
        let service = MessagesService(
            api: api,
            entitlementsProvider: { EntitlementsService(customerStatus: .free) }
        )

        // When / Then
        do {
            _ = try await service.createPost(
                body: "look", tags: [], visibility: .public,
                imageURLs: ["https://cdn/a.png"], videoURLs: [], scheduledAt: nil,
                mastodonProviderIds: [], crossPostToBluesky: false, crossPostToLinkedIn: false
            )
            XCTFail("Expected MessagesError.subscriberRequired")
        } catch let error as MessagesError {
            XCTAssertEqual(error, .subscriberRequired(.mediaAttachments))
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "Gated create must not hit the API.")
    }

    func test_givenProviderThatFlipsToSubscriber_whenCreating_thenGateReflectsLiveValue() async throws {
        // Given — a provider whose backing status starts free and later flips
        // to subscriber (the production scenario: sign-in resolves *after* the
        // service is built). The gate must read the live value each call.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.messageObject(id: "m-flip"))
        let status = StatusBox(.free)
        let service = MessagesService(
            api: api,
            entitlementsProvider: { EntitlementsService(customerStatus: status.value) }
        )

        // When — first call while still free is blocked before any HTTP call.
        do {
            _ = try await service.createPost(
                body: "later", tags: [], visibility: .public,
                imageURLs: [], videoURLs: [], scheduledAt: Date(),
                mastodonProviderIds: [], crossPostToBluesky: false, crossPostToLinkedIn: false
            )
            XCTFail("Expected MessagesError.subscriberRequired while free")
        } catch let error as MessagesError {
            XCTAssertEqual(error, .subscriberRequired(.scheduledPosts))
        }
        var recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)

        // Flip the live account to subscriber.
        status.value = .subscriber

        // Then — the same gated call now passes because the provider re-reads.
        let message = try await service.createPost(
            body: "later", tags: [], visibility: .public,
            imageURLs: [], videoURLs: [], scheduledAt: Date(),
            mastodonProviderIds: [], crossPostToBluesky: false, crossPostToLinkedIn: false
        )
        XCTAssertEqual(message.id, "m-flip")
        recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1)
    }
}

/// Mutable, `@Sendable`-usable box so a test can flip the live status the
/// provider closure reads. Lock-guarded for strict-concurrency safety.
private final class StatusBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: CustomerStatus
    init(_ value: CustomerStatus) { self._value = value }
    var value: CustomerStatus {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}
