// StubSharingService
//
// Deterministic `SharingServicing` stub for App-layer view-model tests of
// the Share Links feature (the-gaps.md G3). Mirrors the project's other
// stubs: an actor with one FIFO outcome queue per call site + a recorded-
// call log so tests can assert *what* was called (and, for the invalid-
// input quartet member, that nothing was called).
//
// The list and document halves of the protocol share queues keyed by the
// logical operation (`listLinks` / `create` / `revoke` / `resolve` /
// `claim`) — a given view model only ever drives one half, so a single
// queue per operation keeps staging terse. `recorded` disambiguates by
// carrying the resource kind + id in each entry.

import Foundation
import InterlinedDomain

struct RecordedSharingCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case listLinks(listId: String)
        case createListLink(listId: String, role: ShareRole, expiresAt: Date?)
        case revokeListLink(listId: String, token: String)
        case resolveList(token: String)
        case claimList(token: String)

        case documentLinks(documentId: String)
        case createDocumentLink(documentId: String, role: ShareRole, expiresAt: Date?)
        case revokeDocumentLink(documentId: String, token: String)
        case resolveDocument(token: String)
        case claimDocument(token: String)
    }
    let kind: Kind
}

actor StubSharingService: SharingServicing {

    // Per-operation FIFO queues, shared across list/document halves.
    private var linksOutcomes: [Result<[ShareLink], Error>] = []
    private var createOutcomes: [Result<ShareLink, Error>] = []
    private var revokeOutcomes: [Result<Bool, Error>] = []
    private var resolveOutcomes: [Result<ResolvedShare, Error>] = []
    private var claimOutcomes: [Result<ShareClaim, Error>] = []

    private(set) var recorded: [RecordedSharingCall] = []

    // MARK: Programmable enqueue helpers

    func enqueueLinks(success value: [ShareLink]) { linksOutcomes.append(.success(value)) }
    func enqueueLinks(failure error: Error) { linksOutcomes.append(.failure(error)) }

    func enqueueCreate(success value: ShareLink) { createOutcomes.append(.success(value)) }
    func enqueueCreate(failure error: Error) { createOutcomes.append(.failure(error)) }

    func enqueueRevoke(success value: Bool) { revokeOutcomes.append(.success(value)) }
    func enqueueRevoke(failure error: Error) { revokeOutcomes.append(.failure(error)) }

    func enqueueResolve(success value: ResolvedShare) { resolveOutcomes.append(.success(value)) }
    func enqueueResolve(failure error: Error) { resolveOutcomes.append(.failure(error)) }

    func enqueueClaim(success value: ShareClaim) { claimOutcomes.append(.success(value)) }
    func enqueueClaim(failure error: Error) { claimOutcomes.append(.failure(error)) }

    // MARK: SharingServicing — Lists

    func listShareLinks(listId: String) async throws -> [ShareLink] {
        recorded.append(.init(kind: .listLinks(listId: listId)))
        return try take(&linksOutcomes, label: "listShareLinks")
    }

    func createListShareLink(listId: String, role: ShareRole, expiresAt: Date?) async throws -> ShareLink {
        recorded.append(.init(kind: .createListLink(listId: listId, role: role, expiresAt: expiresAt)))
        return try take(&createOutcomes, label: "createListShareLink")
    }

    func revokeListShareLink(listId: String, token: String) async throws -> Bool {
        recorded.append(.init(kind: .revokeListLink(listId: listId, token: token)))
        return try take(&revokeOutcomes, label: "revokeListShareLink")
    }

    func resolveListShare(token: String) async throws -> ResolvedShare {
        recorded.append(.init(kind: .resolveList(token: token)))
        return try take(&resolveOutcomes, label: "resolveListShare")
    }

    func claimListShare(token: String) async throws -> ShareClaim {
        recorded.append(.init(kind: .claimList(token: token)))
        return try take(&claimOutcomes, label: "claimListShare")
    }

    // MARK: SharingServicing — Documents

    func documentShareLinks(documentId: String) async throws -> [ShareLink] {
        recorded.append(.init(kind: .documentLinks(documentId: documentId)))
        return try take(&linksOutcomes, label: "documentShareLinks")
    }

    func createDocumentShareLink(documentId: String, role: ShareRole, expiresAt: Date?) async throws -> ShareLink {
        recorded.append(.init(kind: .createDocumentLink(documentId: documentId, role: role, expiresAt: expiresAt)))
        return try take(&createOutcomes, label: "createDocumentShareLink")
    }

    func revokeDocumentShareLink(documentId: String, token: String) async throws -> Bool {
        recorded.append(.init(kind: .revokeDocumentLink(documentId: documentId, token: token)))
        return try take(&revokeOutcomes, label: "revokeDocumentShareLink")
    }

    func resolveDocumentShare(token: String) async throws -> ResolvedShare {
        recorded.append(.init(kind: .resolveDocument(token: token)))
        return try take(&resolveOutcomes, label: "resolveDocumentShare")
    }

    func claimDocumentShare(token: String) async throws -> ShareClaim {
        recorded.append(.init(kind: .claimDocument(token: token)))
        return try take(&claimOutcomes, label: "claimDocumentShare")
    }

    // MARK: - Queue plumbing

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
