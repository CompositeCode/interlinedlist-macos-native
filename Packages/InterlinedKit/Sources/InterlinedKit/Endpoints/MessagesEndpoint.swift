import Foundation

/// Request builders for the **Messages** endpoint group.
///
/// Follows the eight conventions documented on `Request` (see `Request.swift`):
/// one `public enum` namespace, factory methods returning `Request<DTO>`,
/// explicit `AuthRequirement`, path-only URLs, nil-skipping query items,
/// `RequestBody.json` / `RequestBody.raw`, and total (never-throwing) factories.
///
/// Auth: every builder is `.bearer` per decision 0001 (Bearer is the primary
/// transport, and the 401 safety net in `APIClient` transparently falls back to
/// the session transport for the few endpoints that still reject Bearer — dig,
/// in particular, was observed to). The single public read,
/// `userMessages(username:)`, is `.none`.
public enum Messages {

    // MARK: - List / read

    /// `GET /api/messages` — the authenticated timeline.
    ///
    /// Returns the standard `{ "messages": [...], "pagination": {...} }`
    /// envelope, so `paginationKey` is `"messages"`.
    public static func list(
        limit: Int? = nil,
        offset: Int? = nil,
        onlyMine: Bool? = nil,
        tag: String? = nil
    ) -> Request<Paginated<MessageDTO>> {
        Request(
            method: .get,
            path: "/api/messages",
            query: [
                .int("limit", limit),
                .int("offset", offset),
                .bool("onlyMine", onlyMine),
                .string("tag", tag)
            ],
            auth: .bearer,
            paginationKey: "messages"
        )
    }

    /// `GET /api/messages/[id]` — a single message.
    public static func get(id: String) -> Request<MessageDTO> {
        Request(method: .get, path: "/api/messages/\(id)", auth: .bearer)
    }

    /// `GET /api/messages/scheduled` — the caller's pending scheduled posts.
    ///
    /// Non-standard envelope: `{ "messages": [...] }` with no `pagination`
    /// block, so this decodes into `ScheduledMessagesResponse` rather than
    /// `Paginated`.
    public static func scheduled() -> Request<ScheduledMessagesResponse> {
        Request(method: .get, path: "/api/messages/scheduled", auth: .bearer)
    }

    /// `GET /api/messages/[id]/replies` — direct replies to a message.
    ///
    /// Non-standard envelope: `{ "replies": [...], "total": Int }`. It accepts
    /// `limit`/`offset` for paging but does not return the `pagination` block,
    /// so this decodes into `RepliesResponse`.
    public static func replies(
        of id: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<RepliesResponse> {
        Request(
            method: .get,
            path: "/api/messages/\(id)/replies",
            query: [
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .bearer
        )
    }

    // MARK: - Write

    /// `POST /api/messages` — create a message (post, reply, repost, or
    /// scheduled post depending on the fields set on `body`).
    ///
    /// Returns `MessageWriteResponse`, not a bare `MessageDTO`: the live create
    /// response wraps the message under `data` and reports cross-post results in
    /// a top-level `crossPosts` array (drift observed 2026-08-17). The wrapper's
    /// tolerant decoder also accepts the older flat shape.
    public static func create(_ body: CreateMessageRequest) -> Request<MessageWriteResponse> {
        Request(method: .post, path: "/api/messages", body: .json(body), auth: .bearer)
    }

    /// `PATCH /api/messages/[id]` — move a **future scheduled** post to a new
    /// send time. Returns a bare `MessageDTO`.
    ///
    /// VERIFIED live 2026-09-06 (work-consolidation.md §1c · V1). This replaces
    /// the old `update(id:_:)`, which sent `PUT` (**405** live) and decoded the
    /// `MessageWriteResponse` envelope (the reply is a bare DTO). The rename is
    /// deliberate and is the substantive half of the finding: `PATCH` is a
    /// **reschedule** route, not a message-edit route. The live handler accepts
    /// only `scheduledAt`, rejects a content/tags/visibility body with
    /// `400 "No valid updates provided"`, silently drops `content` when it is
    /// sent alongside `scheduledAt`, and refuses any already-published message
    /// with `400 "Can only edit scheduled posts that are in the future"`.
    /// See `RescheduleMessageRequest` for the probe transcript.
    ///
    /// RE-CONFIRMED read-only 2026-09-09 (GitHub #55): `OPTIONS` on this path
    /// reports `Allow: DELETE, GET, HEAD, OPTIONS, PATCH`, so `PATCH` is the
    /// **only** update verb a message has. There is no dedicated scheduled-post
    /// editor route either — `/api/messages/scheduled/[id]` and
    /// `/api/messages/[id]/schedule` both 404, and `OPTIONS
    /// /api/messages/scheduled` reports `Allow: GET, HEAD, OPTIONS` (read-only).
    /// The deployed web client agrees: it issues no `PATCH /api/messages/[id]`
    /// anywhere in its bundles, so the scheduled-post content/destination editor
    /// its help page describes is not something the live product actually ships.
    ///
    /// Editing a published message has **no route on the live API** — see
    /// `MessagesServicing.update` for how that is surfaced to callers.
    public static func reschedule(id: String, _ body: RescheduleMessageRequest) -> Request<MessageDTO> {
        Request(method: .patch, path: "/api/messages/\(id)", body: .json(body), auth: .bearer)
    }

    /// `POST /api/messages/[id]/reply-counts` — re-poll the cross-post targets
    /// and return fresh per-platform reply tallies (work-consolidation.md G27).
    ///
    /// VERIFIED live 2026-09-06: `OPTIONS` reports `Allow: OPTIONS, POST`, and a
    /// real refresh on an owned message returned HTTP 200 with
    /// `{ replyCounts: [...], repliesCheckedAt }`. The body is empty — the id in
    /// the path is the whole request.
    public static func refreshReplyCounts(id: String) -> Request<MessageReplyCountsResponse> {
        Request(method: .post, path: "/api/messages/\(id)/reply-counts", auth: .bearer)
    }

    /// `DELETE /api/messages/[id]` — delete a message. The body is not
    /// meaningful; send via `sendVoid`.
    public static func delete(id: String) -> Request<EmptyResponse> {
        Request(method: .delete, path: "/api/messages/\(id)", auth: .bearer)
    }

    // MARK: - Dig (reaction)

    /// `POST /api/messages/[id]/dig` — add an "I Dig!" reaction.
    public static func dig(id: String) -> Request<DigResponse> {
        Request(method: .post, path: "/api/messages/\(id)/dig", auth: .bearer)
    }

    /// `DELETE /api/messages/[id]/dig` — remove an "I Dig!" reaction.
    public static func undig(id: String) -> Request<DigResponse> {
        Request(method: .delete, path: "/api/messages/\(id)/dig", auth: .bearer)
    }

    // MARK: - Media uploads

    /// `POST /api/messages/images/upload` — upload an image and receive its
    /// hosted URL. The caller supplies already-encoded bytes plus their MIME
    /// type (e.g. `"image/png"`), so this uses `RequestBody.raw`.
    public static func uploadImage(_ data: Data, contentType: String) -> Request<MediaUploadResponse> {
        Request(
            method: .post,
            path: "/api/messages/images/upload",
            body: .raw(data, contentType: contentType),
            auth: .bearer
        )
    }

    /// `POST /api/messages/videos/upload` — upload a video and receive its
    /// hosted URL. Uses `RequestBody.raw` like the image upload.
    public static func uploadVideo(_ data: Data, contentType: String) -> Request<MediaUploadResponse> {
        Request(
            method: .post,
            path: "/api/messages/videos/upload",
            body: .raw(data, contentType: contentType),
            auth: .bearer
        )
    }

    // MARK: - Public

    /// `GET /api/user/[username]/messages` — a user's public posts. No auth.
    ///
    /// Standard `{ "messages": [...], "pagination": {...} }` envelope, so
    /// `paginationKey` is `"messages"`.
    public static func userMessages(
        username: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Request<Paginated<MessageDTO>> {
        Request(
            method: .get,
            path: "/api/user/\(username)/messages",
            query: [
                .int("limit", limit),
                .int("offset", offset)
            ],
            auth: .none,
            paginationKey: "messages"
        )
    }
}
