import XCTest
import InterlinedDomain
@testable import InterlinedList

/// BDD-named coverage for `CrashReportingViewModel` (GitHub issue #29, PR 1).
///
/// Runs against a stub service and an isolated `UserDefaults` suite, so no
/// test touches the real defaults database, the real log, or the signal
/// handler. Per the project's view-layer rule, nothing here renders SwiftUI.
@MainActor
final class CrashReportingViewModelTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "CrashReportingViewModelTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    private func makeViewModel(service: StubCrashReportService) -> CrashReportingViewModel {
        CrashReportingViewModel(
            service: service,
            preferences: CrashReportingPreferences(defaults: defaults)
        )
    }

    /// Records the URL a submission produced without opening a browser.
    private final class URLRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _urls: [URL] = []
        var urls: [URL] { lock.lock(); defer { lock.unlock() }; return _urls }
        func record(_ url: URL) { lock.lock(); _urls.append(url); lock.unlock() }
    }

    // MARK: - The toggle

    func test_givenAnyViewModel_whenConstructed_thenLogPathIsAvailableWithoutLoadingAReport() {
        // The Settings pane shows this path but never loads a pending report,
        // so it has to be resolved at init or that row is always blank.
        let viewModel = makeViewModel(service: StubCrashReportService())
        XCTAssertEqual(viewModel.logFilePath, "/tmp/interlinedlist.log")
    }

    func test_givenFreshInstall_whenReadingToggle_thenReportingIsOff() {
        // Issue #29 frames this as opt-in "help development", so off is the
        // only correct default.
        let viewModel = makeViewModel(service: StubCrashReportService())
        XCTAssertFalse(viewModel.isEnabled)
    }

    func test_givenToggleTurnedOn_whenReadingPreferencesBack_thenChoicePersists() {
        // Given
        let viewModel = makeViewModel(service: StubCrashReportService())

        // When
        viewModel.isEnabled = true

        // Then — a new view model on the next launch sees the same answer.
        XCTAssertTrue(makeViewModel(service: StubCrashReportService()).isEnabled)
    }

    func test_givenPreferenceChangedElsewhere_whenRefreshing_thenToggleCatchesUp() {
        // Given — an open Settings pane while the launch sheet flipped the flag.
        let viewModel = makeViewModel(service: StubCrashReportService())
        viewModel.isEnabled = true

        // When
        CrashReportingPreferences(defaults: defaults).isEnabled = false
        viewModel.refreshFromPreferences()

        // Then
        XCTAssertFalse(viewModel.isEnabled)
    }

    // MARK: - Happy path — a pending report is prepared

    func test_givenReportingOnAndPendingCrash_whenLoading_thenSheetPayloadIsPrepared() async {
        // Given
        let service = StubCrashReportService(
            pending: .stub(),
            logTail: "[INFO] APIClient: HTTP 200 [/api/user]"
        )
        let viewModel = makeViewModel(service: service)
        viewModel.isEnabled = true

        // When
        await viewModel.loadPendingReport()

        // Then — the sheet has everything it needs, and the log tail was
        // actually fetched rather than assumed empty.
        XCTAssertNotNil(viewModel.pendingReport)
        XCTAssertTrue(viewModel.issueTitle.hasPrefix("Crash: SIGSEGV ("))
        XCTAssertTrue(viewModel.editableBody.contains("HTTP 200 [/api/user]"))
        XCTAssertTrue(viewModel.editableBody.contains(CrashReport.stub().signature))
        XCTAssertEqual(viewModel.logFilePath, "/tmp/interlinedlist.log")
        XCTAssertEqual(service.requestedTailBytes, [CrashReportURLBuilder.defaultLogTailBytes])
        // Nothing has been discarded yet — the user has not answered.
        XCTAssertEqual(service.clearCount, 0)
    }

    func test_givenPreparedReport_whenSubmitting_thenOpensPrefilledURLAndClearsBreadcrumb() async {
        // Given
        let service = StubCrashReportService(pending: .stub())
        let viewModel = makeViewModel(service: service)
        viewModel.isEnabled = true
        await viewModel.loadPendingReport()
        let recorder = URLRecorder()

        // When
        await viewModel.submit { url in
            recorder.record(url)
            return true
        }

        // Then — one prefilled GitHub URL, and the prompt does not return.
        XCTAssertEqual(recorder.urls.count, 1)
        let url = recorder.urls[0]
        XCTAssertEqual(url.host, "github.com")
        XCTAssertTrue(url.path.hasSuffix("/issues/new"))
        XCTAssertNil(viewModel.pendingReport)
        XCTAssertEqual(service.clearCount, 1)
        XCTAssertNil(viewModel.submissionError)
    }

    func test_givenUserNote_whenTypedBeforeEditingBody_thenBodyPicksItUp() async {
        // Given
        let viewModel = makeViewModel(service: StubCrashReportService(pending: .stub()))
        viewModel.isEnabled = true
        await viewModel.loadPendingReport()

        // When
        viewModel.userNote = "Saving a document after editing a list"

        // Then
        XCTAssertTrue(viewModel.editableBody.contains("Saving a document after editing a list"))
    }

    func test_givenUserEditedTheBody_whenNoteChanges_thenTheirEditsAreNotOverwritten() async {
        // The payload editor is the user's second line of defence; silently
        // regenerating over their edits would undo a deliberate removal.
        let viewModel = makeViewModel(service: StubCrashReportService(pending: .stub()))
        viewModel.isEnabled = true
        await viewModel.loadPendingReport()

        // When — they take ownership of the text, then touch the note field.
        viewModel.editableBody = "I removed everything except this sentence."
        viewModel.markBodyEdited()
        viewModel.userNote = "some note"

        // Then
        XCTAssertEqual(viewModel.editableBody, "I removed everything except this sentence.")
    }

    func test_givenUserEditedTheBody_whenSubmitting_thenTheirTextIsWhatGetsSent() async {
        // Given
        let viewModel = makeViewModel(service: StubCrashReportService(pending: .stub()))
        viewModel.isEnabled = true
        await viewModel.loadPendingReport()
        viewModel.markBodyEdited()
        viewModel.editableBody = "only this"
        let recorder = URLRecorder()

        // When
        await viewModel.submit { url in recorder.record(url); return true }

        // Then
        let body = URLComponents(url: recorder.urls[0], resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "body" }?.value
        XCTAssertEqual(body, "only this")
    }

    // MARK: - Opt-out suppresses the prompt

    func test_givenReportingOff_whenLoading_thenNoPromptAndNothingIsRead() async {
        // Given — a crash happened, but the user never opted in.
        let service = StubCrashReportService(pending: .stub(), logTail: "secret log")
        let viewModel = makeViewModel(service: service)

        // When
        await viewModel.loadPendingReport()

        // Then — no sheet, and the log was never even touched.
        XCTAssertNil(viewModel.pendingReport)
        XCTAssertTrue(viewModel.editableBody.isEmpty)
        XCTAssertTrue(service.requestedTailBytes.isEmpty)
    }

    func test_givenPendingSheet_whenNeverAskAgain_thenReportingIsOffAndPersists() async {
        // Given
        let service = StubCrashReportService(pending: .stub())
        let viewModel = makeViewModel(service: service)
        viewModel.isEnabled = true
        await viewModel.loadPendingReport()
        XCTAssertNotNil(viewModel.pendingReport)

        // When
        await viewModel.neverAskAgain()

        // Then — the sheet closed, the breadcrumb is gone, and the decision
        // survives into the next launch.
        XCTAssertNil(viewModel.pendingReport)
        XCTAssertFalse(viewModel.isEnabled)
        XCTAssertEqual(service.clearCount, 1)
        XCTAssertFalse(makeViewModel(service: StubCrashReportService()).isEnabled)
    }

    func test_givenNeverAskAgainOnAPriorLaunch_whenLoadingAgain_thenNoPromptAppears() async {
        // Given — the decision from a previous launch.
        CrashReportingPreferences(defaults: defaults).isEnabled = false

        // When
        let service = StubCrashReportService(pending: .stub())
        let viewModel = makeViewModel(service: service)
        await viewModel.loadPendingReport()

        // Then
        XCTAssertNil(viewModel.pendingReport)
    }

    func test_givenPendingSheet_whenDontSend_thenNothingIsSentAndPromptDoesNotReturn() async {
        // Given
        let service = StubCrashReportService(pending: .stub())
        let viewModel = makeViewModel(service: service)
        viewModel.isEnabled = true
        await viewModel.loadPendingReport()

        // When
        await viewModel.dismiss()

        // Then
        XCTAssertNil(viewModel.pendingReport)
        XCTAssertEqual(service.clearCount, 1)
        XCTAssertTrue(viewModel.isEnabled, "Don't Send is a one-off answer, not an opt-out.")
    }

    // MARK: - Submission failure

    func test_givenBrowserRefusesURL_whenSubmitting_thenErrorSurfacesAndBreadcrumbIsKept() async {
        // The user must get another chance rather than losing the report to a
        // browser that failed to launch.
        let service = StubCrashReportService(pending: .stub())
        let viewModel = makeViewModel(service: service)
        viewModel.isEnabled = true
        await viewModel.loadPendingReport()

        // When
        await viewModel.submit { _ in false }

        // Then
        XCTAssertNotNil(viewModel.submissionError)
        XCTAssertNotNil(viewModel.pendingReport, "The sheet must stay open so the user can retry.")
        XCTAssertEqual(service.clearCount, 0, "A failed submission must not discard the report.")
    }

    func test_givenAFailedSubmission_whenRetryingSuccessfully_thenReportIsClearedNormally() async {
        // Given — one failure already recorded.
        let service = StubCrashReportService(pending: .stub())
        let viewModel = makeViewModel(service: service)
        viewModel.isEnabled = true
        await viewModel.loadPendingReport()
        await viewModel.submit { _ in false }

        // When
        await viewModel.submit { _ in true }

        // Then
        XCTAssertNil(viewModel.submissionError)
        XCTAssertNil(viewModel.pendingReport)
        XCTAssertEqual(service.clearCount, 1)
    }

    // MARK: - Boundary

    func test_givenNoCrash_whenLoading_thenNothingIsPreparedAndNothingIsCleared() async {
        // The overwhelmingly common case: a clean previous run.
        let service = StubCrashReportService(pending: nil)
        let viewModel = makeViewModel(service: service)
        viewModel.isEnabled = true

        // When
        await viewModel.loadPendingReport()

        // Then
        XCTAssertNil(viewModel.pendingReport)
        XCTAssertEqual(service.clearCount, 0)
    }

    func test_givenNoPendingReport_whenSubmitting_thenNothingIsOpened() async {
        // Boundary: the sheet cannot be reached without a report, but the
        // method must be safe if it ever is.
        let service = StubCrashReportService(pending: nil)
        let viewModel = makeViewModel(service: service)
        let recorder = URLRecorder()

        await viewModel.submit { url in recorder.record(url); return true }

        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertEqual(service.clearCount, 0)
    }

    func test_givenEmptyLogAndNoFrames_whenLoading_thenBodyIsStillUsable() async {
        // Boundary: `backtrace` returned nothing and the log is empty. The
        // report must still identify the crash.
        let report = CrashReport.stub(frames: [])
        let viewModel = makeViewModel(service: StubCrashReportService(pending: report, logTail: ""))
        viewModel.isEnabled = true

        // When
        await viewModel.loadPendingReport()

        // Then
        XCTAssertTrue(viewModel.editableBody.contains(report.signature))
        XCTAssertFalse(viewModel.editableBody.contains("### Backtrace"))
    }

    func test_givenLoadCalledTwice_whenAlreadyPrepared_thenTheSecondCallIsANoOp() async {
        // The prompt modifier's `.task` can re-run; re-preparing would discard
        // a note the user had already started typing.
        let service = StubCrashReportService(pending: .stub())
        let viewModel = makeViewModel(service: service)
        viewModel.isEnabled = true
        await viewModel.loadPendingReport()
        viewModel.markBodyEdited()
        viewModel.editableBody = "my edits"

        // When
        await viewModel.loadPendingReport()

        // Then
        XCTAssertEqual(viewModel.editableBody, "my edits")
        XCTAssertEqual(service.requestedTailBytes.count, 1)
    }

    func test_givenOversizedLogTail_whenSubmitting_thenTheURLStillFitsGitHubsBudget() async {
        // Boundary: a full 4 KB tail plus frames overflows the URL. The
        // builder must trim rather than produce a link GitHub rejects.
        let hugeTail = (0..<2_000)
            .map { "2026-09-06T12:00:00.000Z [INFO] APIClient: line \($0) [/api/user]" }
            .joined(separator: "\n")
        let service = StubCrashReportService(pending: .stub(), logTail: hugeTail)
        let viewModel = makeViewModel(service: service)
        viewModel.isEnabled = true
        await viewModel.loadPendingReport()
        let recorder = URLRecorder()

        // When
        await viewModel.submit { url in recorder.record(url); return true }

        // Then
        XCTAssertEqual(recorder.urls.count, 1)
        XCTAssertLessThanOrEqual(
            recorder.urls[0].absoluteString.count,
            CrashReportURLBuilder.maxURLLength
        )
    }
}
