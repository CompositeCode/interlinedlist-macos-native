// StubCrashReportService
//
// Deterministic `CrashReportServicing` stub for `CrashReportingViewModelTests`
// (GitHub issue #29, PR 1). Follows the same lock-guarded pattern as the
// project's other service stubs and returns only `InterlinedDomain` values —
// no InterlinedKit, no real files, no signal handler.

import Foundation
import InterlinedDomain

final class StubCrashReportService: CrashReportServicing, @unchecked Sendable {

    private let lock = NSLock()
    private var _pending: CrashReport?
    private var _logTail: String
    private var _clearCount = 0
    private var _requestedTailBytes: [Int] = []

    let logFileURL: URL?

    init(
        pending: CrashReport? = nil,
        logTail: String = "",
        logFileURL: URL? = URL(fileURLWithPath: "/tmp/interlinedlist.log")
    ) {
        self._pending = pending
        self._logTail = logTail
        self.logFileURL = logFileURL
    }

    // MARK: - Assertions

    /// How many times the breadcrumb was cleared. A submission failure must
    /// leave this at zero so the user can retry on the next launch.
    var clearCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _clearCount
    }

    /// Byte caps the view model asked for, so tests can assert the log tail
    /// was actually requested rather than assumed empty.
    var requestedTailBytes: [Int] {
        lock.lock(); defer { lock.unlock() }
        return _requestedTailBytes
    }

    // MARK: - CrashReportServicing

    // The locking lives in synchronous helpers: `NSLock.lock()` is unavailable
    // from an async context, and these protocol methods are `async`.

    func pendingReport() async -> CrashReport? { readPending() }

    func clearPendingReport() async { recordClear() }

    func logTail(maxBytes: Int) async -> String { readTail(maxBytes: maxBytes) }

    private func readPending() -> CrashReport? {
        lock.lock(); defer { lock.unlock() }
        return _pending
    }

    private func recordClear() {
        lock.lock(); defer { lock.unlock() }
        _clearCount += 1
        _pending = nil
    }

    private func readTail(maxBytes: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        _requestedTailBytes.append(maxBytes)
        return _logTail
    }
}

extension CrashReport {

    /// Canonical fixture — a SIGSEGV with two frames.
    static func stub(
        signal: Int32 = 11,
        name: String = "SIGSEGV",
        reason: String? = nil,
        frames: [String] = [
            "0   InterlinedList   0x0000000104a1b2c3 $s14InterlinedList8CrasherC4bangyyF + 40",
            "1   InterlinedList   0x0000000104a1b300 $s14InterlinedList8CrasherC4bootyyF + 12"
        ]
    ) -> CrashReport {
        CrashReport(
            signal: signal,
            name: name,
            reason: reason,
            frames: frames,
            appVersion: "0.1.0",
            build: "42",
            osVersion: "15.4.0",
            occurredAt: Date(timeIntervalSince1970: 1_757_160_000)
        )
    }
}
