// StubDirectMessagesService
//
// Deterministic `DirectMessagesServicing` stub for App-layer view-model
// tests of the Direct Messages feature (the-gaps.md G1). Mirrors the
// project's other stubs (`StubSearchService`, `StubModerationService`):
// an actor with one FIFO outcome queue per call site + a recorded-call
// log so tests can assert both the returned value and that the right
// call was (or was not) made.
//
// The `send` guard (`DirectMessagesError.emptyMessage` on a blank body
// with no images) lives in the concrete `DirectMessagesService`, not in
// the protocol, so this stub does NOT re-implement it — a view model
// under test is expected to guard blank input itself before the service
// is reached, and the "invalid input" quartet case asserts on `recorded`
// staying empty.

import Foundation
import InterlinedDomain

struct RecordedDMCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case folder(folder: DMFolder, cursor: String?)
        case thread(username: String, cursor: String?)
        case threadUpdates(username: String, since: String?)
        case send(recipientId: String, body: String, imageURLs: [String])
        case recipients
        case unreadCount
        case markRead(id: String)
        case trash(id: String)
        case restore(id: String)
    }
    let kind: Kind
}

actor StubDirectMessagesService: DirectMessagesServicing {

    private var folderOutcomes: [Result<DMPage, Error>] = []
    private var threadOutcomes: [Result<DMThread, Error>] = []
    private var threadUpdatesOutcomes: [Result<DMThread, Error>] = []
    private var sendOutcomes: [Result<DirectMessage, Error>] = []
    private var recipientsOutcomes: [Result<[UserSummary], Error>] = []
    private var unreadCountOutcomes: [Result<Int, Error>] = []
    private var markReadOutcomes: [Result<Void, Error>] = []
    private var trashOutcomes: [Result<Void, Error>] = []
    private var restoreOutcomes: [Result<Void, Error>] = []

    private(set) var recorded: [RecordedDMCall] = []

    // MARK: Programmable enqueue helpers

    func enqueueFolder(success value: DMPage) { folderOutcomes.append(.success(value)) }
    func enqueueFolder(failure error: Error) { folderOutcomes.append(.failure(error)) }

    func enqueueThread(success value: DMThread) { threadOutcomes.append(.success(value)) }
    func enqueueThread(failure error: Error) { threadOutcomes.append(.failure(error)) }

    func enqueueThreadUpdates(success value: DMThread) { threadUpdatesOutcomes.append(.success(value)) }
    func enqueueThreadUpdates(failure error: Error) { threadUpdatesOutcomes.append(.failure(error)) }

    func enqueueSend(success value: DirectMessage) { sendOutcomes.append(.success(value)) }
    func enqueueSend(failure error: Error) { sendOutcomes.append(.failure(error)) }

    func enqueueRecipients(success value: [UserSummary]) { recipientsOutcomes.append(.success(value)) }
    func enqueueRecipients(failure error: Error) { recipientsOutcomes.append(.failure(error)) }

    func enqueueUnreadCount(success value: Int) { unreadCountOutcomes.append(.success(value)) }
    func enqueueUnreadCount(failure error: Error) { unreadCountOutcomes.append(.failure(error)) }

    func enqueueMarkReadSuccess() { markReadOutcomes.append(.success(())) }
    func enqueueMarkRead(failure error: Error) { markReadOutcomes.append(.failure(error)) }

    func enqueueTrashSuccess() { trashOutcomes.append(.success(())) }
    func enqueueTrash(failure error: Error) { trashOutcomes.append(.failure(error)) }

    func enqueueRestoreSuccess() { restoreOutcomes.append(.success(())) }
    func enqueueRestore(failure error: Error) { restoreOutcomes.append(.failure(error)) }

    // MARK: DirectMessagesServicing

    func folder(_ folder: DMFolder, cursor: String?) async throws -> DMPage {
        recorded.append(.init(kind: .folder(folder: folder, cursor: cursor)))
        return try take(&folderOutcomes, label: "folder")
    }

    func thread(username: String, cursor: String?) async throws -> DMThread {
        recorded.append(.init(kind: .thread(username: username, cursor: cursor)))
        return try take(&threadOutcomes, label: "thread")
    }

    func threadUpdates(username: String, since: String?) async throws -> DMThread {
        recorded.append(.init(kind: .threadUpdates(username: username, since: since)))
        return try take(&threadUpdatesOutcomes, label: "threadUpdates")
    }

    func send(recipientId: String, body: String, imageURLs: [String]) async throws -> DirectMessage {
        recorded.append(.init(kind: .send(recipientId: recipientId, body: body, imageURLs: imageURLs)))
        return try take(&sendOutcomes, label: "send")
    }

    func recipients() async throws -> [UserSummary] {
        recorded.append(.init(kind: .recipients))
        return try take(&recipientsOutcomes, label: "recipients")
    }

    func unreadCount() async throws -> Int {
        recorded.append(.init(kind: .unreadCount))
        return try take(&unreadCountOutcomes, label: "unreadCount")
    }

    func markRead(id: String) async throws {
        recorded.append(.init(kind: .markRead(id: id)))
        let _: Void = try take(&markReadOutcomes, label: "markRead")
    }

    func trash(id: String) async throws {
        recorded.append(.init(kind: .trash(id: id)))
        let _: Void = try take(&trashOutcomes, label: "trash")
    }

    func restore(id: String) async throws {
        recorded.append(.init(kind: .restore(id: id)))
        let _: Void = try take(&restoreOutcomes, label: "restore")
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
