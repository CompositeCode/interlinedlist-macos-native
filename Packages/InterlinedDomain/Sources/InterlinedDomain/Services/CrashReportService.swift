// CrashReportService
//
// The crash-reporting surface the App layer codes against (GitHub issue #29,
// PR 1).
//
// Why this lives in the domain layer: the payload is the tail of `AppLog`'s
// rotating file, and `AppLog` / `FileLog` are `InterlinedKit` types. Decision
// 0003 forbids `App/Features/**` from importing Kit, and `InterlinedDomain`
// already depends on Kit — so the service reads `FileLog` *here* and the App
// layer sees only `CrashReportServicing`, injected through `AppEnvironment`.
// No new architectural exception is needed.
//
// All three methods are `async` purely to keep the protocol uniform with the
// rest of the domain services and to leave room for a networked
// implementation in PR 2; today the work is synchronous file I/O.

import Foundation
import InterlinedKit

// MARK: - CrashReportServicing

public protocol CrashReportServicing: Sendable {

    /// The breadcrumb left by the previous run, if it crashed. `nil` on a
    /// clean run — which is also what a corrupt or zero-byte breadcrumb
    /// reports, because a report we cannot parse is not worth prompting about.
    func pendingReport() async -> CrashReport?

    /// Discards the breadcrumb. Called after the user sends *or* dismisses, so
    /// one crash prompts exactly once.
    func clearPendingReport() async

    /// Redacted tail of the rotating app log, capped at `maxBytes`.
    func logTail(maxBytes: Int) async -> String

    /// Where the full, unredacted log lives, so the sheet can tell the user
    /// what stayed on their machine. `nil` when file logging is disabled.
    var logFileURL: URL? { get }
}

// MARK: - CrashReportService

public final class CrashReportService: CrashReportServicing {

    private let store: CrashReportStore

    /// The previous run's breadcrumb, snapshotted **at construction**.
    ///
    /// This has to happen at init and cannot be deferred: installing the
    /// signal handler opens the breadcrumb with `O_TRUNC`, so any read after
    /// installation would find an empty file and no crash would ever be
    /// reported. `AppEnvironment.live()` therefore constructs this service
    /// first and installs the handler second, and the snapshot taken here is
    /// what the UI is offered later.
    private let snapshot: CrashReport?

    public init(store: CrashReportStore) {
        self.store = store
        self.snapshot = store.readPending()
    }

    /// Production wiring: breadcrumb and log share `FileLog`'s directory
    /// inside the sandbox container. Both are `nil` under XCTest, which makes
    /// the service inert rather than letting unit runs touch real `~/Library`.
    public convenience init(fileLog: FileLog = .shared) {
        let directory = FileLog.defaultDirectory()
        self.init(store: CrashReportStore(
            breadcrumbURL: directory?.appendingPathComponent(CrashBreadcrumbFormat.fileName),
            logURL: fileLog.currentFileURL
        ))
    }

    /// The breadcrumb path the App layer's signal handler must open at
    /// install time. Exposed here so the path is defined in exactly one place.
    public var breadcrumbURL: URL? { store.breadcrumbURL }

    public var logFileURL: URL? { store.logURL }

    public func pendingReport() async -> CrashReport? {
        snapshot
    }

    /// Clears the on-disk breadcrumb. Usually redundant — installing the
    /// handler already truncated it — but it is what keeps the contract true
    /// when the handler failed to install, and it costs a single empty write.
    public func clearPendingReport() async {
        store.clearPending()
    }

    public func logTail(maxBytes: Int) async -> String {
        store.logTail(maxBytes: maxBytes)
    }
}
