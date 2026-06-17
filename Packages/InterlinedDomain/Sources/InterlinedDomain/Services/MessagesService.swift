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
