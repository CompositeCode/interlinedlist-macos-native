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

    /// Rate-limit metadata parsed from the pull response headers. `nil` when
    /// the route does not emit `RateLimit-Limit` / `RateLimit-Remaining` /
    /// `RateLimit-Reset` headers — the sync engine must interpret `nil` as
    /// "no limit enforced on this route" and proceed at full pace.
    public let rateLimitInfo: RateLimitInfo?

    public init(
        syncedAt: Date? = nil,
        folders: [FolderNode] = [],
        documents: [Document] = [],
        rateLimitInfo: RateLimitInfo? = nil
    ) {
        self.syncedAt = syncedAt
        self.folders = folders
        self.documents = documents
        self.rateLimitInfo = rateLimitInfo
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
        let (dto, rateLimitInfo) = try await api.sendWithRateLimitInfo(
            Documents.sync(lastSyncAt: sinceParam)
        )
        // rateLimitInfo is nil when the route does not enforce a limit —
        // the caller (sync engine) should proceed at full pace in that case.
        return DocumentSyncDelta(
            syncedAt: dto.syncedAt,
            folders: dto.folders.map(FolderNode.init(from:)),
            documents: dto.documents.map(Document.init(from:)),
            rateLimitInfo: rateLimitInfo
        )
    }

    public func pushChange(_ change: DocumentChange) async throws {
        let op = DocumentSyncOperation(from: change)
        let batch = DocumentSyncRequest(operations: [op])
        let (_, rateLimitInfo) = try await api.sendWithRateLimitInfo(Documents.pushSync(batch))
        // When rateLimitInfo is nil this route enforces no limit — proceed at
        // full pace. When non-nil, future pacing logic would throttle here
        // (e.g. back off when remaining approaches zero).
        guard rateLimitInfo != nil else { return }
        // Pacing placeholder — not yet implemented; surfaced when headers arrive.
    }
}
