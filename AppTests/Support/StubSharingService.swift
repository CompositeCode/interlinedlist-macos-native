// StubSharingService
//
// Deterministic `SharingServicing` stub for App-layer view-model tests of
// the Share Links feature (work-consolidation.md G3). Mirrors the project's other
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

        // Document collaborators
        case documentCollaborators(documentId: String)
        case searchCollaborators(documentId: String, query: String)
        case addCollaborator(documentId: String, userId: String, role: ShareRole, notify: Bool)
        case setCollaboratorRole(documentId: String, userId: String, role: ShareRole, notify: Bool)
        case removeCollaborator(documentId: String, userId: String)

        // Email invites (documents + lists)
        case documentInvites(documentId: String)
        case createDocumentInvite(documentId: String, email: String, role: ShareRole, expiresAt: Date?)
        case revokeDocumentInvite(documentId: String, token: String)
        case listInvites(listId: String)
        case createListInvite(listId: String, email: String, role: ShareRole, expiresAt: Date?)
        case revokeListInvite(listId: String, token: String)
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

    // Collaborators.
    private var collaboratorsOutcomes: [Result<[Collaborator], Error>] = []
    private var candidatesOutcomes: [Result<[CollaboratorCandidate], Error>] = []
    private var addCollaboratorOutcomes: [Result<Void, Error>] = []
    private var setRoleOutcomes: [Result<Void, Error>] = []
    private var removeCollaboratorOutcomes: [Result<Bool, Error>] = []

    // Email invites (shared across list/document halves, like the link queues).
    private var invitesOutcomes: [Result<[ShareInvite], Error>] = []
    private var createInviteOutcomes: [Result<SentInvite, Error>] = []
    private var revokeInviteOutcomes: [Result<Bool, Error>] = []

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

    func enqueueCollaborators(success value: [Collaborator]) { collaboratorsOutcomes.append(.success(value)) }
    func enqueueCollaborators(failure error: Error) { collaboratorsOutcomes.append(.failure(error)) }

    func enqueueCandidates(success value: [CollaboratorCandidate]) { candidatesOutcomes.append(.success(value)) }
    func enqueueCandidates(failure error: Error) { candidatesOutcomes.append(.failure(error)) }

    func enqueueAddCollaboratorSuccess() { addCollaboratorOutcomes.append(.success(())) }
    func enqueueAddCollaborator(failure error: Error) { addCollaboratorOutcomes.append(.failure(error)) }

    func enqueueSetRoleSuccess() { setRoleOutcomes.append(.success(())) }
    func enqueueSetRole(failure error: Error) { setRoleOutcomes.append(.failure(error)) }

    func enqueueRemoveCollaborator(success value: Bool) { removeCollaboratorOutcomes.append(.success(value)) }
    func enqueueRemoveCollaborator(failure error: Error) { removeCollaboratorOutcomes.append(.failure(error)) }

    func enqueueInvites(success value: [ShareInvite]) { invitesOutcomes.append(.success(value)) }
    func enqueueInvites(failure error: Error) { invitesOutcomes.append(.failure(error)) }

    func enqueueCreateInvite(success value: SentInvite) { createInviteOutcomes.append(.success(value)) }
    func enqueueCreateInvite(failure error: Error) { createInviteOutcomes.append(.failure(error)) }

    func enqueueRevokeInvite(success value: Bool) { revokeInviteOutcomes.append(.success(value)) }
    func enqueueRevokeInvite(failure error: Error) { revokeInviteOutcomes.append(.failure(error)) }

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

    // MARK: SharingServicing — Document collaborators

    func documentCollaborators(documentId: String) async throws -> [Collaborator] {
        recorded.append(.init(kind: .documentCollaborators(documentId: documentId)))
        return try take(&collaboratorsOutcomes, label: "documentCollaborators")
    }

    func searchDocumentCollaborators(documentId: String, query: String) async throws -> [CollaboratorCandidate] {
        recorded.append(.init(kind: .searchCollaborators(documentId: documentId, query: query)))
        return try take(&candidatesOutcomes, label: "searchDocumentCollaborators")
    }

    func addDocumentCollaborator(documentId: String, userId: String, role: ShareRole, notify: Bool) async throws {
        recorded.append(.init(kind: .addCollaborator(documentId: documentId, userId: userId, role: role, notify: notify)))
        try take(&addCollaboratorOutcomes, label: "addDocumentCollaborator")
    }

    func setDocumentCollaboratorRole(documentId: String, userId: String, role: ShareRole, notify: Bool) async throws {
        recorded.append(.init(kind: .setCollaboratorRole(documentId: documentId, userId: userId, role: role, notify: notify)))
        try take(&setRoleOutcomes, label: "setDocumentCollaboratorRole")
    }

    func removeDocumentCollaborator(documentId: String, userId: String) async throws -> Bool {
        recorded.append(.init(kind: .removeCollaborator(documentId: documentId, userId: userId)))
        return try take(&removeCollaboratorOutcomes, label: "removeDocumentCollaborator")
    }

    // MARK: SharingServicing — Email invites (documents + lists)

    func documentInvites(documentId: String) async throws -> [ShareInvite] {
        recorded.append(.init(kind: .documentInvites(documentId: documentId)))
        return try take(&invitesOutcomes, label: "documentInvites")
    }

    func createDocumentInvite(documentId: String, email: String, role: ShareRole, expiresAt: Date?) async throws -> SentInvite {
        recorded.append(.init(kind: .createDocumentInvite(documentId: documentId, email: email, role: role, expiresAt: expiresAt)))
        return try take(&createInviteOutcomes, label: "createDocumentInvite")
    }

    func revokeDocumentInvite(documentId: String, token: String) async throws -> Bool {
        recorded.append(.init(kind: .revokeDocumentInvite(documentId: documentId, token: token)))
        return try take(&revokeInviteOutcomes, label: "revokeDocumentInvite")
    }

    func listInvites(listId: String) async throws -> [ShareInvite] {
        recorded.append(.init(kind: .listInvites(listId: listId)))
        return try take(&invitesOutcomes, label: "listInvites")
    }

    func createListInvite(listId: String, email: String, role: ShareRole, expiresAt: Date?) async throws -> SentInvite {
        recorded.append(.init(kind: .createListInvite(listId: listId, email: email, role: role, expiresAt: expiresAt)))
        return try take(&createInviteOutcomes, label: "createListInvite")
    }

    func revokeListInvite(listId: String, token: String) async throws -> Bool {
        recorded.append(.init(kind: .revokeListInvite(listId: listId, token: token)))
        return try take(&revokeInviteOutcomes, label: "revokeListInvite")
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
