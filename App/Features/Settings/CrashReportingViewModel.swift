// CrashReportingViewModel
//
// Drives both crash-reporting surfaces (GitHub issue #29, PR 1):
//
//   • `CrashReportingSettingsView` — the opt-in toggle, and
//   • `CrashReportSheet` — the next-launch confirmation.
//
// They share one view model because they share one decision: the toggle both
// gates the prompt and is what "Never ask again" turns off. Splitting them
// would mean two objects racing on the same `UserDefaults` key.
//
// Depends only on the domain `CrashReportServicing` protocol and an injected
// `UserDefaults`, so the tests run against a stub service and an isolated
// defaults suite — no signal handler, no real log file, no `~/Library`.
//
// Per decision 0003, this file imports no Kit symbols.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class CrashReportingViewModel {

    // MARK: - Dependencies

    private let service: CrashReportServicing
    private let preferences: CrashReportingPreferences

    // MARK: - Settings state

    /// The opt-in flag, mirrored as a stored property so `@Observable` can
    /// track it — a computed property reading `UserDefaults` would write
    /// through correctly but would never tell SwiftUI to re-render the toggle.
    /// Every write persists immediately; `refreshFromPreferences()` pulls the
    /// value back if another surface changed it.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            preferences.isEnabled = isEnabled
        }
    }

    /// Re-reads the persisted flag. Called when the Settings pane appears, so
    /// a pane left open while the launch sheet's "Never ask again" flipped the
    /// setting does not keep showing a stale toggle.
    func refreshFromPreferences() {
        let stored = preferences.isEnabled
        if stored != isEnabled { isEnabled = stored }
    }

    // MARK: - Pending-report state

    /// The crash recovered from the previous run, once `loadPendingReport()`
    /// has found one *and* reporting is enabled. `nil` keeps the sheet closed.
    private(set) var pendingReport: CrashReport?

    /// The optional "what were you doing?" answer.
    var userNote: String = "" {
        didSet { regenerateBodyIfUntouched() }
    }

    /// The exact text that will be posted — editable, because the user seeing
    /// and being able to change the payload is the second line of defence
    /// behind redaction, and because they may want to add or remove detail.
    var editableBody: String = ""

    /// Set once the user edits `editableBody` by hand, after which the note
    /// field stops rewriting it. Without this, typing in the note box would
    /// silently discard their edits.
    private var bodyWasEditedByUser = false

    /// Title of the issue that will be filed.
    private(set) var issueTitle: String = ""

    /// Where the *full*, unredacted log stayed, shown so the user can see for
    /// themselves what is and is not leaving the machine.
    ///
    /// Resolved at init, not at load time: the Settings pane shows this path
    /// under "What's in a report" and never loads a pending report, so a
    /// load-time assignment would leave that row permanently blank.
    private(set) var logFilePath: String?

    /// Non-nil when submission failed. The breadcrumb is deliberately kept in
    /// that case so the user can retry on the next launch.
    private(set) var submissionError: String?

    private(set) var isPreparing = false

    // MARK: - Init

    init(
        service: CrashReportServicing,
        preferences: CrashReportingPreferences = CrashReportingPreferences()
    ) {
        self.service = service
        self.preferences = preferences
        self.isEnabled = preferences.isEnabled
        self.logFilePath = service.logFileURL?.path
    }

    // MARK: - Loading

    /// Looks for a breadcrumb from the previous run and, if reporting is
    /// enabled, prepares the payload for the sheet.
    ///
    /// Capture is unconditional but the *prompt* is gated: with the setting
    /// off this returns without reading anything, so a user who never opted in
    /// is never asked. What the unconditional capture buys is the opposite
    /// case — someone who turns the setting on and then crashes gets a real
    /// report on the next launch, rather than "nothing was recorded".
    func loadPendingReport() async {
        guard !isPreparing, pendingReport == nil else { return }
        guard isEnabled else { return }
        isPreparing = true
        defer { isPreparing = false }

        guard let report = await service.pendingReport() else { return }
        let logTail = await service.logTail(maxBytes: CrashReportURLBuilder.defaultLogTailBytes)

        issueTitle = CrashReportURLBuilder.issueTitle(for: report)
        pendingReport = report
        bodyWasEditedByUser = false
        preparedLogTail = logTail
        editableBody = composeBody(for: report)
    }

    /// The redacted log tail captured at load time. Held so the body can be
    /// recomposed when the note changes without re-reading the file — which
    /// would also mean re-reading log lines written *since* the crash.
    private var preparedLogTail = ""

    private func composeBody(for report: CrashReport) -> String {
        CrashReportURLBuilder.issueBody(
            for: report,
            userNote: userNote,
            logTail: preparedLogTail,
            logFilePath: logFilePath
        )
    }

    private func regenerateBodyIfUntouched() {
        guard !bodyWasEditedByUser, let pendingReport else { return }
        editableBody = composeBody(for: pendingReport)
    }

    /// Called by the sheet when the user types into the payload editor.
    func markBodyEdited() {
        bodyWasEditedByUser = true
    }

    // MARK: - Actions

    /// Opens the prefilled GitHub `issues/new` page.
    ///
    /// Nothing is transmitted here: the URL merely *populates* a form, and the
    /// user still has to press **Submit** on GitHub's own page. That second
    /// press is the confirmation issue #29 asks for, and it also means this
    /// path needs no credential and works for signed-out users.
    ///
    /// - Parameter opener: injected so tests can assert the URL without a
    ///   browser. Returns whether the URL was actually opened.
    func submit(using opener: (URL) async -> Bool) async {
        guard pendingReport != nil else { return }
        submissionError = nil
        guard let url = CrashReportURLBuilder.issueURL(
            title: issueTitle,
            body: editableBody
        ) else {
            submissionError = "The report could not be turned into a GitHub link."
            return
        }
        guard await opener(url) else {
            // Keep the breadcrumb: the user should get another chance rather
            // than losing the report to a browser that failed to launch.
            submissionError = "Could not open GitHub. The report is still on this Mac — try again."
            return
        }
        await finish()
    }

    /// "Don't Send" — discards the report without transmitting anything.
    func dismiss() async {
        await finish()
    }

    /// "Never ask again" — turns the setting off, which is what actually
    /// suppresses future prompts, and discards this report. Presented in the
    /// sheet as exactly that, so it is not a hidden second switch that
    /// contradicts the Settings toggle.
    func neverAskAgain() async {
        isEnabled = false
        await finish()
    }

    /// Clears the breadcrumb and closes the sheet, so one crash prompts once.
    private func finish() async {
        await service.clearPendingReport()
        pendingReport = nil
        editableBody = ""
        userNote = ""
        issueTitle = ""
        preparedLogTail = ""
        bodyWasEditedByUser = false
        submissionError = nil
    }
}
