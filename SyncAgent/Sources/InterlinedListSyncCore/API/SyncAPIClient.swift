import Foundation
import os

/// Errors surfaced by the API layer, mapped from HTTP status + transport.
public enum APIError: Error, Sendable, Equatable {
    case noToken
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case notFound
    case http(status: Int, body: String?)
    case transport(String)
    case decoding(String)
    case invalidResponse
}

/// The document-sync operations the engine needs. A protocol so tests can
/// substitute an in-memory fake server.
public protocol DocumentSyncAPI: Sendable {
    func fetchDelta(since: Date?) async throws -> DeltaResponse
    func fetchAllDocuments() async throws -> [RemoteDocument]
    func fetchDocument(id: String) async throws -> RemoteDocument
    func createDocument(_ body: CreateDocumentBody) async throws -> RemoteDocument
    func updateDocument(id: String, _ body: UpdateDocumentBody) async throws -> RemoteDocument
    func deleteDocument(id: String) async throws
    func fetchAllFolders() async throws -> [RemoteFolder]
    func createFolder(_ body: CreateFolderBody) async throws -> RemoteFolder
}

/// URLSession-backed client for the InterlinedList Documents API. Reads the
/// bearer token fresh on every request via the injected ``TokenProviding`` so a
/// mid-run sign-in / sign-out in the main app is picked up immediately.
public actor SyncAPIClient: DocumentSyncAPI {

    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: any TokenProviding
    private let decoder = JSONCoding.makeDecoder()
    private let encoder = JSONCoding.makeEncoder()
    private let logger = Logger(subsystem: SyncConfiguration.logSubsystem, category: "API")

    /// Page size for the full-list reconciliation fetch.
    private let pageLimit = 200

    public init(
        baseURL: URL = SyncConfiguration.apiBaseURL,
        tokenProvider: any TokenProviding,
        session: URLSession = SyncAPIClient.makeSession()
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }

    // MARK: - DocumentSyncAPI

    public func fetchDelta(since: Date?) async throws -> DeltaResponse {
        var query: [URLQueryItem] = []
        if let since {
            query.append(URLQueryItem(name: "lastSyncAt", value: JSONCoding.iso8601String(since)))
        }
        let request = try makeRequest(method: "GET", path: "/api/documents/sync", query: query)
        return try await perform(request, as: DeltaResponse.self)
    }

    public func fetchAllDocuments() async throws -> [RemoteDocument] {
        var all: [RemoteDocument] = []
        var offset = 0
        while true {
            let query = [
                URLQueryItem(name: "limit", value: String(pageLimit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            let request = try makeRequest(method: "GET", path: "/api/documents", query: query)
            let page = try await perform(request, as: DocumentListResponse.self)
            all.append(contentsOf: page.documents)
            if page.documents.count < pageLimit { break }
            offset += pageLimit
            if offset > 100_000 { break } // safety valve
        }
        return all
    }

    public func fetchDocument(id: String) async throws -> RemoteDocument {
        let request = try makeRequest(method: "GET", path: "/api/documents/\(pathEncode(id))")
        return try await decodeDocument(request)
    }

    public func createDocument(_ body: CreateDocumentBody) async throws -> RemoteDocument {
        let request = try makeRequest(method: "POST", path: "/api/documents", jsonBody: body)
        return try await decodeDocument(request)
    }

    public func updateDocument(id: String, _ body: UpdateDocumentBody) async throws -> RemoteDocument {
        let request = try makeRequest(method: "PATCH", path: "/api/documents/\(pathEncode(id))", jsonBody: body)
        return try await decodeDocument(request)
    }

    public func deleteDocument(id: String) async throws {
        let request = try makeRequest(method: "DELETE", path: "/api/documents/\(pathEncode(id))")
        // 404 = already gone = success.
        try await performVoid(request, treating404AsSuccess: true)
    }

    public func fetchAllFolders() async throws -> [RemoteFolder] {
        var all: [RemoteFolder] = []
        var offset = 0
        while true {
            let query = [
                URLQueryItem(name: "limit", value: String(pageLimit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            let request = try makeRequest(method: "GET", path: "/api/documents/folders", query: query)
            let page = try await perform(request, as: FolderListResponse.self)
            all.append(contentsOf: page.folders)
            if page.folders.count < pageLimit { break }
            offset += pageLimit
            if offset > 100_000 { break }
        }
        return all
    }

    public func createFolder(_ body: CreateFolderBody) async throws -> RemoteFolder {
        let request = try makeRequest(method: "POST", path: "/api/documents/folders", jsonBody: body)
        let (data, _) = try await sendExpectingSuccess(request)
        if let env = try? decoder.decode(FolderEnvelope.self, from: data), let folder = env.folder {
            return folder
        }
        do {
            return try decoder.decode(RemoteFolder.self, from: data)
        } catch {
            throw APIError.decoding("\(error)")
        }
    }

    // MARK: - Request building

    private func makeRequest(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        jsonBody: (any Encodable & Sendable)? = nil
    ) throws -> URLRequest {
        guard let token = tokenProvider.currentToken() else { throw APIError.noToken }

        // Build `<base><path>` with a single separating slash. `path` always
        // begins with `/api/...`; trim any trailing slash on the base.
        let base = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        guard var components = URLComponents(string: base + path) else {
            throw APIError.invalidResponse
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(jsonBody))
        }
        return request
    }

    private func pathEncode(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }

    // MARK: - Perform

    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, _) = try await sendExpectingSuccess(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Decode \(String(describing: T.self)) failed: \(error.localizedDescription, privacy: .public)")
            throw APIError.decoding("\(error)")
        }
    }

    /// Detail/create/update responses may be `{document:…}` (live) or the bare
    /// object (per the older contract). Tolerate both.
    private func decodeDocument(_ request: URLRequest) async throws -> RemoteDocument {
        let (data, _) = try await sendExpectingSuccess(request)
        if let env = try? decoder.decode(DocumentEnvelope.self, from: data), let doc = env.document {
            return doc
        }
        do {
            return try decoder.decode(RemoteDocument.self, from: data)
        } catch {
            throw APIError.decoding("\(error)")
        }
    }

    private func performVoid(_ request: URLRequest, treating404AsSuccess: Bool) async throws {
        do {
            _ = try await sendExpectingSuccess(request)
        } catch APIError.notFound where treating404AsSuccess {
            return
        }
    }

    /// Sends the request and returns the body for 2xx responses; maps error codes.
    private func sendExpectingSuccess(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch http.statusCode {
        case 200...299:
            return (data, http)
        case 401, 403:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited(retryAfter: Self.retryAfter(from: http))
        default:
            let body = String(data: data, encoding: .utf8)
            throw APIError.http(status: http.statusCode, body: body)
        }
    }

    /// Parses the `Retry-After` header (integer seconds or HTTP-date).
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)) {
            return seconds
        }
        if let date = JSONCoding.parseISO8601(value) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }
}

/// Type-erased `Encodable` so a heterogeneous request body can be encoded.
private struct AnyEncodable: Encodable {
    private let encodeClosure: @Sendable (Encoder) throws -> Void
    init(_ wrapped: any Encodable & Sendable) {
        self.encodeClosure = { encoder in try wrapped.encode(to: encoder) }
    }
    func encode(to encoder: Encoder) throws { try encodeClosure(encoder) }
}
