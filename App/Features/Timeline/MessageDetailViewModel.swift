// MessageDetailViewModel
//
// Drives `MessageDetailView`: loads a single message plus its first
// page of replies. Replies are kept flat for M1; the indented thread
// tree lands in M2 alongside reply composition (PLAN.md §1, §6).
//
// Reads through `MessagesServicing` only, so a stub service drives
// tests without any networking.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class MessageDetailViewModel {

    static let pageSize: Int = 50

    private let messages: MessagesServicing
    private let messageID: String

    private(set) var message: Message?
    private(set) var replies: [Message] = []
    private(set) var isLoading: Bool = false
    private(set) var error: Error?

    init(messages: MessagesServicing, messageID: String) {
        self.messages = messages
        self.messageID = messageID
    }

    /// Loads the message and its first page of replies in parallel.
    /// Either failure surfaces as `error` and the other half is still
    /// populated when it succeeds — partial results beat an empty
    /// detail screen.
    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        async let messageResult = loadMessage()
        async let repliesResult = loadReplies()

        let (loadedMessage, loadedReplies) = await (messageResult, repliesResult)

        if let loadedMessage { self.message = loadedMessage }
        if let loadedReplies { self.replies = loadedReplies }
    }

    /// Re-fetches both halves; bound to the detail view's
    /// `.refreshable` modifier.
    func refresh() async {
        await load()
    }

    private func loadMessage() async -> Message? {
        do {
            return try await messages.message(id: messageID)
        } catch {
            self.error = error
            return nil
        }
    }

    private func loadReplies() async -> [Message]? {
        do {
            return try await messages.replies(of: messageID, limit: Self.pageSize, offset: 0)
        } catch {
            // Don't clobber a message-load error with a replies-load
            // error — the first failure is the more actionable one.
            if self.error == nil { self.error = error }
            return nil
        }
    }
}
