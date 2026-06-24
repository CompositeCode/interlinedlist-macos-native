import Foundation
import InterlinedKit

// MARK: - DocumentSyncDelta

/// Pure-domain projection of the wire sync delta. Decouples the sync engine
/// (in `InterlinedPersistence`) from the kit DTOs so the persistence package
/// stays Kit-free.
public struct DocumentSyncDelta: Sendable, Equatable {

    /// The server's "as of" timestamp for this delta. `nil` when the API
    /// omitted it (the engine then falls back to its injected clock).
    public let syncedAt: Date?
    public let folders: [FolderNode]
    public let documents: [Document]

    public init(
        syncedAt: Date? = nil,
        folders: [FolderNode] = [],
        documents: [Document] = []
    ) {
        self.syncedAt = syncedAt
        self.folders = folders
        self.documents = documents
    }
}

// MARK: - DocumentSyncTransport

/// The two operations the `DocumentSyncEngine` needs from the network — the
/// delta pull and the batched outbox push. Implemented by
/// `KitDocumentSyncTransport` (kit-backed) and a stub in tests.
///
/// Exists as a domain seam so `InterlinedPersistence` doesn't have to
/// `import InterlinedKit` to host the sync engine — the engine consumes
/// this protocol instead. Wire mapping stays in the domain layer where the
/// DTO knowledge already lives.
public protocol DocumentSyncTransport: Sendable {
    /// Pull a delta. `since` is the engine's last cursor; `nil` for a full
    /// snapshot.
    func pullDelta(since: Date?) async throws -> DocumentSyncDelta

    /// Push one queued change. The kit endpoint takes batches but the
    /// engine sends one-at-a-time so a failure attribution per row stays
    /// trivial. If/when batching matters for throughput, this can grow a
    /// `pushBatch(_:)` overload without breaking the per-row path.
    func pushChange(_ change: DocumentChange) async throws
}

// MARK: - KitDocumentSyncTransport

/// Kit-backed implementation. Wraps `Documents.sync` / `Documents.pushSync`
/// and projects the response DTOs through the domain mappers.
public final class KitDocumentSyncTransport: DocumentSyncTransport {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func pullDelta(since: Date?) async throws -> DocumentSyncDelta {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let sinceParam = since.map(formatter.string(from:))
        let response = try await api.send(Documents.sync(lastSyncAt: sinceParam))
        return DocumentSyncDelta(
            syncedAt: response.syncedAt,
            folders: response.folders.map(FolderNode.init(from:)),
            documents: response.documents.map(Document.init(from:))
        )
    }

    public func pushChange(_ change: DocumentChange) async throws {
        let op = DocumentSyncOperation(from: change)
        let batch = DocumentSyncRequest(operations: [op])
        _ = try await api.send(Documents.pushSync(batch))
    }
}
