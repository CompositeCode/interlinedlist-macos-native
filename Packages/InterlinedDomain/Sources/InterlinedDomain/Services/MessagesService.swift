import Foundation
import InterlinedKit

// MARK: - MessagesServicing

/// The timeline + message read surface the App layer codes against (PLAN.md
/// §6 M1 read-only core). Depends only on `APIClientProtocol` and the optional
/// `MessageStore` cache port, so it is fully unit-testable against stubs.
public protocol MessagesServicing: Sendable {

    /// Loads one page of the timeline for `scope`, optionally filtered by
    /// `tag`. `scope == .mine` maps to the API's `onlyMine=true` flag.
    ///
    /// When a `MessageStore` is injected the result is written through to the
    /// cache; if the live fetch fails and the cache holds a prior page for the
    /// same scope + tag, that cached page is returned instead of throwing
    /// (stale-while-revalidate / offline fallback).
    func timeline(scope: TimelineScope, tag: String?, limit: Int, offset: Int) async throws -> TimelinePage

    /// Surfaces the cached page first (when a store is injected and holds one),
    /// then the freshly-fetched page — the stale-while-revalidate stream the
    /// App layer binds to so the UI renders instantly and refreshes in place.
    /// With no store, the stream yields exactly one element: the live page.
    func timelineStream(scope: TimelineScope, tag: String?, limit: Int, offset: Int) -> AsyncThrowingStream<TimelinePage, Error>

    /// Loads a single message by id, writing it through to the cache. Falls
    /// back to the cached copy when the live fetch fails and one exists.
    func message(id: String) async throws -> Message

    /// Loads the direct replies to a message.
    func replies(of id: String, limit: Int, offset: Int) async throws -> [Message]

    // MARK: - M2 write surface (PLAN.md §6 M2)
    //
    // Wraps the Wave 1 `InterlinedKit.Messages` builders. The write surface is
    // deliberately small: only the fields the M2 composer / reply / repost /
    // edit / delete UIs consume. Cross-post fan-out (`mastodonProviderIds`,
    // `crossPostToBluesky`, `crossPostToLinkedIn`), scheduling (`scheduledAt`),
    // and media attachments (`imageUrls`, `videoUrls`) are accepted by the
    // kit's `CreateMessageRequest` but **not** exposed at the domain seam
    // until M6, when the composer grows the platform pickers, the date
    // picker, and the upload pipeline. Adding them later is additive.

    /// Creates a new message (post, reply, or repost depending on which of
    /// `parentId` / `pushedMessageId` is set).
    ///
    /// - Parameters:
    ///   - body: the Markdown source — written into the API's `content` field.
    ///   - parentId: when set, the new message is a reply to this id.
    ///   - tags: hashtag-style tag tokens; empty for none.
    ///   - visibility: `.public` or `.private`.
    ///   - pushedMessageId: when set, the new message is a repost ("push") of
    ///     this id. Mutually exclusive in practice with `parentId` (a reply
    ///     to a repost is still a reply), but the API does not enforce
    ///     mutual exclusion and neither does this method — the caller's
    ///     intent flows through unchanged.
    func create(
        body: String,
        parentId: String?,
        tags: [String],
        visibility: Visibility,
        pushedMessageId: String?
    ) async throws -> Message

    /// Convenience over `create` with `parentId` set. Lets the App-layer
    /// reply UI call a verb that matches the intent ("reply to this") rather
    /// than spelling out the create call. Visibility is explicit so the UI
    /// can default a reply's visibility independently of the parent.
    func reply(
        to parentId: String,
        body: String,
        tags: [String],
        visibility: Visibility
    ) async throws -> Message

    /// Convenience over `create` with `pushedMessageId` set. The optional
    /// `commentary` becomes the post body — `nil` and `""` both encode as an
    /// empty body, which is what the web composer sends for a bare repost.
    func repost(
        _ pushedMessageId: String,
        commentary: String?,
        visibility: Visibility
    ) async throws -> Message

    /// Edits an existing message in place. The full body/tags/visibility are
    /// resent — this is a PUT, not a PATCH, matching the kit builder.
    func update(
        messageId: String,
        body: String,
        tags: [String],
        visibility: Visibility
    ) async throws -> Message

    /// Deletes a message. Removes it from the by-id cache on success so the
    /// UI never re-renders a tombstoned message from the cache.
    func delete(messageId: String) async throws

    /// Adds an "I Dig!" reaction to a message. Returns the updated cached
    /// `Message` (with the new dig count and `didDig == true`) so the
    /// optimistic-UI path can replace its in-memory copy.
    func dig(messageId: String) async throws -> Message

    /// Removes an "I Dig!" reaction from a message. Mirrors `dig` — returns
    /// the updated cached `Message`.
    func undig(messageId: String) async throws -> Message
}

// MARK: - MessagesService

public final class MessagesService: MessagesServicing {

    private let api: APIClientProtocol
    private let store: MessageStore?
    private let decoder: JSONDecoder

    /// - Parameters:
    ///   - api: the networking seam (a stub in tests).
    ///   - store: optional cache port. When `nil`, the service fetches live
    ///     with no caching.
    ///   - decoder: shared kit JSON configuration, used to split the paginated
    ///     envelope. Defaults to the kit's `JSONCoders` decoder so dates parse
    ///     identically to the client.
    public init(
        api: APIClientProtocol,
        store: MessageStore? = nil,
        decoder: JSONDecoder = JSONCoders.makeDecoder()
    ) {
        self.api = api
        self.store = store
        self.decoder = decoder
    }

    // MARK: Timeline

    public func timeline(
        scope: TimelineScope,
        tag: String?,
        limit: Int,
        offset: Int
    ) async throws -> TimelinePage {
        do {
            let page = try await fetchTimelinePage(scope: scope, tag: tag, limit: limit, offset: offset)
            await store?.replaceTimeline(page.messages, scope: scope, tag: tag)
            return page
        } catch let error as APIError {
            // Offline / upstream failure: fall back to a cached page when one
            // exists. A genuine empty cache still surfaces the error so the UI
            // can show a real failure rather than a silent empty feed.
            if let store, case let cached = await store.cachedTimeline(scope: scope, tag: tag), !cached.isEmpty {
                return TimelinePage(messages: cached, hasMore: false, nextOffset: nil)
            }
            throw error
        }
    }

    public func timelineStream(
        scope: TimelineScope,
        tag: String?,
        limit: Int,
        offset: Int
    ) -> AsyncThrowingStream<TimelinePage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // 1. Surface the cached page immediately, if any.
                if let store {
                    let cached = await store.cachedTimeline(scope: scope, tag: tag)
                    if !cached.isEmpty {
                        continuation.yield(TimelinePage(messages: cached, hasMore: false, nextOffset: nil))
                    }
                }
                // 2. Revalidate from the API and surface the fresh page.
                do {
                    let fresh = try await self.timeline(scope: scope, tag: tag, limit: limit, offset: offset)
                    continuation.yield(fresh)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Detail

    public func message(id: String) async throws -> Message {
        do {
            let dto = try await api.send(Messages.get(id: id))
            let message = Message(from: dto)
            await store?.upsert([message])
            return message
        } catch let error as APIError {
            if let store, let cached = await store.cachedMessage(id: id) {
                return cached
            }
            throw error
        }
    }

    public func replies(of id: String, limit: Int, offset: Int) async throws -> [Message] {
        let response = try await api.send(Messages.replies(of: id, limit: limit, offset: offset))
        let messages = response.replies.map(Message.init(from:))
        await store?.upsert(messages)
        return messages
    }

    // MARK: - M2 write surface (PLAN.md §6 M2)

    public func create(
        body: String,
        parentId: String?,
        tags: [String],
        visibility: Visibility,
        pushedMessageId: String?
    ) async throws -> Message {
        // Encode an empty tag list as `nil` so the wire body stays minimal —
        // `CreateMessageRequest.encode(to:)` skips nil fields.
        let request = CreateMessageRequest(
            content: body,
            publiclyVisible: visibility.isPubliclyVisible,
            tags: tags.isEmpty ? nil : tags,
            parentId: parentId,
            pushedMessageId: pushedMessageId
        )
        let dto = try await api.send(Messages.create(request))
        let message = Message(from: dto)
        await store?.upsert([message])
        return message
    }

    public func reply(
        to parentId: String,
        body: String,
        tags: [String],
        visibility: Visibility
    ) async throws -> Message {
        try await create(
            body: body,
            parentId: parentId,
            tags: tags,
            visibility: visibility,
            pushedMessageId: nil
        )
    }

    public func repost(
        _ pushedMessageId: String,
        commentary: String?,
        visibility: Visibility
    ) async throws -> Message {
        try await create(
            body: commentary ?? "",
            parentId: nil,
            tags: [],
            visibility: visibility,
            pushedMessageId: pushedMessageId
        )
    }

    public func update(
        messageId: String,
        body: String,
        tags: [String],
        visibility: Visibility
    ) async throws -> Message {
        let request = CreateMessageRequest(
            content: body,
            publiclyVisible: visibility.isPubliclyVisible,
            tags: tags.isEmpty ? nil : tags
        )
        let dto = try await api.send(Messages.update(id: messageId, request))
        let message = Message(from: dto)
        await store?.upsert([message])
        return message
    }

    public func delete(messageId: String) async throws {
        try await api.sendVoid(Messages.delete(id: messageId))
        await store?.remove(id: messageId)
    }

    public func dig(messageId: String) async throws -> Message {
        let response = try await api.send(Messages.dig(id: messageId))
        return try await applyDigResponse(response, to: messageId)
    }

    public func undig(messageId: String) async throws -> Message {
        let response = try await api.send(Messages.undig(id: messageId))
        return try await applyDigResponse(response, to: messageId)
    }

    /// Folds the small `DigResponse` envelope into a freshly-merged `Message`.
    ///
    /// Dig and undig do not return a full message body — only the updated
    /// `digCount` / `dugByMe` pair (plus `isNewDig` / `digCreatedAt` on add,
    /// which the domain does not consume). To return a usable `Message` for
    /// the optimistic-UI path, we re-fetch the message body. This is one
    /// extra round-trip per reaction, which we accept for M2 simplicity;
    /// the call site can move to a purely-local merge once a cached
    /// `Message` is guaranteed to be present (the optimistic flow already
    /// has one in hand). The current shape is deliberately conservative.
    private func applyDigResponse(_ response: DigResponse, to messageId: String) async throws -> Message {
        let dto = try await api.send(Messages.get(id: messageId))
        // Trust the dig response's count/flag pair (it's the freshest), and
        // overlay the freshly-fetched body so we have a complete `Message`.
        let merged = Message(from: dto)
        let updated = Message(
            id: merged.id,
            author: merged.author,
            text: merged.text,
            createdAt: merged.createdAt,
            updatedAt: merged.updatedAt,
            tags: merged.tags,
            visibility: merged.visibility,
            digCount: response.digCount,
            didDig: response.dugByMe,
            repostCount: merged.repostCount,
            replyCount: merged.replyCount,
            parentID: merged.parentID,
            repost: merged.repost,
            scheduledAt: merged.scheduledAt
        )
        await store?.upsert([updated])
        return updated
    }

    // MARK: - Paginated consumption

    /// Mirrors the kit's `fetchPaginated` test helper and `ContractTests`:
    /// `Paginated<T>` is not `Decodable` (its collection key is runtime-known
    /// via `Request.paginationKey`), so the paginated request is sent with
    /// `sendRaw` and the bytes are split by `PaginatedDecoder` using the
    /// builder's own key.
    private func fetchTimelinePage(
        scope: TimelineScope,
        tag: String?,
        limit: Int,
        offset: Int
    ) async throws -> TimelinePage {
        let request = Messages.list(
            limit: limit,
            offset: offset,
            onlyMine: scope.onlyMine,
            tag: tag
        )
        let (data, _) = try await api.sendRaw(request)
        let key = request.paginationKey ?? "messages"
        let paginated = try PaginatedDecoder.decode(
            MessageDTO.self,
            collectionKey: key,
            from: data,
            decoder: decoder
        )
        return TimelinePage(from: paginated)
    }
}
