// CrashReportStore
//
// File I/O and parsing behind `CrashReportService` (GitHub issue #29, PR 1).
// Owns exactly two artifacts:
//
//   • the **breadcrumb** the previous run's signal handler wrote, and
//   • the tail of the rotating **app log** that accompanies it.
//
// Everything here is best-effort by construction. The store runs on the launch
// path, so a missing directory, an unreadable file or a garbage payload must
// degrade to "no pending report" — never to a throw, and never to a crash
// while reporting a crash. Accordingly nothing in this type is `throws`.

import Foundation

public struct CrashReportStore: Sendable {

    /// Hard ceiling on how much breadcrumb we will read. A runaway backtrace
    /// (mutual recursion unwinding through thousands of frames) could produce
    /// an arbitrarily large file; reading it whole on the launch path is the
    /// only way this code could hurt a user who is already having a bad day.
    public static let maxBreadcrumbBytes = 256 * 1024

    /// Hard ceiling on frames kept from one block, for the same reason.
    public static let maxFrames = 128

    /// Where the crashing process leaves its breadcrumb. `nil` disables the
    /// store entirely (every call becomes a no-op) — that is what happens
    /// under XCTest, because `FileLog.defaultDirectory()` returns `nil` there
    /// and unit runs must never touch the real `~/Library`.
    public let breadcrumbURL: URL?

    /// The rotating app log whose tail is attached to a report.
    public let logURL: URL?

    public init(breadcrumbURL: URL?, logURL: URL?) {
        self.breadcrumbURL = breadcrumbURL
        self.logURL = logURL
    }

    // MARK: - Breadcrumb

    /// Reads and parses the breadcrumb left by the previous run.
    ///
    /// Returns `nil` for every "there was no crash" shape: no file, a
    /// zero-byte file (the handler opens the file at install and only writes
    /// to it while dying, so a clean run leaves it empty), a file that does
    /// not start with our magic line, or a block too damaged to yield a
    /// signal number.
    public func readPending() -> CrashReport? {
        guard let breadcrumbURL, let data = readCapped(breadcrumbURL, limit: Self.maxBreadcrumbBytes) else {
            return nil
        }
        // Lossy on purpose: a partial UTF-8 sequence at the truncation point
        // must degrade to U+FFFD, not throw away the whole report.
        return Self.parse(String(decoding: data, as: UTF8.self))
    }

    /// Removes the breadcrumb so the prompt does not reappear on the next
    /// launch. Truncation rather than deletion, because the handler is holding
    /// an open descriptor on this inode — unlinking it would leave the handler
    /// writing into a file nobody can find.
    public func clearPending() {
        guard let breadcrumbURL else { return }
        try? Data().write(to: breadcrumbURL, options: [])
    }

    // MARK: - Log tail

    /// Last `maxBytes` of the rotating app log, **already redacted**.
    ///
    /// The tail is trimmed forward to the first newline after cutting. That is
    /// not cosmetic: cutting a fixed number of bytes off the end of a log can
    /// land in the middle of a bearer token, and the leading fragment of a
    /// token no longer matches any deny-list rule. Dropping the partial first
    /// line makes a split credential structurally impossible. It also disposes
    /// of any partial UTF-8 sequence at the same cut.
    public func logTail(maxBytes: Int) -> String {
        guard maxBytes > 0, let logURL else { return "" }
        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return "" }
        defer { try? handle.close() }

        let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? nil
        let byteCount = size ?? 0
        var truncated = false
        if byteCount > maxBytes {
            try? handle.seek(toOffset: UInt64(byteCount - maxBytes))
            truncated = true
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return "" }

        var text = String(decoding: data, as: UTF8.self)
        if truncated, let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }
        return CrashReportRedactor.redact(text)
    }

    // MARK: - Parsing

    /// Parses the **first complete block** of a breadcrumb file.
    ///
    /// A file can hold two blocks: the uncaught-`NSException` handler writes
    /// one, then the `SIGABRT` that follows makes the signal handler append
    /// another. First-block-wins is what we want — the exception block carries
    /// a name and reason, the signal block only a number.
    ///
    /// Exposed `internal` for tests; the production path goes through
    /// `readPending()`.
    static func parse(_ text: String) -> CrashReport? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(of: CrashBreadcrumbFormat.magic) else { return nil }

        var fields: [String: String] = [:]
        var frames: [String] = []
        var inFrames = false

        for line in lines[(start + 1)...] {
            // A second `magic` ends this block — the next block is a duplicate
            // report of the same death and is discarded.
            if line == CrashBreadcrumbFormat.magic { break }
            if line == CrashBreadcrumbFormat.endMarker { break }
            if line == CrashBreadcrumbFormat.framesMarker { inFrames = true; continue }
            if inFrames {
                guard frames.count < Self.maxFrames else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { frames.append(trimmed) }
                continue
            }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<separator])
            let value = String(line[line.index(after: separator)...])
            fields[key] = value
        }

        // The signal number is the one field that must be present and valid —
        // without it the block is a fragment written before the handler got
        // anywhere, and there is nothing worth prompting about.
        guard let rawSignal = fields["signal"], let signal = Int32(rawSignal) else { return nil }

        let occurredAt = fields["occurred"]
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))
            ?? Date()

        return CrashReport(
            signal: signal,
            name: fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? CrashReport.signalName(signal),
            // The writer escapes newlines so a multi-line exception reason
            // stays on one physical line; undo that here.
            reason: fields["reason"].flatMap { $0.isEmpty ? nil : $0.replacingOccurrences(of: "\\n", with: "\n") },
            frames: frames,
            appVersion: fields["version"] ?? "unknown",
            build: fields["build"] ?? "unknown",
            osVersion: fields["os"] ?? "unknown",
            occurredAt: occurredAt
        )
    }

    // MARK: - Helpers

    /// Reads at most `limit` bytes from `url`, returning `nil` for a missing,
    /// unreadable or empty file. Never throws: this runs at launch.
    private func readCapped(_ url: URL, limit: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit), !data.isEmpty else { return nil }
        return data
    }
}
