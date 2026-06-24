// StubNotificationsService
//
// Deterministic `NotificationsServicing` stub for App-layer view-model
// tests of the M5 notifications tray. Mirrors the project's other
// stubs: actor with one FIFO outcome queue per call site + recorded
// calls.

import Foundation
import InterlinedDomain

struct RecordedNotificationsCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case tray
        case markRead(id: String)
        case markAllRead
    }
    let kind: Kind
}

actor StubNotificationsService: NotificationsServicing {

    private var trayOutcomes: [Result<NotificationTray, Error>] = []
    private var markReadOutcomes: [Result<Void, Error>] = []
    private var markAllReadOutcomes: [Result<Void, Error>] = []

    private(set) var recorded: [RecordedNotificationsCall] = []

    func enqueueTray(success tray: NotificationTray) { trayOutcomes.append(.success(tray)) }
    func enqueueTray(failure error: Error) { trayOutcomes.append(.failure(error)) }

    func enqueueMarkReadSuccess() { markReadOutcomes.append(.success(())) }
    func enqueueMarkRead(failure error: Error) { markReadOutcomes.append(.failure(error)) }

    func enqueueMarkAllReadSuccess() { markAllReadOutcomes.append(.success(())) }
    func enqueueMarkAllRead(failure error: Error) { markAllReadOutcomes.append(.failure(error)) }

    func tray() async throws -> NotificationTray {
        recorded.append(.init(kind: .tray))
        return try take(&trayOutcomes, label: "tray")
    }

    func markRead(id: String) async throws {
        recorded.append(.init(kind: .markRead(id: id)))
        let _: Void = try take(&markReadOutcomes, label: "markRead")
    }

    func markAllRead() async throws {
        recorded.append(.init(kind: .markAllRead))
        let _: Void = try take(&markAllReadOutcomes, label: "markAllRead")
    }

    private func take<T>(_ queue: inout [Result<T, Error>], label: String) throws -> T {
        guard !queue.isEmpty else {
            throw StubError.noOutcome(label: label)
        }
        switch queue.removeFirst() {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    enum StubError: Error, Equatable {
        case noOutcome(label: String)
    }
}
