// StubModerationService
//
// Deterministic `ModerationServicing` stub for App-layer view-model tests
// of the moderation feature (the-gaps.md G2). Mirrors the project's other
// stubs: an actor with one FIFO outcome queue per call site + a recorded-
// call log.

import Foundation
import InterlinedDomain

struct RecordedModerationCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case blockedUsers(limit: Int, offset: Int)
        case mutedUsers(limit: Int, offset: Int)
        case block(username: String)
        case unblock(username: String)
        case mute(username: String)
        case unmute(username: String)
        case reportUser(username: String, reason: ReportReason, detail: String?)
        case reportMessage(id: String, reason: ReportReason, detail: String?)
        case isBlocking(username: String)
    }
    let kind: Kind
}

actor StubModerationService: ModerationServicing {

    private var blockedOutcomes: [Result<[ModeratedUser], Error>] = []
    private var mutedOutcomes: [Result<[ModeratedUser], Error>] = []
    private var blockOutcomes: [Result<Void, Error>] = []
    private var unblockOutcomes: [Result<Void, Error>] = []
    private var muteOutcomes: [Result<Void, Error>] = []
    private var unmuteOutcomes: [Result<Void, Error>] = []
    private var reportUserOutcomes: [Result<Void, Error>] = []
    private var reportMessageOutcomes: [Result<Void, Error>] = []
    private var isBlockingOutcomes: [Result<Bool, Error>] = []

    private(set) var recorded: [RecordedModerationCall] = []

    // MARK: Programmable enqueue helpers

    func enqueueBlocked(success value: [ModeratedUser]) { blockedOutcomes.append(.success(value)) }
    func enqueueBlocked(failure error: Error) { blockedOutcomes.append(.failure(error)) }

    func enqueueMuted(success value: [ModeratedUser]) { mutedOutcomes.append(.success(value)) }
    func enqueueMuted(failure error: Error) { mutedOutcomes.append(.failure(error)) }

    func enqueueBlockSuccess() { blockOutcomes.append(.success(())) }
    func enqueueBlock(failure error: Error) { blockOutcomes.append(.failure(error)) }

    func enqueueUnblockSuccess() { unblockOutcomes.append(.success(())) }
    func enqueueUnblock(failure error: Error) { unblockOutcomes.append(.failure(error)) }

    func enqueueMuteSuccess() { muteOutcomes.append(.success(())) }
    func enqueueMute(failure error: Error) { muteOutcomes.append(.failure(error)) }

    func enqueueUnmuteSuccess() { unmuteOutcomes.append(.success(())) }
    func enqueueUnmute(failure error: Error) { unmuteOutcomes.append(.failure(error)) }

    func enqueueReportUserSuccess() { reportUserOutcomes.append(.success(())) }
    func enqueueReportUser(failure error: Error) { reportUserOutcomes.append(.failure(error)) }

    func enqueueReportMessageSuccess() { reportMessageOutcomes.append(.success(())) }
    func enqueueReportMessage(failure error: Error) { reportMessageOutcomes.append(.failure(error)) }

    func enqueueIsBlocking(success value: Bool) { isBlockingOutcomes.append(.success(value)) }
    func enqueueIsBlocking(failure error: Error) { isBlockingOutcomes.append(.failure(error)) }

    // MARK: ModerationServicing

    func blockedUsers(limit: Int, offset: Int) async throws -> [ModeratedUser] {
        recorded.append(.init(kind: .blockedUsers(limit: limit, offset: offset)))
        return try take(&blockedOutcomes, label: "blockedUsers")
    }

    func mutedUsers(limit: Int, offset: Int) async throws -> [ModeratedUser] {
        recorded.append(.init(kind: .mutedUsers(limit: limit, offset: offset)))
        return try take(&mutedOutcomes, label: "mutedUsers")
    }

    func block(username: String) async throws {
        recorded.append(.init(kind: .block(username: username)))
        let _: Void = try take(&blockOutcomes, label: "block")
    }

    func unblock(username: String) async throws {
        recorded.append(.init(kind: .unblock(username: username)))
        let _: Void = try take(&unblockOutcomes, label: "unblock")
    }

    func mute(username: String) async throws {
        recorded.append(.init(kind: .mute(username: username)))
        let _: Void = try take(&muteOutcomes, label: "mute")
    }

    func unmute(username: String) async throws {
        recorded.append(.init(kind: .unmute(username: username)))
        let _: Void = try take(&unmuteOutcomes, label: "unmute")
    }

    func reportUser(username: String, reason: ReportReason, detail: String?) async throws {
        recorded.append(.init(kind: .reportUser(username: username, reason: reason, detail: detail)))
        let _: Void = try take(&reportUserOutcomes, label: "reportUser")
    }

    func reportMessage(id: String, reason: ReportReason, detail: String?) async throws {
        recorded.append(.init(kind: .reportMessage(id: id, reason: reason, detail: detail)))
        let _: Void = try take(&reportMessageOutcomes, label: "reportMessage")
    }

    func isBlocking(username: String) async throws -> Bool {
        recorded.append(.init(kind: .isBlocking(username: username)))
        return try take(&isBlockingOutcomes, label: "isBlocking")
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
