// StubSearchService
//
// Deterministic `SearchServicing` stub for App-layer view-model tests of
// the global search feature (the-gaps.md G5). Mirrors the project's other
// stubs: an actor with one FIFO outcome queue per resource + a recorded-
// call log.
//
// The three per-resource entry points (`messages` / `lists` / `documents`)
// are what the default `all(query:)` protocol extension fans out to, so
// staging the three queues drives `all(query:)` end-to-end. Blank queries
// are short-circuited by the extension before reaching the stub, so a
// blank-query test asserts on `recorded` being empty.

import Foundation
import InterlinedDomain

struct RecordedSearchCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case messages(query: String, limit: Int, offset: Int)
        case lists(query: String, limit: Int, offset: Int)
        case documents(query: String, limit: Int, offset: Int)
    }
    let kind: Kind
}

actor StubSearchService: SearchServicing {

    private var messagesOutcomes: [Result<[Message], Error>] = []
    private var listsOutcomes: [Result<[ListSummary], Error>] = []
    private var documentsOutcomes: [Result<[Document], Error>] = []

    private(set) var recorded: [RecordedSearchCall] = []

    // MARK: Programmable enqueue helpers

    func enqueueMessages(success value: [Message]) { messagesOutcomes.append(.success(value)) }
    func enqueueMessages(failure error: Error) { messagesOutcomes.append(.failure(error)) }

    func enqueueLists(success value: [ListSummary]) { listsOutcomes.append(.success(value)) }
    func enqueueLists(failure error: Error) { listsOutcomes.append(.failure(error)) }

    func enqueueDocuments(success value: [Document]) { documentsOutcomes.append(.success(value)) }
    func enqueueDocuments(failure error: Error) { documentsOutcomes.append(.failure(error)) }

    /// Stages a full happy-path `all(query:)` result in one call.
    func enqueueAll(messages: [Message], lists: [ListSummary], documents: [Document]) {
        messagesOutcomes.append(.success(messages))
        listsOutcomes.append(.success(lists))
        documentsOutcomes.append(.success(documents))
    }

    // MARK: SearchServicing

    func messages(query: String, limit: Int, offset: Int) async throws -> [Message] {
        recorded.append(.init(kind: .messages(query: query, limit: limit, offset: offset)))
        return try take(&messagesOutcomes, label: "messages")
    }

    func lists(query: String, limit: Int, offset: Int) async throws -> [ListSummary] {
        recorded.append(.init(kind: .lists(query: query, limit: limit, offset: offset)))
        return try take(&listsOutcomes, label: "lists")
    }

    func documents(query: String, limit: Int, offset: Int) async throws -> [Document] {
        recorded.append(.init(kind: .documents(query: query, limit: limit, offset: offset)))
        return try take(&documentsOutcomes, label: "documents")
    }

    private func take<T>(_ queue: inout [Result<T, Error>], label: String) throws -> T {
        guard !queue.isEmpty else { throw StubError.noOutcome(label: label) }
        switch queue.removeFirst() {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    enum StubError: Error, Equatable {
        case noOutcome(label: String)
    }
}
