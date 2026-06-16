import Foundation

// MARK: - AuthRequirement

/// How a request must be authenticated.
///
/// This is the routing hint that lets `AuthTransport` (decision 0001) choose
/// between the **Bearer** transport (default for nearly every endpoint) and
/// the small **cookie-session** allowlist (`/api/user/identities`,
/// `/api/user/organizations`, `/api/exports/*`).
///
/// Most endpoint builders should leave this as `.bearer`. Builders for the
/// session-only allowlist set `.session`. Builders for unauthenticated
/// endpoints (login, register, public profile reads) set `.none`.
public enum AuthRequirement: Sendable, Equatable {
    /// No `Authorization` header and no cookie — public endpoint.
    case none
    /// Default. Send `Authorization: Bearer <token>`.
    case bearer
    /// Use the cookie-session transport (lazy login + `URLSession`-managed
    /// `HttpOnly` cookie). Reserved for the decision-0001 allowlist.
    case session
}

// MARK: - Request

/// A value-typed description of an HTTP request to the InterlinedList API.
///
/// `Request<Response>` is generic over the **expected decoded response type**.
/// This is the foundation every endpoint group in `Endpoints/` builds on.
///
/// ## Endpoint extension pattern (for the per-group request builder agents)
///
/// Each endpoint group lives in its own file under `Endpoints/` and exposes
/// a `public enum` namespace whose static factory methods return a
/// `Request<…>` typed to the matching DTO. The DTOs themselves live in `DTOs/`.
///
/// ```swift
/// // Endpoints/MessagesEndpoint.swift
/// public enum Messages {
///     /// GET /api/messages
///     public static func list(
///         limit: Int? = nil,
///         offset: Int? = nil,
///         onlyMine: Bool? = nil,
///         tag: String? = nil
///     ) -> Request<Paginated<MessageDTO>> {
///         Request(
///             method: .get,
///             path: "/api/messages",
///             query: [
///                 .int("limit", limit),
///                 .int("offset", offset),
///                 .bool("onlyMine", onlyMine),
///                 .string("tag", tag)
///             ],
///             auth: .bearer,
///             paginationKey: "messages"
///         )
///     }
///
///     /// POST /api/messages
///     public static func create(_ body: CreateMessageRequest) -> Request<MessageDTO> {
///         Request(method: .post, path: "/api/messages", body: .json(body), auth: .bearer)
///     }
/// }
/// ```
///
/// Conventions every step-2 builder must follow:
///
/// 1. **One file per endpoint group** (Messages, Lists, Documents, …) named
///    `<Group>Endpoint.swift`. Each file declares a single `public enum`
///    namespace named after the group (plural where the API uses plural).
/// 2. **Factory methods return `Request<Response>`** typed to the exact DTO
///    they decode. Use `Paginated<T>` for endpoints with the
///    `{collection, pagination}` envelope and supply `paginationKey` with
///    the per-endpoint collection key (e.g. `"messages"`, `"lists"`).
/// 3. **`AuthRequirement` is set explicitly** on every request. Default to
///    `.bearer`. Use `.session` only for the decision-0001 allowlist:
///    `/api/user/identities`, `/api/user/organizations`, `/api/exports/*`.
///    Use `.none` only for unauthenticated endpoints (login, register, the
///    public profile / public-list reads).
/// 4. **Path is the URL path only** (e.g. `/api/messages/\(id)/replies`),
///    never the absolute URL — the base URL is owned by `APIClient`.
/// 5. **Query parameters use `QueryItem`** with the nil-skipping helpers
///    (`.int`, `.bool`, `.string`). Nil values are dropped automatically so
///    callers can pass through optional filters unchanged.
/// 6. **Bodies use `RequestBody.json(_:)`** with a `Codable` DTO struct.
///    For raw bytes (image / video upload), use `RequestBody.raw(_:contentType:)`.
/// 7. **Never throw from a factory.** Construction is total; failures
///    surface from the client at send time.
/// 8. **Method names use Swift conventions** — `list`, `get(id:)`,
///    `create(_:)`, `update(id:_:)`, `delete(id:)`, `replies(of:)`, etc.
public struct Request<Response>: Sendable where Response: Sendable {

    /// The HTTP verb.
    public let method: HTTPMethod

    /// The URL path beginning with `/` (e.g. `/api/messages`). Never an
    /// absolute URL — the `APIClient` joins this with its configured base.
    public let path: String

    /// Query items, applied to the URL after nil-stripping.
    public let query: [QueryItem]

    /// Optional request body. For JSON bodies, prefer `RequestBody.json(_:)`
    /// so the client can encode with the shared `JSONEncoder` configuration.
    public let body: RequestBody?

    /// Additional headers (beyond `Authorization`, `Content-Type`, `Accept`,
    /// which the client manages). Mostly empty.
    public let headers: [String: String]

    /// Authentication routing hint. See `AuthRequirement`.
    public let auth: AuthRequirement

    /// For paginated list endpoints, the JSON key under which the collection
    /// is nested in the response envelope (e.g. `"messages"`, `"lists"`).
    /// `nil` for non-paginated endpoints. Used by `Paginated<T>` decoding.
    public let paginationKey: String?

    public init(
        method: HTTPMethod,
        path: String,
        query: [QueryItem] = [],
        body: RequestBody? = nil,
        headers: [String: String] = [:],
        auth: AuthRequirement = .bearer,
        paginationKey: String? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.headers = headers
        self.auth = auth
        self.paginationKey = paginationKey
    }
}

// MARK: - QueryItem

/// A query parameter that knows how to skip itself when its value is nil.
/// Designed for endpoint builders that take many optional filters
/// (`limit`, `offset`, `tag`, `onlyMine`, `range`, …) without forcing
/// callers to build URL strings.
public struct QueryItem: Sendable, Equatable {
    public let name: String
    public let value: String?

    public init(name: String, value: String?) {
        self.name = name
        self.value = value
    }

    public static func string(_ name: String, _ value: String?) -> QueryItem {
        QueryItem(name: name, value: value)
    }

    public static func int(_ name: String, _ value: Int?) -> QueryItem {
        QueryItem(name: name, value: value.map { String($0) })
    }

    public static func bool(_ name: String, _ value: Bool?) -> QueryItem {
        QueryItem(name: name, value: value.map { $0 ? "true" : "false" })
    }
}

// MARK: - RequestBody

/// The body payload of an outbound request.
///
/// `.json` is encoded by the client's shared `JSONEncoder`; the caller
/// supplies a `Codable` value so the body is type-checked at the call site.
/// `.raw` is for media uploads where the bytes are already encoded.
public enum RequestBody: Sendable {
    case json(any Encodable & Sendable)
    case raw(Data, contentType: String)

    /// The MIME type to set on `Content-Type`.
    public var contentType: String {
        switch self {
        case .json: return "application/json"
        case .raw(_, let contentType): return contentType
        }
    }
}
