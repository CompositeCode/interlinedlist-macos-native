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
