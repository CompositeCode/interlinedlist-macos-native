import Foundation

// MARK: - Search response envelopes
//
// The three search endpoints reuse the existing resource DTOs for their rows
// (`MessageDTO`, `ListDTO`, `DocumentDTO`) wrapped under a per-resource
// collection key. Shapes verified live 2026-07-31 (authenticated Bearer probe):
//
//   GET /api/messages/search?q=…  -> { "messages": [MessageDTO] }        (POST → 405)
//   GET /api/lists/search?q=…     -> { "lists": [ListDTO], "pagination": {…} }
//   GET /api/documents/search?q=… -> { "documents": [DocumentDTO] }
//
// `pagination` is modelled optional because messages/documents search omit the
// envelope today while lists search includes it. Decoding tolerates both.

/// `GET /api/messages/search` response.
public struct MessageSearchResponse: Decodable, Sendable, Equatable {
    public let messages: [MessageDTO]
    public let pagination: PaginationInfo?

    public init(messages: [MessageDTO], pagination: PaginationInfo? = nil) {
        self.messages = messages
        self.pagination = pagination
    }
}

/// `GET /api/lists/search` response.
public struct ListSearchResponse: Decodable, Sendable, Equatable {
    public let lists: [ListDTO]
    public let pagination: PaginationInfo?

    public init(lists: [ListDTO], pagination: PaginationInfo? = nil) {
        self.lists = lists
        self.pagination = pagination
    }
}

/// `GET /api/documents/search` response.
public struct DocumentSearchResponse: Decodable, Sendable, Equatable {
    public let documents: [DocumentDTO]
    public let pagination: PaginationInfo?

    public init(documents: [DocumentDTO], pagination: PaginationInfo? = nil) {
        self.documents = documents
        self.pagination = pagination
    }
}
