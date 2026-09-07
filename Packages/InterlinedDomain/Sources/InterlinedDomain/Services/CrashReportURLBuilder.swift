// CrashReportURLBuilder
//
// Composes the GitHub issue text for a recovered crash and turns it into a
// prefilled `issues/new` URL (GitHub issue #29, PR 1). Pure and synchronous —
// no network, no auth, no secrets.
//
// Why a prefilled URL rather than an API call: it works for *every* user,
// including signed-out ones and ones who have never linked a GitHub identity,
// it needs no shipped credential (a PAT in a distributed app is a leaked PAT),
// and pressing **Submit** on GitHub's own page is itself the user confirmation
// issue #29 asks for. The one-click API path (`GitHubServicing.createIssue`)
// is the PR 2 upgrade for users who *are* linked; it does not replace this.

import Foundation

public enum CrashReportURLBuilder {

    /// The repository crash reports are filed against. Public, with issues
    /// enabled — which is exactly why everything reaching it goes through
    /// `CrashReportRedactor` first.
    public static let defaultRepo = "CompositeCode/interlinedlist-macos-native"

    /// Ceiling on the finished URL.
    ///
    /// GitHub's front end rejects an over-long request line rather than
    /// truncating it, and a rejected URL would strand the user on an error
    /// page with their report gone. 7,500 characters sits comfortably under
    /// the usual 8 KB request-line limit with room for the host and path.
    public static let maxURLLength = 7_500

    /// Bytes of log tail offered by default. Roughly what survives encoding
    /// into the budget above once the backtrace has taken its share.
    public static let defaultLogTailBytes = 4_000

    // MARK: - Title

    /// `Crash: SIGSEGV (a1b2c3d4)` — the signature prefix is in the title so
    /// duplicates are visible at a glance in the issue list, and so PR 2's
    /// dedup lookup can match on it.
    public static func issueTitle(for report: CrashReport) -> String {
        "Crash: \(report.name) (\(report.shortSignature))"
    }

    // MARK: - Body

    /// Composes the default issue body.
    ///
    /// Ordered most- to least-essential, because truncation happens from the
    /// end: the environment table (which carries the signature) is first, then
    /// the user's note, then the backtrace, and the log tail last. Whatever
    /// gets cut, the report still identifies the crash.
    ///
    /// - Parameters:
    ///   - report: the recovered crash.
    ///   - userNote: the optional "what were you doing?" text.
    ///   - logTail: **already redacted** log text. This function does not
    ///     redact — `CrashReportStore.logTail(maxBytes:)` did, and doing it
    ///     twice would hide a bug in that path rather than surface it.
    ///   - logFilePath: where the full log stayed, shown as reassurance.
    public static func issueBody(
        for report: CrashReport,
        userNote: String = "",
        logTail: String = "",
        logFilePath: String? = nil
    ) -> String {
        var sections: [String] = []

        let timestamp = ISO8601DateFormatter().string(from: report.occurredAt)
        sections.append("""
        ### Crash

        | | |
        | --- | --- |
        | Signal | `\(report.name)`\(report.isException ? "" : " (\(report.signal))") |
        | Signature | `\(report.signature)` |
        | Version | \(report.appVersion) (\(report.build)) |
        | macOS | \(report.osVersion) |
        | Occurred | \(timestamp) |
        """)

        if let reason = report.reason, !reason.isEmpty {
            sections.append("**Reason:** \(reason)")
        }

        let note = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            sections.append("### What I was doing\n\n\(note)")
        }

        if !report.frames.isEmpty {
            let frames = CrashReportRedactor.redact(frames: report.frames).joined(separator: "\n")
            sections.append("### Backtrace\n\n```\n\(frames)\n```")
        }

        let trimmedLog = logTail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLog.isEmpty {
            sections.append("### Log tail (redacted)\n\n```\n\(trimmedLog)\n```")
        }

        var footer = "<sub>Filed from InterlinedList for macOS. Sensitive values were removed before this text was shown to me."
        if let logFilePath {
            footer += " The full log stayed on my Mac at `\(logFilePath)`."
        }
        footer += "</sub>"
        sections.append(footer)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - URL

    /// Builds the prefilled `issues/new` URL, shrinking `body` from the end
    /// until the encoded URL fits `maxLength`.
    ///
    /// Trimming is done on the *raw* text at a line boundary and the result is
    /// re-encoded from scratch, so a truncated body can never leave a broken
    /// percent-escape behind. An unbalanced code fence left by the cut is
    /// closed so the rendered issue stays readable, and the truncation is
    /// disclosed in the body rather than happening silently.
    ///
    /// Returns `nil` only if the title alone cannot fit — a loud failure is
    /// better than handing the user a link GitHub will reject.
    public static func issueURL(
        repo: String = defaultRepo,
        title: String,
        body: String,
        maxLength: Int = maxURLLength
    ) -> URL? {
        let base = "https://github.com/\(repo)/issues/new"
        let prefix = "\(base)?title=\(percentEncoded(title))&body="
        guard prefix.count <= maxLength else { return nil }
        let budget = maxLength - prefix.count

        if percentEncoded(body).count <= budget {
            return URL(string: prefix + percentEncoded(body))
        }

        // Room the decorated result needs on top of whatever text survives.
        let reserve = percentEncoded("\n```" + truncationNotice).count
        var kept = body
        while !kept.isEmpty {
            // Encoded length is not a fixed multiple of raw length — an ASCII
            // letter costs one character, a newline three, an emoji twelve —
            // so scale the raw target by the ratio actually observed on this
            // payload rather than guessing a constant. `min(_, count - 1)`
            // guarantees the loop makes progress and terminates even when the
            // estimate is optimistic.
            let ratio = Double(percentEncoded(kept).count) / Double(kept.count)
            let rawTarget = Int(Double(max(budget - reserve, 0)) / max(ratio, 1))
            let target = min(max(rawTarget, 0), kept.count - 1)
            kept = trimmedToLineBoundary(kept, maxCharacters: target)
            if kept.isEmpty { break }
            let candidate = closingUnbalancedFence(in: kept) + truncationNotice
            if percentEncoded(candidate).count <= budget {
                return URL(string: prefix + percentEncoded(candidate))
            }
        }
        // Nothing of the body survives the budget. The title still carries the
        // signal name and signature prefix, so the issue is not useless.
        return URL(string: prefix)
    }

    /// Appended when the body had to be cut, so a reader never mistakes a
    /// truncated report for a complete one.
    static let truncationNotice = "\n\n_(truncated to fit a GitHub URL — the full report is on my Mac.)_"

    // MARK: - Helpers

    /// RFC 3986 unreserved characters only. Everything else — including `+`,
    /// `&`, `#` and `/` — is escaped, so the body cannot terminate the query
    /// parameter or be re-read as a space by the receiving server.
    static func percentEncoded(_ text: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// Cuts `text` to at most `maxCharacters`, backing up to the last newline
    /// so a line — and therefore any token on it — is never split in half.
    static func trimmedToLineBoundary(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let cut = text.index(text.startIndex, offsetBy: maxCharacters)
        let head = text[text.startIndex..<cut]
        if let lastNewline = head.lastIndex(of: "\n") {
            return String(head[head.startIndex..<lastNewline])
        }
        return String(head)
    }

    /// Appends a closing ``` when truncation left a fenced block open.
    static func closingUnbalancedFence(in text: String) -> String {
        let fences = text.components(separatedBy: "```").count - 1
        return fences.isMultiple(of: 2) ? text : text + "\n```"
    }
}
