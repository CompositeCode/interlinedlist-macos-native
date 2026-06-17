import Foundation

/// An in-memory `MessageStore`, used as the default cache in tests and in any
/// context that has no persistence layer wired up yet. The real, durable
/// implementation is the SwiftData store in `InterlinedPersistence`.
///
/// Implemented as an `actor` so its mutable state is safe under Swift 6 strict
/// concurrency without manual locking.
public actor InMemoryMessageStore: MessageStore {

    /// Cache key for a timeline slice: a scope combined with an optional tag.
    /// The two together identify a distinct cached feed.
    private struct TimelineKey: Hashable {
        let scope: TimelineScope
        let tag: String?
    }

    private var timelines: [TimelineKey: [Message]] = [:]
    private var messagesByID: [String: Message] = [:]

    public init() {}

    public func cachedTimeline(scope: TimelineScope, tag: String?) async -> [Message] {
        timelines[TimelineKey(scope: scope, tag: tag)] ?? []
    }

    public func replaceTimeline(_ messages: [Message], scope: TimelineScope, tag: String?) async {
        timelines[TimelineKey(scope: scope, tag: tag)] = messages
        for message in messages {
            messagesByID[message.id] = message
        }
    }

    public func cachedMessage(id: String) async -> Message? {
        messagesByID[id]
    }

    public func upsert(_ messages: [Message]) async {
        for message in messages {
            messagesByID[message.id] = message
        }
    }

    public func clear() async {
        timelines.removeAll()
        messagesByID.removeAll()
    }
}
