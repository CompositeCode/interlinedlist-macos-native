import Foundation
import InterlinedKit

// MARK: - MessagesError

/// Domain-level errors surfaced by `MessagesService`'s M6 write surface.
///
/// Transport / status / decode failures continue to surface as `APIError` —
/// these are the domain-layer cases the kit cannot express. Mirrors the
/// `ListsError.subscriberRequired` pattern (PLAN.md §8 — subscriber gating
/// through `EntitlementsService`): the gated write paths (media attach,
/// scheduled posts, cross-posting) check entitlement *before* any HTTP call
/// and throw this when the account is not entitled.
public enum MessagesError: Error, Sendable, Equatable {

    /// The current account is not entitled to a subscriber-only posting
    /// feature. Raised when `EntitlementsService.isEnabled(feature) == false`,
    /// before any HTTP call is made, so the composer can surface a friendly
    /// upsell rather than a mid-flow 403 (PLAN.md §8 — "Subscriber 403s
    /// mid-flow"). The associated `Feature` tells the UI which capability was
    /// blocked so the upsell copy can be specific.
    case subscriberRequired(Feature)

    /// A media attachment exceeds the API's hard byte limit and cannot be
    /// reduced client-side. Images are resized/recompressed by `ImagePrep`
    /// before this can fire (so this surfaces only for an undersizable
    /// image — `ImagePrepError.tooLargeAfterAllAttempts` is re-thrown as-is,
    /// not folded here); video cannot be transcoded client-side, so an
    /// over-budget video throws this with the actual / limit byte counts so
    /// the UI can tell the user how much to trim (PLAN.md §8 — "clear errors
    /// when impossible").
    case mediaTooLarge(byteCount: Int, limit: Int)
}

extension MessagesError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .subscriberRequired(let feature):
            switch feature {
            case .mediaAttachments:
                return "Attaching media requires an active subscription."
            case .scheduledPosts:
                return "Scheduling posts requires an active subscription."
            case .crossPosting:
                return "Cross-posting requires an active subscription."
            }
        case .mediaTooLarge(let byteCount, let limit):
            return "This file is \(byteCount) bytes, over the \(limit)-byte limit."
        }
    }
}

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

    // MARK: - M6 write surface (PLAN.md §6 M6 — "Subscriber & orgs")
    //
    // Additive over the M2 surface (the M2 methods above are unchanged). The
    // three subscriber-gated capabilities — media attachments, scheduling,
    // cross-posting — route through `EntitlementsService` before any HTTP
    // call and throw `MessagesError.subscriberRequired(feature)` when the
    // account is not entitled (PLAN.md §8). The kit's `CreateMessageRequest`
    // already accepts every field these methods set; this surface is the
    // domain-level seam the M6 composer codes against.

    /// Creates a post with the full M6 field set in one call: media
    /// attachments, scheduling, and cross-post fan-out. Each non-trivial
    /// option is entitlement-gated:
    ///
    /// - non-empty `imageURLs` / `videoURLs` requires `.mediaAttachments`;
    /// - a non-nil `scheduledAt` requires `.scheduledPosts`;
    /// - any cross-post target (`mastodonProviderIds` non-empty,
    ///   `crossPostToBluesky`, or `crossPostToLinkedIn`) requires
    ///   `.crossPosting`.
    ///
    /// All applicable gates are checked before the HTTP call; the first
    /// failing gate throws `MessagesError.subscriberRequired(feature)` and no
    /// request is made. A plain text post (no media / schedule / cross-post)
    /// passes every gate and behaves like the M2 `create`.
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
    ) async throws -> Message

    /// Loads the caller's pending scheduled posts (`GET /api/messages/scheduled`).
    /// Read-only and ungated (viewing what you scheduled is not a paid action;
    /// the gate is on *creating* a scheduled post). Returns domain `Message`
    /// values with `scheduledAt` populated; the App layer groups them by
    /// today / this week / this month.
    func scheduledPosts() async throws -> [Message]

    /// Uploads an image attachment, returning its hosted URL. Runs the source
    /// bytes through `ImagePrep` (resize + recompress to the API limits) before
    /// calling the kit upload builder. Entitlement-gated on `.mediaAttachments`
    /// — checked before the prep step and the HTTP call.
    ///
    /// - Throws:
    ///   - `MessagesError.subscriberRequired(.mediaAttachments)` when the
    ///     account is not entitled (no prep, no upload).
    ///   - `ImagePrepError` when the bytes cannot be prepared within the limits.
    ///   - `APIError` from the upload itself.
    func uploadImage(_ data: Data) async throws -> String

    /// Uploads a video attachment, returning its hosted URL. Entitlement-gated
    /// on `.mediaAttachments` (checked before the byte-budget check and the
    /// HTTP call). The client cannot transcode video, so this validates the
    /// byte budget (`MessagesService.maxVideoBytes`) and throws
    /// `MessagesError.mediaTooLarge` when the budget is exceeded rather than
    /// shipping bytes the server will reject.
    ///
    /// - Parameters:
    ///   - data: the already-encoded video bytes.
    ///   - contentType: the video MIME type (e.g. `"video/mp4"`).
    func uploadVideo(_ data: Data, contentType: String) async throws -> String

    // MARK: - NW-3: Scheduled post management

    /// Cancels a scheduled post by deleting it. The post must not yet be
    /// published; calling on a published post surfaces `APIError.notFound`
    /// (the server treats it as gone once published).
    func cancelScheduled(messageId: String) async throws

    /// Reschedules a pending post to `newDate`. Re-fetches the existing body
    /// first so the update call can supply the full content (the PUT requires
    /// a complete body, not a patch). Returns the authoritative updated
    /// `Message` (with `scheduledAt == newDate`).
    func reschedule(messageId: String, newDate: Date) async throws -> Message
}

// MARK: - MessagesService

public final class MessagesService: MessagesServicing {

    // MARK: - M6 media limits (PLAN.md §8)
    //
    // Hard-coded per PLAN.md §8 ("Media size limits — 1.4 MB image / 3 MB
    // video"). The image limits are sourced from `ImagePrep` (the prep
    // pipeline is the authority for the image budget); the video limit lives
    // here because the client cannot transcode video and so just validates the
    // budget before upload.
    //
    // TODO(backend ask P2.5): the API does not expose these limits in a
    // machine-readable form today. Backend ask P2.5 proposes a `/api/limits`
    // (or `customerStatus`-embedded) document so the client reads the budget
    // instead of hard-coding it; when that lands these constants become a
    // fallback default and the live value wins.

    /// Maximum image bytes accepted by the API. Sourced from `ImagePrep`'s
    /// own budget so the two never drift (PLAN.md §8 — ≤ 1.4 MB image).
    public static let maxImageBytes: Int = ImagePrep.maxBytes

    /// Maximum image longest-edge pixels. Sourced from `ImagePrep` (≤ 1200 px).
    public static let maxImageLongestEdgePixels = ImagePrep.maxLongestEdgePixels

    /// Maximum video bytes accepted by the API (PLAN.md §8 — ≤ 3 MB video).
    /// The client cannot transcode video, so this is a hard pre-upload gate.
    public static let maxVideoBytes: Int = 3 * 1_024 * 1_024

    private let api: APIClientProtocol
    private let store: MessageStore?
    private let decoder: JSONDecoder

    /// The entitlement source consulted by every M6 gated write path. Held as
    /// a `@Sendable` provider closure rather than a stored snapshot so gating is
    /// evaluated **at call time** against the live account. The default-snapshot
    /// init below wraps a fixed value in a constant closure; the App layer's
    /// composition root injects a closure that reads the *current*
    /// `EntitlementsService` (rebuilt from the refreshed `CurrentUser`), so a
    /// subscriber whose status resolves after the service is constructed is no
    /// longer wrongly blocked at the domain gate, and a lapsed subscription
    /// re-gates without rebuilding the service (PLAN.md §8 — "re-fetch
    /// `customerStatus`, update UI").
    private let entitlementsProvider: @Sendable () -> EntitlementsService

    /// - Parameters:
    ///   - api: the networking seam (a stub in tests).
    ///   - store: optional cache port. When `nil`, the service fetches live
    ///     with no caching.
    ///   - decoder: shared kit JSON configuration, used to split the paginated
    ///     envelope. Defaults to the kit's `JSONCoders` decoder so dates parse
    ///     identically to the client.
    ///   - entitlements: the subscriber-gating seam for the M6 write surface
    ///     (PLAN.md §3, §8). Defaults to a free-account value so existing M2
    ///     call sites stay source-compatible; the M6 composer constructs the
    ///     service with the live `EntitlementsService` built from the signed-in
    ///     `CurrentUser`. Only the M6 gated methods consult it — the M2 surface
    ///     is unaffected.
    ///
    /// This init captures a **fixed** entitlements snapshot. Use
    /// `init(api:store:decoder:entitlementsProvider:)` when the entitlements
    /// must track a session that resolves / changes after construction.
    public convenience init(
        api: APIClientProtocol,
        store: MessageStore? = nil,
        decoder: JSONDecoder = JSONCoders.makeDecoder(),
        entitlements: EntitlementsService = EntitlementsService(customerStatus: .free)
    ) {
        self.init(
            api: api,
            store: store,
            decoder: decoder,
            entitlementsProvider: { entitlements }
        )
    }

    /// Entitlements-provider init (PLAN.md §8 — live gating).
    ///
    /// Identical to the snapshot init except the entitlement source is a
    /// `@Sendable` closure evaluated on every gated call. The App layer passes
    /// a closure that reads the current user's `EntitlementsService` so the
    /// domain backstop tracks the **live** `customerStatus`: a real subscriber
    /// is no longer blocked because the service was constructed before sign-in
    /// resolved, and a mid-session lapse re-gates on the next call. Additive —
    /// the snapshot init above is unchanged and delegates here.
    ///
    /// - Parameter entitlementsProvider: returns the entitlements to gate
    ///   against, evaluated at call time. Must be cheap (it runs per gated
    ///   call) and side-effect-free.
    public init(
        api: APIClientProtocol,
        store: MessageStore? = nil,
        decoder: JSONDecoder = JSONCoders.makeDecoder(),
        entitlementsProvider: @escaping @Sendable () -> EntitlementsService
    ) {
        self.api = api
        self.store = store
        self.decoder = decoder
        self.entitlementsProvider = entitlementsProvider
    }

    // MARK: Timeline

    public func timeline(
        scope: TimelineScope,
        tag: String?,
        limit: Int,
        offset: Int
    ) async throws -> TimelinePage {
        // The Following feed has no API endpoint yet. Return an empty page
        // immediately — no network call, no store write — so the view model
        // surfaces a "coming soon" empty state rather than a spinner that
        // never resolves or a spurious API error (App Store Guideline 2.1).
        if scope == .following {
            return TimelinePage(messages: [], hasMore: false, nextOffset: nil)
        }
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

    // MARK: - M6 write surface (PLAN.md §6 M6)

    public func createPost(
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
        // Gate every applicable subscriber feature *before* any HTTP call, so
        // the composer surfaces an upsell instead of a mid-flow 403 (PLAN.md
        // §8). The first failing gate throws; no request is made.
        let hasMedia = !imageURLs.isEmpty || !videoURLs.isEmpty
        if hasMedia {
            try requireEntitlement(.mediaAttachments)
        }
        if scheduledAt != nil {
            try requireEntitlement(.scheduledPosts)
        }
        let hasCrossPost = !mastodonProviderIds.isEmpty || crossPostToBluesky || crossPostToLinkedIn
        if hasCrossPost {
            try requireEntitlement(.crossPosting)
        }

        // Encode empty collections / false flags as `nil` so the wire body
        // stays minimal — `CreateMessageRequest.encode(to:)` skips nil fields
        // and the server applies its own defaults.
        let request = CreateMessageRequest(
            content: body,
            publiclyVisible: visibility.isPubliclyVisible,
            tags: tags.isEmpty ? nil : tags,
            imageUrls: imageURLs.isEmpty ? nil : imageURLs,
            videoUrls: videoURLs.isEmpty ? nil : videoURLs,
            scheduledAt: scheduledAt,
            mastodonProviderIds: mastodonProviderIds.isEmpty ? nil : mastodonProviderIds,
            crossPostToBluesky: crossPostToBluesky ? true : nil,
            crossPostToLinkedIn: crossPostToLinkedIn ? true : nil
        )
        let dto = try await api.send(Messages.create(request))
        let message = Message(from: dto)
        // A scheduled post is not yet on the timeline; only cache published
        // posts so the by-id cache never serves a not-yet-public message as
        // if it were live.
        if scheduledAt == nil {
            await store?.upsert([message])
        }
        return message
    }

    public func scheduledPosts() async throws -> [Message] {
        let response = try await api.send(Messages.scheduled())
        // Read-only; do not write the by-id cache — these are future posts the
        // timeline cache should not surface as published.
        return response.messages.map(Message.init(from:))
    }

    public func uploadImage(_ data: Data) async throws -> String {
        // Gate before the (potentially expensive) prep step and the upload.
        try requireEntitlement(.mediaAttachments)
        // `ImagePrep` resizes + recompresses to the API limits. An image that
        // still cannot fit re-throws `ImagePrepError.tooLargeAfterAllAttempts`
        // unchanged (it is the precise, actionable failure for the UI).
        let prepared = try ImagePrep.prepare(data)
        let response = try await api.send(
            Messages.uploadImage(prepared.data, contentType: prepared.format.mimeType)
        )
        return response.url
    }

    public func uploadVideo(_ data: Data, contentType: String) async throws -> String {
        // Gate before the budget check and the upload.
        try requireEntitlement(.mediaAttachments)
        // The client cannot transcode video; enforce the hard byte budget
        // up front so we never ship bytes the server will reject (PLAN.md §8).
        guard data.count <= Self.maxVideoBytes else {
            throw MessagesError.mediaTooLarge(byteCount: data.count, limit: Self.maxVideoBytes)
        }
        let response = try await api.send(Messages.uploadVideo(data, contentType: contentType))
        return response.url
    }

    public func cancelScheduled(messageId: String) async throws {
        try await api.sendVoid(Messages.delete(id: messageId))
        await store?.remove(id: messageId)
    }

    public func reschedule(messageId: String, newDate: Date) async throws -> Message {
        let existing = try await message(id: messageId)
        let request = CreateMessageRequest(
            content: existing.text,
            publiclyVisible: existing.visibility.isPubliclyVisible,
            tags: existing.tags.isEmpty ? nil : existing.tags,
            scheduledAt: newDate
        )
        let dto = try await api.send(Messages.update(id: messageId, request))
        let updated = Message(from: dto)
        return updated
    }

    /// Throws `MessagesError.subscriberRequired(feature)` when `feature` is
    /// not enabled for the current account. The single gate every M6 write
    /// path routes through (PLAN.md §3 — "one switch, not scattered ifs").
    ///
    /// Evaluates `entitlementsProvider` per call so gating tracks the live
    /// account (PLAN.md §8) rather than a snapshot taken at construction.
    private func requireEntitlement(_ feature: Feature) throws {
        guard entitlementsProvider().isEnabled(feature) else {
            throw MessagesError.subscriberRequired(feature)
        }
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
