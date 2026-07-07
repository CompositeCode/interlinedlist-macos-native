// StubMessagesService
//
// Deterministic `MessagesServicing` stub for App-layer view-model
// tests. Mirrors the kit / domain stub style (an `actor` for Swift 6
// strict-concurrency safety) at the `MessagesServicing` seam the
// view models actually depend on, rather than at the HTTP boundary.
//
// Each write entry point pops its next queued outcome (a queued
// success `Message` or an `Error`) and records the request shape so
// tests can assert it routed correctly. Read entry points (`message`,
// `replies`, `timeline*`) are unused by the M2 view-model tests and
// throw a "not enqueued" error if called — keeping the surface
// honest for the few tests that do exercise the read paths.

import Foundation
import InterlinedDomain

/// Records one outbound write so a test can assert on intent.
struct RecordedMessagesCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case timeline(scope: TimelineScope, tag: String?, limit: Int, offset: Int)
        case timelineStream(scope: TimelineScope, tag: String?, limit: Int, offset: Int)
        case message(id: String)
        case replies(of: String, limit: Int, offset: Int)
        case create(body: String, parentId: String?, tags: [String], visibility: Visibility, pushedMessageId: String?)
        case reply(to: String, body: String, tags: [String], visibility: Visibility)
        case repost(messageId: String, commentary: String?, visibility: Visibility)
        case update(messageId: String, body: String, tags: [String], visibility: Visibility)
        case delete(messageId: String)
        case dig(messageId: String)
        case undig(messageId: String)
        // M6 write surface (additive — see the M6 conformance block below).
        case createPost(body: String, tags: [String], visibility: Visibility, imageURLs: [String], videoURLs: [String], scheduledAt: Date?, mastodonProviderIds: [String], crossPostToBluesky: Bool, crossPostToLinkedIn: Bool)
        case scheduledPosts
        case uploadImage(byteCount: Int)
        case uploadVideo(byteCount: Int, contentType: String)
        case cancelScheduled(messageId: String)
        case reschedule(messageId: String, newDate: Date)
    }
    let kind: Kind
}

/// Test double for `MessagesServicing`. Each call type has its own
/// independent FIFO outcome queue so tests can pre-stage exactly the
/// responses they need without ordering coupling.
actor StubMessagesService: MessagesServicing {

    // MARK: Outcome queues

    private var createOutcomes: [Result<Message, Error>] = []
    private var replyOutcomes: [Result<Message, Error>] = []
    private var repostOutcomes: [Result<Message, Error>] = []
    private var updateOutcomes: [Result<Message, Error>] = []
    private var deleteOutcomes: [Result<Void, Error>] = []
    private var digOutcomes: [Result<Message, Error>] = []
    private var undigOutcomes: [Result<Message, Error>] = []
    private var messageOutcomes: [Result<Message, Error>] = []
    private var repliesOutcomes: [Result<[Message], Error>] = []
    private var timelineOutcomes: [Result<TimelinePage, Error>] = []
    // M6 write-surface queues (additive — see the M6 conformance block below).
    private var createPostOutcomes: [Result<Message, Error>] = []
    private var scheduledPostsOutcomes: [Result<[Message], Error>] = []
    private var uploadImageOutcomes: [Result<String, Error>] = []
    private var uploadVideoOutcomes: [Result<String, Error>] = []
    private var cancelScheduledOutcomes: [Result<Void, Error>] = []
    private var rescheduleOutcomes: [Result<Message, Error>] = []

    private(set) var recorded: [RecordedMessagesCall] = []

    // MARK: Test programming

    func enqueueCreate(success message: Message) { createOutcomes.append(.success(message)) }
    func enqueueCreate(failure error: Error) { createOutcomes.append(.failure(error)) }

    func enqueueReply(success message: Message) { replyOutcomes.append(.success(message)) }
    func enqueueReply(failure error: Error) { replyOutcomes.append(.failure(error)) }

    func enqueueRepost(success message: Message) { repostOutcomes.append(.success(message)) }
    func enqueueRepost(failure error: Error) { repostOutcomes.append(.failure(error)) }

    func enqueueUpdate(success message: Message) { updateOutcomes.append(.success(message)) }
    func enqueueUpdate(failure error: Error) { updateOutcomes.append(.failure(error)) }

    func enqueueDeleteSuccess() { deleteOutcomes.append(.success(())) }
    func enqueueDelete(failure error: Error) { deleteOutcomes.append(.failure(error)) }

    func enqueueDig(success message: Message) { digOutcomes.append(.success(message)) }
    func enqueueDig(failure error: Error) { digOutcomes.append(.failure(error)) }

    func enqueueUndig(success message: Message) { undigOutcomes.append(.success(message)) }
    func enqueueUndig(failure error: Error) { undigOutcomes.append(.failure(error)) }

    func enqueueMessage(success message: Message) { messageOutcomes.append(.success(message)) }
    func enqueueMessage(failure error: Error) { messageOutcomes.append(.failure(error)) }

    func enqueueReplies(success replies: [Message]) { repliesOutcomes.append(.success(replies)) }
    func enqueueReplies(failure error: Error) { repliesOutcomes.append(.failure(error)) }

    func enqueueTimeline(success page: TimelinePage) { timelineOutcomes.append(.success(page)) }
    func enqueueTimeline(failure error: Error) { timelineOutcomes.append(.failure(error)) }

    func enqueueCreatePost(success message: Message) { createPostOutcomes.append(.success(message)) }
    func enqueueCreatePost(failure error: Error) { createPostOutcomes.append(.failure(error)) }

    func enqueueScheduledPosts(success posts: [Message]) { scheduledPostsOutcomes.append(.success(posts)) }
    func enqueueScheduledPosts(failure error: Error) { scheduledPostsOutcomes.append(.failure(error)) }

    func enqueueUploadImage(success url: String) { uploadImageOutcomes.append(.success(url)) }
    func enqueueUploadImage(failure error: Error) { uploadImageOutcomes.append(.failure(error)) }

    func enqueueUploadVideo(success url: String) { uploadVideoOutcomes.append(.success(url)) }
    func enqueueUploadVideo(failure error: Error) { uploadVideoOutcomes.append(.failure(error)) }

    func enqueueCancelScheduledSuccess() { cancelScheduledOutcomes.append(.success(())) }
    func enqueueCancelScheduled(failure error: Error) { cancelScheduledOutcomes.append(.failure(error)) }
    func enqueueReschedule(success message: Message) { rescheduleOutcomes.append(.success(message)) }
    func enqueueReschedule(failure error: Error) { rescheduleOutcomes.append(.failure(error)) }

    // MARK: MessagesServicing — reads

    func timeline(scope: TimelineScope, tag: String?, limit: Int, offset: Int) async throws -> TimelinePage {
        recorded.append(.init(kind: .timeline(scope: scope, tag: tag, limit: limit, offset: offset)))
        return try take(&timelineOutcomes, label: "timeline")
    }

    nonisolated func timelineStream(scope: TimelineScope, tag: String?, limit: Int, offset: Int) -> AsyncThrowingStream<TimelinePage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.recordTimelineStream(scope: scope, tag: tag, limit: limit, offset: offset)
                do {
                    let page = try await self.takeTimelineForStream()
                    continuation.yield(page)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func recordTimelineStream(scope: TimelineScope, tag: String?, limit: Int, offset: Int) {
        recorded.append(.init(kind: .timelineStream(scope: scope, tag: tag, limit: limit, offset: offset)))
    }

    private func takeTimelineForStream() async throws -> TimelinePage {
        try take(&timelineOutcomes, label: "timelineStream")
    }

    func message(id: String) async throws -> Message {
        recorded.append(.init(kind: .message(id: id)))
        return try take(&messageOutcomes, label: "message")
    }

    func replies(of id: String, limit: Int, offset: Int) async throws -> [Message] {
        recorded.append(.init(kind: .replies(of: id, limit: limit, offset: offset)))
        return try take(&repliesOutcomes, label: "replies")
    }

    // MARK: MessagesServicing — writes

    func create(
        body: String,
        parentId: String?,
        tags: [String],
        visibility: Visibility,
        pushedMessageId: String?
    ) async throws -> Message {
        recorded.append(.init(kind: .create(body: body, parentId: parentId, tags: tags, visibility: visibility, pushedMessageId: pushedMessageId)))
        return try take(&createOutcomes, label: "create")
    }

    func reply(to parentId: String, body: String, tags: [String], visibility: Visibility) async throws -> Message {
        recorded.append(.init(kind: .reply(to: parentId, body: body, tags: tags, visibility: visibility)))
        return try take(&replyOutcomes, label: "reply")
    }

    func repost(_ pushedMessageId: String, commentary: String?, visibility: Visibility) async throws -> Message {
        recorded.append(.init(kind: .repost(messageId: pushedMessageId, commentary: commentary, visibility: visibility)))
        return try take(&repostOutcomes, label: "repost")
    }

    func update(messageId: String, body: String, tags: [String], visibility: Visibility) async throws -> Message {
        recorded.append(.init(kind: .update(messageId: messageId, body: body, tags: tags, visibility: visibility)))
        return try take(&updateOutcomes, label: "update")
    }

    func delete(messageId: String) async throws {
        recorded.append(.init(kind: .delete(messageId: messageId)))
        let _: Void = try take(&deleteOutcomes, label: "delete")
    }

    func dig(messageId: String) async throws -> Message {
        recorded.append(.init(kind: .dig(messageId: messageId)))
        return try take(&digOutcomes, label: "dig")
    }

    func undig(messageId: String) async throws -> Message {
        recorded.append(.init(kind: .undig(messageId: messageId)))
        return try take(&undigOutcomes, label: "undig")
    }

    // MARK: MessagesServicing — M6 write surface
    //
    // Additive conformance added by the Wave 7.3/7.4 (Organizations +
    // Linked-accounts) agent purely to keep the App test bundle compiling
    // after the uncommitted M6 `MessagesServicing` expansion (createPost /
    // scheduledPosts / uploadImage / uploadVideo). It mirrors the existing
    // FIFO-queue style so the Composer agent — which owns the M6 messages /
    // entitlements / scheduled wiring — can write tests against it directly.
    // No existing behavior changed.

    func createPost(
        body: String,
        tags: [String],
        visibility: Visibility,
        imageURLs: [String],
        videoURLs: [String],
        scheduledAt: Date?,
        mastodonProviderIds: [String],
        crossPostToBluesky: Bool,
        crossPostToLinkedIn: Bool
    ) async throws -> Message {
        recorded.append(.init(kind: .createPost(
            body: body,
            tags: tags,
            visibility: visibility,
            imageURLs: imageURLs,
            videoURLs: videoURLs,
            scheduledAt: scheduledAt,
            mastodonProviderIds: mastodonProviderIds,
            crossPostToBluesky: crossPostToBluesky,
            crossPostToLinkedIn: crossPostToLinkedIn
        )))
        return try take(&createPostOutcomes, label: "createPost")
    }

    func scheduledPosts() async throws -> [Message] {
        recorded.append(.init(kind: .scheduledPosts))
        return try take(&scheduledPostsOutcomes, label: "scheduledPosts")
    }

    func uploadImage(_ data: Data) async throws -> String {
        recorded.append(.init(kind: .uploadImage(byteCount: data.count)))
        return try take(&uploadImageOutcomes, label: "uploadImage")
    }

    func uploadVideo(_ data: Data, contentType: String) async throws -> String {
        recorded.append(.init(kind: .uploadVideo(byteCount: data.count, contentType: contentType)))
        return try take(&uploadVideoOutcomes, label: "uploadVideo")
    }

    func cancelScheduled(messageId: String) async throws {
        recorded.append(.init(kind: .cancelScheduled(messageId: messageId)))
        let _: Void = try take(&cancelScheduledOutcomes, label: "cancelScheduled")
    }

    func reschedule(messageId: String, newDate: Date) async throws -> Message {
        recorded.append(.init(kind: .reschedule(messageId: messageId, newDate: newDate)))
        return try take(&rescheduleOutcomes, label: "reschedule")
    }

    // MARK: - Internals

    private func take<T>(_ queue: inout [Result<T, Error>], label: String) throws -> T {
        guard !queue.isEmpty else {
            throw StubError.noOutcome(label: label)
        }
        switch queue.removeFirst() {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    enum StubError: Error, Equatable {
        case noOutcome(label: String)
    }
}
