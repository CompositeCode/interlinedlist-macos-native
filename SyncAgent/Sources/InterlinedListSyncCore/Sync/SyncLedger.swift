import Foundation
import os

/// Per-document snapshot from the last successful sync. Used to decide whether
/// the local file, the remote document, or both have changed since.
public struct LedgerEntry: Codable, Sendable, Equatable {
    public var remoteUpdatedAt: Date
    public var contentHash: String
    public var folderId: String?
    /// Full relative file path last written (folder + filename). Doubles as a
    /// fallback correlation key when an atomic save strips the xattr id.
    public var relativeFilePath: String

    public init(remoteUpdatedAt: Date, contentHash: String, folderId: String?, relativeFilePath: String) {
        self.remoteUpdatedAt = remoteUpdatedAt
        self.contentHash = contentHash
        self.folderId = folderId
        self.relativeFilePath = relativeFilePath
    }
}

/// A known folder, so the engine can compute a document's mirrored path.
public struct FolderRecord: Codable, Sendable, Equatable {
    public var name: String
    public var parentId: String?
    public init(name: String, parentId: String?) {
        self.name = name
        self.parentId = parentId
    }
}

/// The complete on-disk sync state: cursor, per-document entries, folder map.
public struct LedgerData: Codable, Sendable, Equatable {
    public var lastSyncAt: Date?
    public var cycleCount: Int
    public var entries: [String: LedgerEntry]
    public var folders: [String: FolderRecord]

    public init(
        lastSyncAt: Date? = nil,
        cycleCount: Int = 0,
        entries: [String: LedgerEntry] = [:],
        folders: [String: FolderRecord] = [:]
    ) {
        self.lastSyncAt = lastSyncAt
        self.cycleCount = cycleCount
        self.entries = entries
        self.folders = folders
    }

    /// Resolves the mirrored folder path for `folderId` from the folder map,
    /// walking parents. Cycles and missing links degrade gracefully to root.
    public func relativePath(forFolderId folderId: String?, sanitize: (String) -> String) -> String {
        guard let folderId else { return "" }
        var components: [String] = []
        var current: String? = folderId
        var guardCounter = 0
        while let id = current, let record = folders[id], guardCounter < 64 {
            components.insert(sanitize(record.name), at: 0)
            current = record.parentId
            guardCounter += 1
        }
        return components.joined(separator: "/")
    }
}

/// Persistence port for the ledger.
public protocol LedgerStoring: Sendable {
    func load() -> LedgerData
    func save(_ data: LedgerData)
}

/// JSON-file-backed ledger under Application Support.
public struct FileLedgerStore: LedgerStoring {
    private let url: URL
    private let logger = Logger(subsystem: SyncConfiguration.logSubsystem, category: "Ledger")

    public init(url: URL) {
        self.url = url
    }

    /// Default location: `~/Library/Application Support/com.interlinedlist.macos.sync/ledger.json`.
    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(SyncConfiguration.bundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ledger.json")
    }

    public func load() -> LedgerData {
        guard let data = try? Data(contentsOf: url) else { return LedgerData() }
        do {
            return try JSONCoding.makeDecoder().decode(LedgerData.self, from: data)
        } catch {
            logger.error("Ledger decode failed; starting fresh: \(error.localizedDescription, privacy: .public)")
            return LedgerData()
        }
    }

    public func save(_ data: LedgerData) {
        do {
            let encoded = try JSONCoding.makeEncoder().encode(data)
            try encoded.write(to: url, options: .atomic)
        } catch {
            logger.error("Ledger save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// In-memory ledger for tests.
public final class InMemoryLedgerStore: LedgerStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var data: LedgerData

    public init(_ initial: LedgerData = LedgerData()) { self.data = initial }

    public func load() -> LedgerData {
        lock.lock(); defer { lock.unlock() }
        return data
    }

    public func save(_ data: LedgerData) {
        lock.lock(); defer { lock.unlock() }
        self.data = data
    }
}
