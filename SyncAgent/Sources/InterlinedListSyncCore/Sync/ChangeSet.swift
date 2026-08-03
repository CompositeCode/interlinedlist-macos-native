import Foundation

/// Normalized remote view of one document for diffing.
public struct RemoteDocState: Sendable, Equatable {
    public let id: String
    public let title: String
    public let content: String?
    public let folderId: String?
    public let updatedAt: Date
    public let isDeleted: Bool

    public init(id: String, title: String, content: String?, folderId: String?, updatedAt: Date, isDeleted: Bool) {
        self.id = id
        self.title = title
        self.content = content
        self.folderId = folderId
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}

/// Normalized local view of one tracked document for diffing.
public struct LocalDocState: Sendable, Equatable {
    public let id: String
    public let url: URL
    public let title: String
    public let contentHash: String
    public let folderRelativePath: String
    public let modifiedAt: Date

    public init(id: String, url: URL, title: String, contentHash: String, folderRelativePath: String, modifiedAt: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.contentHash = contentHash
        self.folderRelativePath = folderRelativePath
        self.modifiedAt = modifiedAt
    }
}

/// The set of actions to reconcile one cycle. Ids reference documents; `create`
/// references untracked local files; `adopt` records already-in-sync docs into
/// the ledger without any I/O.
public struct SyncPlan: Sendable, Equatable {
    public var pull: [String] = []
    public var push: [String] = []
    public var conflict: [String] = []
    public var deleteLocal: [String] = []
    public var deleteRemote: [String] = []
    public var create: [URL] = []
    public var adopt: [String] = []
    public var noOp: [String] = []

    public var isEmpty: Bool {
        pull.isEmpty && push.isEmpty && conflict.isEmpty && deleteLocal.isEmpty
            && deleteRemote.isEmpty && create.isEmpty
    }
}

/// Pure reconciliation planner. No I/O — takes normalized snapshots and returns
/// a plan the engine executes.
public enum ChangeSet {

    /// - Parameters:
    ///   - remote: remote docs under consideration, keyed by id. In a delta
    ///     cycle this is just the changed docs; in a full cycle it is every
    ///     server document.
    ///   - remoteIsComplete: `true` for a full-list cycle — enables deletion
    ///     detection (a ledger/local id absent from `remote` means deleted).
    ///     `false` for a delta cycle — absent ids are assumed unchanged.
    ///   - tracked: local files carrying a sync id, keyed by id.
    ///   - untracked: local `.md` files without an id (new local documents).
    ///   - ledger: last-synced snapshot, keyed by id.
    public static func compute(
        remote: [String: RemoteDocState],
        remoteIsComplete: Bool,
        tracked: [String: LocalDocState],
        untracked: [ScannedDocument],
        ledger: [String: LedgerEntry]
    ) -> SyncPlan {
        var plan = SyncPlan()

        let ids = Set(remote.keys).union(tracked.keys).union(ledger.keys)
        for id in ids {
            let remoteDoc = remote[id]
            let local = tracked[id]
            let base = ledger[id]

            let inRemoteView = remoteDoc != nil
            let remoteExists: Bool
            let remoteChanged: Bool
            if let remoteDoc {
                remoteExists = !remoteDoc.isDeleted
                remoteChanged = base == nil || remoteDoc.updatedAt != base!.remoteUpdatedAt
            } else if remoteIsComplete {
                // Full cycle and not present → the server no longer has it.
                remoteExists = false
                remoteChanged = false
            } else {
                // Delta cycle: unseen means unchanged, still present.
                remoteExists = true
                remoteChanged = false
            }

            let localExists = local != nil
            let localChanged: Bool = {
                guard let local else { return false }
                return base == nil || local.contentHash != base!.contentHash
            }()

            // Fresh-ledger fast path: both present, no baseline, but content
            // already matches → adopt into the ledger, no conflict copy.
            if base == nil, let local, inRemoteView, let remoteDoc, remoteExists,
               let content = remoteDoc.content,
               local.contentHash == ContentHash.sha256(content) {
                plan.adopt.append(id)
                continue
            }

            switch ConflictResolver.decide(
                localChanged: localChanged,
                remoteChanged: remoteChanged,
                localExists: localExists,
                remoteExists: remoteExists
            ) {
            case .pull:         plan.pull.append(id)
            case .push:         plan.push.append(id)
            case .conflictCopy: plan.conflict.append(id)
            case .deleteLocal:  plan.deleteLocal.append(id)
            case .deleteRemote: plan.deleteRemote.append(id)
            case .noOp:         plan.noOp.append(id)
            }
        }

        // Untracked local files are brand-new documents to create on the server.
        for file in untracked where file.documentID == nil {
            plan.create.append(file.url)
        }

        return plan
    }
}
