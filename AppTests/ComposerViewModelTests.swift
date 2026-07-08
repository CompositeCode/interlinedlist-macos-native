// ComposerViewModelTests
//
// BDD-named view-model tests for the M2 composer window. View-model
// only — no SwiftUI rendering exercised. The view model is tested
// against `StubMessagesService` and the real `ComposerEventBus` so
// the event-emission half of the contract is covered by an
// integration assertion (subscribe before submit, then iterate one
// event off the stream).
//
// Quartet per behaviour: happy path, invalid input, upstream API
// failure, empty / boundary.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ComposerViewModelTests: XCTestCase {

    // MARK: - submit (new post)

    func test_givenValidBody_whenSubmittingNewPost_thenCallsCreatePostAndPostsEvent() async throws {
        // Given — a new post now routes through the unified M6 `createPost`
        // write surface (a plain post sends empty media / schedule / cross-post
        // fields, which the domain treats exactly like the M2 `create`).
        let stub = StubMessagesService()
        let created = MessageFixtures.message(id: "m-new", text: "hello")
        await stub.enqueueCreatePost(success: created)
        let bus = ComposerEventBus()
        let viewModel = ComposerViewModel(messages: stub, eventBus: bus, mode: .newPost)
        viewModel.body = "hello"
        viewModel.visibility = .public

        // Subscribe before submit so we don't miss the emitted event.
        var iterator = bus.events().makeAsyncIterator()

        // When
        await viewModel.submit()

        // Then — the createPost call was issued with the typed body and no
        // M6 options for a plain post.
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1)
        if case .createPost(let body, let tags, let visibility, let imageURLs, let videoURLs, let scheduledAt, let mastodon, let bluesky, let linkedIn) = recorded.first?.kind {
            XCTAssertEqual(body, "hello")
            XCTAssertEqual(tags, [])
            XCTAssertEqual(visibility, .public)
            XCTAssertTrue(imageURLs.isEmpty)
            XCTAssertTrue(videoURLs.isEmpty)
            XCTAssertNil(scheduledAt)
            XCTAssertTrue(mastodon.isEmpty)
            XCTAssertFalse(bluesky)
            XCTAssertFalse(linkedIn)
        } else {
            XCTFail("Expected a `createPost` call, got \(String(describing: recorded.first))")
        }
        XCTAssertTrue(viewModel.didFinish)
        XCTAssertNil(viewModel.error)

        // And the event bus surfaced `.messageCreated`.
        let event = await iterator.next()
        if case .messageCreated(let message) = event {
            XCTAssertEqual(message.id, "m-new")
        } else {
            XCTFail("Expected `.messageCreated`, got \(String(describing: event))")
        }
    }

    func test_givenEmptyBody_whenSubmittingNewPost_thenNoCallIsMade() async {
        // Given — invalid input case: empty body.
        let stub = StubMessagesService()
        let bus = ComposerEventBus()
        let viewModel = ComposerViewModel(messages: stub, eventBus: bus, mode: .newPost)
        viewModel.body = "   "

        // When
        await viewModel.submit()

        // Then — guard bailed out; no call, no finish.
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
        XCTAssertFalse(viewModel.didFinish)
        XCTAssertFalse(viewModel.isPublishable)
    }

    func test_givenAPIFailure_whenSubmittingNewPost_thenSurfacesErrorAndDoesNotFinish() async {
        // Given — upstream API failure case on the unified createPost path.
        let stub = StubMessagesService()
        let failure = TestError.upstream("server down")
        await stub.enqueueCreatePost(failure: failure)
        let bus = ComposerEventBus()
        let viewModel = ComposerViewModel(messages: stub, eventBus: bus, mode: .newPost)
        viewModel.body = "hello"

        // When
        await viewModel.submit()

        // Then
        XCTAssertFalse(viewModel.didFinish)
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    func test_givenWhitespaceOnlyBody_whenSubmitting_thenBoundaryRefusalLeavesIsSubmittingFalse() async {
        // Given — boundary: only whitespace and a leading newline.
        let stub = StubMessagesService()
        let bus = ComposerEventBus()
        let viewModel = ComposerViewModel(messages: stub, eventBus: bus, mode: .newPost)
        viewModel.body = "\n  \t"

        // When
        await viewModel.submit()

        // Then
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertFalse(viewModel.didFinish)
    }

    // MARK: - submit (edit)

    func test_givenEditMode_whenSubmitting_thenCallsUpdateWithMessageId() async throws {
        // Given
        let original = MessageFixtures.message(id: "m-orig", text: "old", tags: ["swift"], visibility: .public)
        let stub = StubMessagesService()
        let updated = MessageFixtures.message(id: "m-orig", text: "new", tags: ["swift"], visibility: .private)
        await stub.enqueueUpdate(success: updated)
        let bus = ComposerEventBus()
        let viewModel = ComposerViewModel(
            messages: stub,
            eventBus: bus,
            mode: .edit(messageID: original.id, original: original)
        )

        // The view model pre-populates from the original; mutate the
        // typed values to simulate user edits.
        viewModel.body = "new"
        viewModel.visibility = .private

        var iterator = bus.events().makeAsyncIterator()

        // When
        await viewModel.submit()

        // Then
        let recorded = await stub.recorded
        if case .update(let id, let body, _, let visibility) = recorded.first?.kind {
            XCTAssertEqual(id, "m-orig")
            XCTAssertEqual(body, "new")
            XCTAssertEqual(visibility, .private)
        } else {
            XCTFail("Expected an `update` call, got \(String(describing: recorded.first))")
        }
        XCTAssertTrue(viewModel.didFinish)

        let event = await iterator.next()
        if case .messageUpdated(let message) = event {
            XCTAssertEqual(message.text, "new")
        } else {
            XCTFail("Expected `.messageUpdated`, got \(String(describing: event))")
        }
    }

    func test_givenEditAPIFailure_whenSubmitting_thenSurfacesError() async {
        // Given
        let original = MessageFixtures.message(id: "m-x")
        let stub = StubMessagesService()
        let failure = TestError.upstream("forbidden")
        await stub.enqueueUpdate(failure: failure)
        let viewModel = ComposerViewModel(
            messages: stub,
            eventBus: ComposerEventBus(),
            mode: .edit(messageID: original.id, original: original)
        )
        viewModel.body = "new body"

        // When
        await viewModel.submit()

        // Then
        XCTAssertFalse(viewModel.didFinish)
        XCTAssertEqual(viewModel.error as? TestError, failure)
    }

    // MARK: - Tag normalisation

    func test_givenCommaAndSpaceSeparated_whenNormalising_thenReturnsTokenList() {
        let tags = ComposerViewModel.normalise(tags: "swift, ios macos,, , swift")
        // Dedupes, preserves first-seen order.
        XCTAssertEqual(tags, ["swift", "ios", "macos"])
    }

    func test_givenHashPrefixedTags_whenNormalising_thenStripsHash() {
        let tags = ComposerViewModel.normalise(tags: "#swift #ios")
        XCTAssertEqual(tags, ["swift", "ios"])
    }

    func test_givenEmptyInput_whenNormalising_thenReturnsEmptyArray() {
        XCTAssertEqual(ComposerViewModel.normalise(tags: ""), [])
        XCTAssertEqual(ComposerViewModel.normalise(tags: "   \t  "), [])
    }

    // MARK: - M6 helpers

    /// A subscriber-entitled view model for the happy paths.
    private func subscriberViewModel(
        messages: StubMessagesService,
        bus: ComposerEventBus = ComposerEventBus(),
        readData: @escaping @Sendable (URL) async throws -> Data = { _ in Data([0x1]) },
        onSubscriberLapse: (@MainActor () async -> Void)? = nil
    ) -> ComposerViewModel {
        ComposerViewModel(
            messages: messages,
            eventBus: bus,
            mode: .newPost,
            entitlements: EntitlementsService(customerStatus: .subscriber),
            readData: readData,
            onSubscriberLapse: onSubscriberLapse
        )
    }

    private func imageURL() -> URL { URL(fileURLWithPath: "/tmp/test.png") }
    private func videoURL() -> URL { URL(fileURLWithPath: "/tmp/test.mp4") }

    // MARK: - M6 media attachments (happy path)

    func test_givenSubscriberWithImageAttachment_whenSubmitting_thenUploadsThenPostsWithURL() async throws {
        // Given — happy path: a subscriber attaches one image.
        let stub = StubMessagesService()
        await stub.enqueueUploadImage(success: "https://cdn/uploaded.png")
        await stub.enqueueCreatePost(success: MessageFixtures.message(id: "m-img"))
        let viewModel = subscriberViewModel(messages: stub)
        viewModel.body = "look"
        viewModel.addAttachments(urls: [imageURL()])

        // When
        await viewModel.submit()

        // Then — uploaded first, then createPost referenced the returned URL.
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 2)
        guard case .uploadImage = recorded[0].kind else {
            return XCTFail("Expected uploadImage first, got \(recorded[0].kind)")
        }
        if case .createPost(_, _, _, let imageURLs, let videoURLs, _, _, _, _) = recorded[1].kind {
            XCTAssertEqual(imageURLs, ["https://cdn/uploaded.png"])
            XCTAssertTrue(videoURLs.isEmpty)
        } else {
            XCTFail("Expected createPost, got \(recorded[1].kind)")
        }
        XCTAssertTrue(viewModel.didFinish)
        XCTAssertNil(viewModel.error)
    }

    func test_givenSubscriberWithVideoAttachment_whenSubmitting_thenUploadsVideoWithContentType() async throws {
        // Given — a subscriber attaches one video.
        let stub = StubMessagesService()
        await stub.enqueueUploadVideo(success: "https://cdn/uploaded.mp4")
        await stub.enqueueCreatePost(success: MessageFixtures.message(id: "m-vid"))
        let viewModel = subscriberViewModel(messages: stub, readData: { _ in Data(repeating: 0, count: 64) })
        viewModel.body = "watch"
        viewModel.addAttachments(urls: [videoURL()])

        // When
        await viewModel.submit()

        // Then
        let recorded = await stub.recorded
        if case .uploadVideo(_, let contentType) = recorded.first?.kind {
            XCTAssertEqual(contentType, "video/mp4")
        } else {
            XCTFail("Expected uploadVideo, got \(String(describing: recorded.first?.kind))")
        }
        if case .createPost(_, _, _, _, let videoURLs, _, _, _, _) = recorded.last?.kind {
            XCTAssertEqual(videoURLs, ["https://cdn/uploaded.mp4"])
        } else {
            XCTFail("Expected createPost, got \(String(describing: recorded.last?.kind))")
        }
        XCTAssertTrue(viewModel.didFinish)
    }

    // MARK: - M6 media (upstream upload failure → no createPost)

    func test_givenMediaTooLarge_whenSubmitting_thenSurfacesErrorAndDoesNotCreatePost() async throws {
        // Given — upstream API failure case: the upload throws mediaTooLarge.
        let stub = StubMessagesService()
        await stub.enqueueUploadVideo(failure: MessagesError.mediaTooLarge(byteCount: 9_000_000, limit: 3_145_728))
        let viewModel = subscriberViewModel(messages: stub, readData: { _ in Data(repeating: 0, count: 64) })
        viewModel.body = "watch"
        viewModel.addAttachments(urls: [videoURL()])

        // When
        await viewModel.submit()

        // Then — the failed upload aborts the post; createPost never ran.
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1)
        guard case .uploadVideo = recorded.first?.kind else {
            return XCTFail("Expected only the failed uploadVideo")
        }
        XCTAssertFalse(viewModel.didFinish)
        XCTAssertEqual(viewModel.error as? MessagesError, .mediaTooLarge(byteCount: 9_000_000, limit: 3_145_728))
    }

    // MARK: - M6 media (unsupported file — invalid input, no service call)

    func test_givenUnsupportedFile_whenAdding_thenSurfacesErrorAndQueuesNothing() async {
        // Given — invalid input: a non-media file is dropped.
        let stub = StubMessagesService()
        let viewModel = subscriberViewModel(messages: stub)

        // When
        viewModel.addAttachments(urls: [URL(fileURLWithPath: "/tmp/notes.txt")])

        // Then — nothing queued, error surfaced, no service call.
        XCTAssertTrue(viewModel.attachments.isEmpty)
        XCTAssertEqual(viewModel.error as? ComposerError, .unsupportedAttachment)
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - M6 scheduled-at wiring

    func test_givenScheduledPost_whenSubmitting_thenPassesScheduledAt() async throws {
        // Given — a subscriber schedules a future post.
        let stub = StubMessagesService()
        await stub.enqueueCreatePost(success: MessageFixtures.message(id: "m-sched"))
        let viewModel = subscriberViewModel(messages: stub)
        viewModel.body = "later"
        viewModel.isScheduled = true
        let when = Date().addingTimeInterval(7200)
        viewModel.scheduledAt = when

        // When
        await viewModel.submit()

        // Then
        let recorded = await stub.recorded
        if case .createPost(_, _, _, _, _, let scheduledAt, _, _, _) = recorded.first?.kind {
            XCTAssertEqual(scheduledAt, when)
        } else {
            XCTFail("Expected createPost with scheduledAt, got \(String(describing: recorded.first?.kind))")
        }
        XCTAssertTrue(viewModel.didFinish)
    }

    func test_givenScheduleToggledOn_whenLabelComputed_thenReadsSchedule() {
        let stub = StubMessagesService()
        let viewModel = subscriberViewModel(messages: stub)
        XCTAssertEqual(viewModel.publishButtonLabel, "Publish")
        viewModel.isScheduled = true
        XCTAssertEqual(viewModel.publishButtonLabel, "Schedule")
    }

    func test_givenPastScheduledDate_whenChecking_thenNotPublishable() {
        // Given — boundary: scheduling on with a past date is rejected.
        let stub = StubMessagesService()
        let viewModel = subscriberViewModel(messages: stub)
        viewModel.body = "later"
        viewModel.isScheduled = true
        viewModel.scheduledAt = Date().addingTimeInterval(-60)

        // Then
        XCTAssertFalse(viewModel.isPublishable)
    }

    // MARK: - M6 cross-post flag passthrough

    func test_givenCrossPostToggles_whenSubmitting_thenPassesFlagsAndProviderIds() async throws {
        // Given — a subscriber enables Mastodon (with ids), Bluesky, LinkedIn.
        let stub = StubMessagesService()
        await stub.enqueueCreatePost(success: MessageFixtures.message(id: "m-xpost"))
        let viewModel = subscriberViewModel(messages: stub)
        viewModel.body = "fan out"
        viewModel.crossPostToMastodon = true
        viewModel.mastodonProviderIdsInput = "p-1, p-2 p-2"
        viewModel.crossPostToBluesky = true
        viewModel.crossPostToLinkedIn = true

        // When
        await viewModel.submit()

        // Then
        let recorded = await stub.recorded
        if case .createPost(_, _, _, _, _, _, let mastodon, let bluesky, let linkedIn) = recorded.first?.kind {
            XCTAssertEqual(mastodon, ["p-1", "p-2"]) // deduped, order preserved
            XCTAssertTrue(bluesky)
            XCTAssertTrue(linkedIn)
        } else {
            XCTFail("Expected createPost, got \(String(describing: recorded.first?.kind))")
        }
        XCTAssertTrue(viewModel.didFinish)
    }

    func test_givenMastodonToggledOff_whenSubmitting_thenSendsNoProviderIds() async throws {
        // Given — boundary: provider-id text present but the Mastodon toggle
        // is off, so the ids must NOT be sent.
        let stub = StubMessagesService()
        await stub.enqueueCreatePost(success: MessageFixtures.message(id: "m-off"))
        let viewModel = subscriberViewModel(messages: stub)
        viewModel.body = "hello"
        viewModel.crossPostToMastodon = false
        viewModel.mastodonProviderIdsInput = "p-1 p-2"

        // When
        await viewModel.submit()

        // Then
        let recorded = await stub.recorded
        if case .createPost(_, _, _, _, _, _, let mastodon, _, _) = recorded.first?.kind {
            XCTAssertTrue(mastodon.isEmpty)
        } else {
            XCTFail("Expected createPost, got \(String(describing: recorded.first?.kind))")
        }
    }

    // MARK: - M6 gating (non-subscriber)

    func test_givenNonSubscriber_whenInspectingControls_thenSubscriberFeaturesDisabled() {
        // Given — a free account.
        let stub = StubMessagesService()
        let viewModel = ComposerViewModel(
            messages: stub,
            eventBus: ComposerEventBus(),
            mode: .newPost,
            entitlements: EntitlementsService(customerStatus: .free)
        )

        // Then — the UI gate hides the capability (controls render disabled).
        XCTAssertTrue(viewModel.showsSubscriberControls)
        XCTAssertFalse(viewModel.canUseSubscriberFeatures)
    }

    func test_givenNonSubscriber_whenAddingAttachment_thenRejectedWithSubscriberRequired() async {
        // Given — invalid input: a free account tries to attach media.
        let stub = StubMessagesService()
        let viewModel = ComposerViewModel(
            messages: stub,
            eventBus: ComposerEventBus(),
            mode: .newPost,
            entitlements: EntitlementsService(customerStatus: .free)
        )

        // When
        viewModel.addAttachments(urls: [imageURL()])

        // Then — nothing queued, gated error, no service call.
        XCTAssertTrue(viewModel.attachments.isEmpty)
        XCTAssertEqual(viewModel.error as? MessagesError, .subscriberRequired(.mediaAttachments))
        let recorded = await stub.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenNonSubscriberPlainPost_whenSubmitting_thenStillPostsViaCreatePost() async throws {
        // Given — a free account posting plain text (no gated options): the
        // domain createPost is ungated for a plain post, so it should succeed.
        let stub = StubMessagesService()
        await stub.enqueueCreatePost(success: MessageFixtures.message(id: "m-plain"))
        let viewModel = ComposerViewModel(
            messages: stub,
            eventBus: ComposerEventBus(),
            mode: .newPost,
            entitlements: EntitlementsService(customerStatus: .free)
        )
        viewModel.body = "just text"

        // When
        await viewModel.submit()

        // Then
        let recorded = await stub.recorded
        XCTAssertEqual(recorded.count, 1)
        guard case .createPost = recorded.first?.kind else {
            return XCTFail("Expected createPost, got \(String(describing: recorded.first?.kind))")
        }
        XCTAssertTrue(viewModel.didFinish)
    }

    // MARK: - M6 subscriber-lapse refresh hook (PLAN.md §8)

    func test_givenGatedCreatePostReturns403_whenSubmitting_thenInvokesLapseRefresh() async {
        // Given — a subscriber whose subscription lapsed server-side: createPost
        // returns a subscriber-required domain error mid-flow.
        let stub = StubMessagesService()
        await stub.enqueueCreatePost(failure: MessagesError.subscriberRequired(.crossPosting))
        let refreshed = RefreshSpy()
        let viewModel = subscriberViewModel(
            messages: stub,
            onSubscriberLapse: { await refreshed.mark() }
        )
        viewModel.body = "fan out"
        viewModel.crossPostToBluesky = true

        // When
        await viewModel.submit()

        // Then — the error surfaced and the re-gate hook fired.
        XCTAssertFalse(viewModel.didFinish)
        XCTAssertEqual(viewModel.error as? MessagesError, .subscriberRequired(.crossPosting))
        let didRefresh = await refreshed.didRefresh
        XCTAssertTrue(didRefresh)
    }

    func test_givenOrdinaryFailure_whenSubmitting_thenDoesNotInvokeLapseRefresh() async {
        // Given — a plain server error that is not a subscription lapse.
        let stub = StubMessagesService()
        await stub.enqueueCreatePost(failure: TestError.upstream("network down"))
        let refreshed = RefreshSpy()
        let viewModel = subscriberViewModel(
            messages: stub,
            onSubscriberLapse: { await refreshed.mark() }
        )
        viewModel.body = "hello"

        // When
        await viewModel.submit()

        // Then — error surfaced, but no re-gate refresh for a non-lapse error.
        XCTAssertEqual(viewModel.error as? TestError, .upstream("network down"))
        let didRefresh = await refreshed.didRefresh
        XCTAssertFalse(didRefresh)
    }

    // MARK: - crossPostResults (NW-2)

    func test_givenCrossPostResults_whenPostSucceeds_thenSetsCrossPostResultsState() async {
        let stub = StubMessagesService()
        let crossResult = CrossPostResult(platform: "bluesky", providerId: nil, status: .ok, externalURL: nil)
        let created = Message(
            id: "m-x",
            author: MessageFixtures.author(),
            text: "hello",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [],
            visibility: .public,
            digCount: 0,
            didDig: false,
            repostCount: 0,
            replyCount: nil,
            parentID: nil,
            repost: nil,
            scheduledAt: nil,
            crossPostResults: [crossResult]
        )
        await stub.enqueueCreatePost(success: created)
        let viewModel = ComposerViewModel(messages: stub, eventBus: ComposerEventBus())
        viewModel.body = "hello"

        await viewModel.submit()

        XCTAssertEqual(viewModel.crossPostResults?.count, 1)
        XCTAssertEqual(viewModel.crossPostResults?.first?.platform, "bluesky")
        XCTAssertTrue(viewModel.didFinish)
    }

    func test_givenNoCrossPostResults_whenPostSucceeds_thenCrossPostResultsRemainsNil() async {
        let stub = StubMessagesService()
        let created = Message(
            id: "m-y",
            author: MessageFixtures.author(),
            text: "hello",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [],
            visibility: .public,
            digCount: 0,
            didDig: false,
            repostCount: 0,
            replyCount: nil,
            parentID: nil,
            repost: nil,
            scheduledAt: nil,
            crossPostResults: []
        )
        await stub.enqueueCreatePost(success: created)
        let viewModel = ComposerViewModel(messages: stub, eventBus: ComposerEventBus())
        viewModel.body = "hello"

        await viewModel.submit()

        XCTAssertNil(viewModel.crossPostResults)
        XCTAssertTrue(viewModel.didFinish)
    }

    func test_givenCrossPostResultsSet_whenDismissed_thenBecomesNil() async {
        let stub = StubMessagesService()
        let crossResult = CrossPostResult(platform: "bluesky", providerId: nil, status: .ok, externalURL: nil)
        let created = Message(
            id: "m-z",
            author: MessageFixtures.author(),
            text: "hello",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [],
            visibility: .public,
            digCount: 0,
            didDig: false,
            repostCount: 0,
            replyCount: nil,
            parentID: nil,
            repost: nil,
            scheduledAt: nil,
            crossPostResults: [crossResult]
        )
        await stub.enqueueCreatePost(success: created)
        let viewModel = ComposerViewModel(messages: stub, eventBus: ComposerEventBus())
        viewModel.body = "hello"
        await viewModel.submit()
        XCTAssertNotNil(viewModel.crossPostResults)

        viewModel.dismissCrossPostResults()

        XCTAssertNil(viewModel.crossPostResults)
    }

    // MARK: - setBlueskyEnabled / setMastodonEnabled (NW-4)

    func test_givenBlueskyConfigured_whenEnablingBluesky_thenToggleRemainsEnabled() async {
        let stub = StubMessagesService()
        let users = StubUserService()
        users.enqueueBlueskyConfigured(success: true)
        let viewModel = ComposerViewModel(messages: stub, eventBus: ComposerEventBus(), userService: users)

        await viewModel.setBlueskyEnabled(true)

        XCTAssertTrue(viewModel.crossPostToBluesky)
        XCTAssertFalse(viewModel.blueskyNotConfigured)
    }

    func test_givenBlueskyNotConfigured_whenEnablingBluesky_thenDisablesToggleAndSetsFlag() async {
        let stub = StubMessagesService()
        let users = StubUserService()
        users.enqueueBlueskyConfigured(success: false)
        let viewModel = ComposerViewModel(messages: stub, eventBus: ComposerEventBus(), userService: users)

        await viewModel.setBlueskyEnabled(true)

        XCTAssertFalse(viewModel.crossPostToBluesky)
        XCTAssertTrue(viewModel.blueskyNotConfigured)
    }

    func test_givenDisableBluesky_whenCalledWithFalse_thenNoServiceCallMade() async {
        let stub = StubMessagesService()
        let users = StubUserService()
        let viewModel = ComposerViewModel(messages: stub, eventBus: ComposerEventBus(), userService: users)

        await viewModel.setBlueskyEnabled(false)

        // No blueskyConfigured call should have been made when disabling.
        XCTAssertFalse(viewModel.crossPostToBluesky)
        XCTAssertFalse(viewModel.blueskyNotConfigured)
        XCTAssertEqual(users.recorded.filter { $0.kind == .blueskyConfigured }.count, 0)
    }

    func test_givenMastodonNotConfigured_whenEnablingMastodon_thenDisablesAndSetsFlag() async {
        let stub = StubMessagesService()
        let users = StubUserService()
        users.enqueueMastodonConfigured(success: false)
        let viewModel = ComposerViewModel(messages: stub, eventBus: ComposerEventBus(), userService: users)
        viewModel.mastodonProviderIdsInput = "mastodon.social"

        await viewModel.setMastodonEnabled(true)

        XCTAssertFalse(viewModel.crossPostToMastodon)
        XCTAssertTrue(viewModel.mastodonNotConfigured)
    }

    func test_givenMastodonConfigured_whenEnablingMastodon_thenToggleRemainsEnabled() async {
        // Happy path: server confirms the instance is configured.
        let stub = StubMessagesService()
        let users = StubUserService()
        users.enqueueMastodonConfigured(success: true)
        let viewModel = ComposerViewModel(messages: stub, eventBus: ComposerEventBus(), userService: users)
        viewModel.mastodonProviderIdsInput = "mastodon.social"

        await viewModel.setMastodonEnabled(true)

        XCTAssertTrue(viewModel.crossPostToMastodon)
        XCTAssertFalse(viewModel.mastodonNotConfigured)
    }

    func test_givenBlueskyConfiguredCheckFails_whenEnablingBluesky_thenNonFatalAndToggleStaysEnabled() async {
        // Upstream API failure: the check throws but the toggle must remain
        // enabled (non-fatal per the view model's catch — the server may be
        // temporarily unreachable).
        let stub = StubMessagesService()
        let users = StubUserService()
        users.enqueueBlueskyConfigured(failure: StubUserService.StubUserError.noOutcome(label: "blueskyConfigured"))
        let viewModel = ComposerViewModel(messages: stub, eventBus: ComposerEventBus(), userService: users)

        await viewModel.setBlueskyEnabled(true)

        // Toggle stays on; the hint flag must NOT be set for a transient error.
        XCTAssertTrue(viewModel.crossPostToBluesky)
        XCTAssertFalse(viewModel.blueskyNotConfigured)
    }

    func test_givenMastodonConfiguredCheckFails_whenEnablingMastodon_thenNonFatalAndToggleStaysEnabled() async {
        // Upstream API failure: same non-fatal policy applies to Mastodon.
        let stub = StubMessagesService()
        let users = StubUserService()
        users.enqueueMastodonConfigured(failure: StubUserService.StubUserError.noOutcome(label: "mastodonConfigured"))
        let viewModel = ComposerViewModel(messages: stub, eventBus: ComposerEventBus(), userService: users)
        viewModel.mastodonProviderIdsInput = "mastodon.social"

        await viewModel.setMastodonEnabled(true)

        XCTAssertTrue(viewModel.crossPostToMastodon)
        XCTAssertFalse(viewModel.mastodonNotConfigured)
    }

    func test_givenNoUserService_whenEnablingBluesky_thenToggleEnabledWithNoCheck() async {
        // Boundary: no userService injected (e.g. a test host that omits it).
        // The toggle should set to true without performing a network check.
        let stub = StubMessagesService()
        let viewModel = ComposerViewModel(messages: stub, eventBus: ComposerEventBus(), userService: nil)

        await viewModel.setBlueskyEnabled(true)

        XCTAssertTrue(viewModel.crossPostToBluesky)
        XCTAssertFalse(viewModel.blueskyNotConfigured)
    }

    func test_givenNoUserService_whenEnablingMastodon_thenToggleEnabledWithNoCheck() async {
        // Boundary: same nil-userService guard for Mastodon.
        let stub = StubMessagesService()
        let viewModel = ComposerViewModel(messages: stub, eventBus: ComposerEventBus(), userService: nil)
        viewModel.mastodonProviderIdsInput = "mastodon.social"

        await viewModel.setMastodonEnabled(true)

        XCTAssertTrue(viewModel.crossPostToMastodon)
        XCTAssertFalse(viewModel.mastodonNotConfigured)
    }
}

/// Spy that records whether the subscriber-lapse refresh hook fired.
private actor RefreshSpy {
    private(set) var didRefresh = false
    func mark() { didRefresh = true }
}
