import Foundation

/// High-level state of the sync service, surfaced in the menu bar.
public enum SyncStatus: Sendable, Equatable {
    case idle
    case syncing
    case paused
    case offline
    case signedOut
    case authExpired
    case error(String)
}

/// Errors the engine can raise during a cycle.
public enum SyncError: Error, Sendable, Equatable {
    case notAuthenticated
    case authExpired
    case offline
    case noSyncFolder
    case rateLimited(retryAfter: TimeInterval?)
    case api(APIError)
    case fileSystem(String)
}

/// Summary of a completed cycle, for notifications and the menu.
public struct SyncSummary: Sendable, Equatable {
    public var pulled: Int
    public var pushed: Int
    public var created: Int
    public var deletedLocal: Int
    public var deletedRemote: Int
    public var conflicts: Int
    public var finishedAt: Date

    public init(
        pulled: Int = 0, pushed: Int = 0, created: Int = 0,
        deletedLocal: Int = 0, deletedRemote: Int = 0, conflicts: Int = 0,
        finishedAt: Date
    ) {
        self.pulled = pulled
        self.pushed = pushed
        self.created = created
        self.deletedLocal = deletedLocal
        self.deletedRemote = deletedRemote
        self.conflicts = conflicts
        self.finishedAt = finishedAt
    }

    public var changeCount: Int {
        pulled + pushed + created + deletedLocal + deletedRemote + conflicts
    }
}

/// Events emitted by the engine for the UI layer to consume on the main actor.
public enum SyncEvent: Sendable {
    case statusChanged(SyncStatus)
    case cycleCompleted(SyncSummary)
    case conflictCreated(fileName: String)
    case authRequired
}
