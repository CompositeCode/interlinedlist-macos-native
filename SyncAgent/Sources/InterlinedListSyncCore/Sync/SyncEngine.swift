import Foundation
import os

/// Orchestrates one sync cycle: pull remote deltas, diff against the local
/// folder + ledger, apply changes both directions, and persist the ledger.
///
/// An `actor`, so cycles never overlap. Driven by a poll timer and FSEvents; a
/// manual "Sync Now" calls ``syncNow()`` directly. Reports progress through the
/// ``events`` stream for the UI to render on the main actor.
public actor SyncEngine {

    // MARK: - Dependencies

    private let api: any DocumentSyncAPI
    private let mapper: DocumentMapper
    private let ledgerStore: any LedgerStoring
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: SyncConfiguration.logSubsystem, category: "SyncEngine")

    private var watcher: (any FileWatching)?
    private var network: (any NetworkMonitoring)?

    // MARK: - State

    private var ledger: LedgerData
    private var status: SyncStatus = .idle
    private var isPaused = false
    private var isCycling = false
    private var pollInterval: TimeInterval
    private var pollTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    public let events: AsyncStream<SyncEvent>
    private let eventContinuation: AsyncStream<SyncEvent>.Continuation

    public init(
        api: any DocumentSyncAPI,
        mapper: DocumentMapper,
        ledgerStore: any LedgerStoring,
        pollInterval: TimeInterval = SyncConfiguration.defaultPollInterval,
        watcher: (any FileWatching)? = nil,
        network: (any NetworkMonitoring)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.mapper = mapper
        self.ledgerStore = ledgerStore
        self.pollInterval = pollInterval
        self.watcher = watcher
        self.network = network
        self.now = now
        self.ledger = ledgerStore.load()

        var captured: AsyncStream<SyncEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(32)) { captured = $0 }
        self.eventContinuation = captured
    }

    // MARK: - Lifecycle

    public func start() {
        guard pollTask == nil else { return }
        try? mapper.ensureFolder(relativePath: "")

        if let network {
            network.setOnChange { [weak self] online in
                guard let self else { return }
                Task { await self.networkChanged(online: online) }
            }
            network.start()
        }

        if let watcher {
            watcher.start()
            let stream = watcher.changes
            watchTask = Task { [weak self] in
                for await _ in stream {
                    guard let self else { return }
                    // Debounce bursts, then sync.
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await self.syncNow(trigger: .fileChange)
                }
            }
        }

        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.pollLoop()
        }
    }

    public func stop() {
        pollTask?.cancel(); pollTask = nil
        watchTask?.cancel(); watchTask = nil
        watcher?.stop()
        network?.stop()
    }

    public func pause() {
        isPaused = true
        updateStatus(.paused)
    }

    public func resume() {
        isPaused = false
        updateStatus(.idle)
        Task { await self.syncNow(trigger: .manual) }
    }

    public func setPollInterval(_ interval: TimeInterval) {
        pollInterval = min(max(interval, SyncConfiguration.minPollInterval), SyncConfiguration.maxPollInterval)
    }

    public func currentStatus() -> SyncStatus { status }
    public func lastSyncAt() -> Date? { ledger.lastSyncAt }

    /// Clears the ledger so the next cycle rebuilds from a full server fetch.
    public func resetLedger() {
        ledger = LedgerData()
        ledgerStore.save(ledger)
    }

    // MARK: - Poll loop

    private func pollLoop() async {
        while !Task.isCancelled {
            await syncNow(trigger: .poll)
            let delay = backoffDelay() ?? pollInterval
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func networkChanged(online: Bool) async {
        if online {
            if status == .offline { updateStatus(.idle) }
            await syncNow(trigger: .manual)
        } else {
            updateStatus(.offline)
        }
    }

    private func backoffDelay() -> TimeInterval? {
        guard consecutiveFailures > 0 else { return nil }
        let base = pow(2.0, Double(min(consecutiveFailures, 8)))
        return min(base, SyncConfiguration.maxBackoff)
    }

    // MARK: - Cycle

    public enum Trigger: Sendable { case poll, manual, fileChange }

    /// Runs a single reconciliation cycle if not already running / paused.
    public func syncNow(trigger: Trigger = .manual) async {
        guard !isCycling else { return }
        if isPaused, trigger != .manual { return }
        if let network, !network.isCurrentlyOnline() {
            updateStatus(.offline)
            return
        }

        isCycling = true
        defer { isCycling = false }
        if status != .paused { updateStatus(.syncing) }

        do {
            let summary = try await runCycle()
            consecutiveFailures = 0
            if status != .paused { updateStatus(.idle) }
            emit(.cycleCompleted(summary))
        } catch {
            handle(error)
        }
    }

    /// Executes one cycle and returns its summary. Extracted for testability —
    /// call directly with a fake API to assert reconciliation behavior.
    /// - Parameter forceFullReconcile: forces the authoritative full-list pass
    ///   (deletion detection) regardless of the cycle counter.
    @discardableResult
    public func runCycle(forceFullReconcile: Bool = false) async throws -> SyncSummary {
        let fullReconcile = forceFullReconcile
            || ledger.lastSyncAt == nil
            || (ledger.cycleCount % SyncConfiguration.fullReconcileEveryNCycles == 0)

        // 1. Pull delta (advances the cursor and carries changed content).
        let delta = try await api.fetchDelta(since: ledger.lastSyncAt)
        mergeFolders(delta.folders)

        var remote: [String: RemoteDocState] = [:]
        for d in delta.documents {
            remote[d.id] = RemoteDocState(
                id: d.id, title: d.title, content: d.content,
                folderId: d.folderId, updatedAt: d.updatedAt, isDeleted: d.isDeleted
            )
        }

        // 2. On a full cycle, fetch the authoritative list to detect deletions.
        var remoteIsComplete = false
        if fullReconcile {
            let allFolders = try await api.fetchAllFolders()
            mergeFolders(allFolders)
            let allDocs = try await api.fetchAllDocuments()
            let liveIDs = Set(allDocs.map(\.id))
            for doc in allDocs where remote[doc.id] == nil {
                remote[doc.id] = RemoteDocState(
                    id: doc.id, title: doc.title, content: doc.content,
                    folderId: doc.folderId, updatedAt: doc.updatedAt, isDeleted: false
                )
            }
            // Anything we know about but the server no longer lists is deleted.
            for id in Set(ledger.entries.keys) where !liveIDs.contains(id) {
                remote[id] = RemoteDocState(
                    id: id, title: "", content: nil, folderId: nil,
                    updatedAt: now(), isDeleted: true
                )
            }
            remoteIsComplete = true
        }

        // 3. Scan the local folder.
        let scanned = try mapper.scan()
        var tracked: [String: LocalDocState] = [:]
        var untracked: [ScannedDocument] = []
        for file in scanned {
            if let id = file.documentID {
                tracked[id] = localState(id: id, file: file)
            } else {
                untracked.append(file)
            }
        }

        // Fallback correlation: editors that save atomically strip the xattr, so
        // a file can lose its id while keeping its path. Re-associate by path
        // from the ledger and re-stamp the xattr.
        if !untracked.isEmpty {
            var pathToID: [String: String] = [:]
            for (id, entry) in ledger.entries { pathToID[entry.relativeFilePath] = id }
            var stillUntracked: [ScannedDocument] = []
            for file in untracked {
                let rel = mapper.relativeFilePath(of: file.url)
                if let id = pathToID[rel], tracked[id] == nil {
                    mapper.setDocumentID(id, at: file.url)
                    tracked[id] = localState(id: id, file: file)
                } else {
                    stillUntracked.append(file)
                }
            }
            untracked = stillUntracked
        }
        let scannedByURL = Dictionary(uniqueKeysWithValues: scanned.map { ($0.url, $0) })

        // 4. Plan.
        let plan = ChangeSet.compute(
            remote: remote,
            remoteIsComplete: remoteIsComplete,
            tracked: tracked,
            untracked: untracked,
            ledger: ledger.entries
        )

        // 5. Execute.
        var summary = SyncSummary(finishedAt: now())
        let reverseFolderMap = buildReverseFolderMap()

        for id in plan.pull { try await applyPull(id: id, remote: remote, tracked: tracked); summary.pulled += 1 }
        for id in plan.conflict {
            try await applyConflict(id: id, remote: remote, tracked: tracked, scannedByURL: scannedByURL)
            summary.conflicts += 1
        }
        for id in plan.push { try await applyPush(id: id, tracked: tracked, scannedByURL: scannedByURL); summary.pushed += 1 }
        for url in plan.create {
            if let file = scannedByURL[url] {
                try await applyCreate(file: file, reverseFolderMap: reverseFolderMap)
                summary.created += 1
            }
        }
        for id in plan.deleteLocal { applyDeleteLocal(id: id, tracked: tracked); summary.deletedLocal += 1 }
        for id in plan.deleteRemote { try await applyDeleteRemote(id: id); summary.deletedRemote += 1 }
        for id in plan.adopt { applyAdopt(id: id, remote: remote, tracked: tracked) }

        // 6. Advance cursor + persist.
        ledger.lastSyncAt = delta.lastSyncAt ?? ledger.lastSyncAt ?? now()
        ledger.cycleCount += 1
        ledgerStore.save(ledger)
        summary.finishedAt = now()
        return summary
    }

    // MARK: - Action handlers

    private func applyPull(id: String, remote: [String: RemoteDocState], tracked: [String: LocalDocState]) async throws {
        guard let doc = remote[id] else { return }
        let content = try await resolveContent(for: doc)
        let relativePath = ledger.relativePath(forFolderId: doc.folderId, sanitize: mapper.sanitizeFilename)
        let url = try mapper.place(
            id: id, title: doc.title, content: content,
            folderRelativePath: relativePath, currentURL: tracked[id]?.url
        )
        recordEntry(id: id, remoteUpdatedAt: doc.updatedAt, content: content, folderId: doc.folderId, url: url)
    }

    private func applyConflict(
        id: String,
        remote: [String: RemoteDocState],
        tracked: [String: LocalDocState],
        scannedByURL: [URL: ScannedDocument]
    ) async throws {
        guard let doc = remote[id], let local = tracked[id] else { return }
        let localBody = scannedByURL[local.url]?.body ?? ((try? String(contentsOf: local.url, encoding: .utf8)) ?? "")
        let copyURL = try mapper.writeConflictCopy(of: local.url, body: localBody, at: now())
        emit(.conflictCreated(fileName: copyURL.lastPathComponent))
        try await applyPull(id: id, remote: remote, tracked: tracked)
    }

    private func applyPush(id: String, tracked: [String: LocalDocState], scannedByURL: [URL: ScannedDocument]) async throws {
        guard let local = tracked[id] else { return }
        let body = scannedByURL[local.url]?.body ?? ((try? String(contentsOf: local.url, encoding: .utf8)) ?? "")
        let folderId = ledger.entries[id]?.folderId
        let updated = try await api.updateDocument(
            id: id,
            UpdateDocumentBody(title: local.title, content: body, folderId: folderId)
        )
        recordEntry(id: id, remoteUpdatedAt: updated.updatedAt, content: body, folderId: folderId, url: local.url)
    }

    private func applyCreate(file: ScannedDocument, reverseFolderMap: [String: String]) async throws {
        let folderId = reverseFolderMap[file.folderRelativePath]
        let created = try await api.createDocument(
            CreateDocumentBody(title: file.title, content: file.body, folderId: folderId)
        )
        mapper.adopt(id: created.id, at: file.url)
        recordEntry(
            id: created.id, remoteUpdatedAt: created.updatedAt,
            content: file.body, folderId: folderId, url: file.url
        )
    }

    private func applyDeleteLocal(id: String, tracked: [String: LocalDocState]) {
        if let url = tracked[id]?.url { mapper.removeFile(at: url) }
        ledger.entries[id] = nil
    }

    private func applyDeleteRemote(id: String) async throws {
        try await api.deleteDocument(id: id)
        ledger.entries[id] = nil
    }

    private func applyAdopt(id: String, remote: [String: RemoteDocState], tracked: [String: LocalDocState]) {
        guard let doc = remote[id], let local = tracked[id] else { return }
        ledger.entries[id] = LedgerEntry(
            remoteUpdatedAt: doc.updatedAt,
            contentHash: local.contentHash,
            folderId: doc.folderId,
            relativeFilePath: mapper.relativeFilePath(of: local.url)
        )
    }

    // MARK: - Helpers

    private func resolveContent(for doc: RemoteDocState) async throws -> String {
        if let content = doc.content { return content }
        // List/delta metadata omitted the body — fetch the detail.
        let detail = try await api.fetchDocument(id: doc.id)
        return detail.content ?? ""
    }

    private func localState(id: String, file: ScannedDocument) -> LocalDocState {
        LocalDocState(
            id: id, url: file.url, title: file.title, contentHash: file.contentHash,
            folderRelativePath: file.folderRelativePath, modifiedAt: file.modifiedAt
        )
    }

    private func recordEntry(id: String, remoteUpdatedAt: Date, content: String, folderId: String?, url: URL) {
        ledger.entries[id] = LedgerEntry(
            remoteUpdatedAt: remoteUpdatedAt,
            contentHash: ContentHash.sha256(content),
            folderId: folderId,
            relativeFilePath: mapper.relativeFilePath(of: url)
        )
    }

    private func mergeFolders(_ folders: [RemoteFolder]) {
        for folder in folders {
            if folder.isDeleted {
                ledger.folders[folder.id] = nil
            } else {
                ledger.folders[folder.id] = FolderRecord(name: folder.name, parentId: folder.parentId)
            }
        }
    }

    /// Maps a mirrored folder relative-path back to its server folder id, so a
    /// new local file inside a known folder is created under the right parent.
    private func buildReverseFolderMap() -> [String: String] {
        var map: [String: String] = [:]
        for (id, _) in ledger.folders {
            let path = ledger.relativePath(forFolderId: id, sanitize: mapper.sanitizeFilename)
            if !path.isEmpty { map[path] = id }
        }
        return map
    }

    // MARK: - Status & errors

    private func updateStatus(_ new: SyncStatus) {
        guard new != status else { return }
        status = new
        emit(.statusChanged(new))
    }

    private func emit(_ event: SyncEvent) {
        eventContinuation.yield(event)
    }

    private func handle(_ error: Error) {
        consecutiveFailures += 1
        switch error {
        case APIError.noToken:
            updateStatus(.signedOut)
            emit(.authRequired)
        case APIError.unauthorized:
            updateStatus(.authExpired)
            emit(.authRequired)
        case APIError.rateLimited(let retryAfter):
            logger.error("Rate limited; retry after \(retryAfter ?? -1, privacy: .public)s")
            updateStatus(.idle)
        case APIError.transport:
            updateStatus(.offline)
        default:
            logger.error("Sync cycle failed: \(String(describing: error), privacy: .public)")
            updateStatus(.error(String(describing: error)))
        }
    }
}
