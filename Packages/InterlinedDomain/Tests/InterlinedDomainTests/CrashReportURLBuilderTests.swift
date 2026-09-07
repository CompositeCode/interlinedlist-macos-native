import XCTest
@testable import InterlinedDomain

/// BDD-named coverage for `CrashReportURLBuilder` (GitHub issue #29, PR 1).
///
/// The contract that matters: whatever gets trimmed to fit GitHub's URL
/// budget, the result is always a *valid* URL and always still identifies the
/// crash. A malformed link would strand the user on an error page with their
/// report gone.
final class CrashReportURLBuilderTests: XCTestCase {

    private func makeReport(
        frames: [String] = ["0   InterlinedList   0x0000000104a1b2c3 $s14InterlinedList3fooyyF + 40"],
        reason: String? = nil
    ) -> CrashReport {
        CrashReport(
            signal: 11,
            name: "SIGSEGV",
            reason: reason,
            frames: frames,
            appVersion: "0.1.0",
            build: "42",
            osVersion: "15.4.0",
            occurredAt: Date(timeIntervalSince1970: 1_757_160_000)
        )
    }

    // MARK: - Happy path

    func test_givenReport_whenBuildingTitle_thenTitleCarriesNameAndSignaturePrefix() {
        let report = makeReport()
        let title = CrashReportURLBuilder.issueTitle(for: report)

        XCTAssertTrue(title.hasPrefix("Crash: SIGSEGV ("))
        XCTAssertTrue(title.contains(report.shortSignature))
    }

    func test_givenReport_whenBuildingBody_thenBodyCarriesEnvironmentAndSignature() {
        let report = makeReport(reason: "unexpectedly found nil")
        let body = CrashReportURLBuilder.issueBody(
            for: report,
            userNote: "Saving a document",
            logTail: "[INFO] APIClient: HTTP 200 [/api/user]",
            logFilePath: "/tmp/interlinedlist.log"
        )

        XCTAssertTrue(body.contains(report.signature))
        XCTAssertTrue(body.contains("0.1.0 (42)"))
        XCTAssertTrue(body.contains("15.4.0"))
        XCTAssertTrue(body.contains("unexpectedly found nil"))
        XCTAssertTrue(body.contains("Saving a document"))
        XCTAssertTrue(body.contains("$s14InterlinedList3fooyyF"))
        XCTAssertTrue(body.contains("HTTP 200 [/api/user]"))
        XCTAssertTrue(body.contains("/tmp/interlinedlist.log"))
    }

    func test_givenTitleAndBody_whenBuildingURL_thenURLIsWellFormedAndDecodesBack() throws {
        // When
        let url = try XCTUnwrap(CrashReportURLBuilder.issueURL(
            title: "Crash: SIGSEGV (a1b2c3d4)",
            body: "### Crash\n\nSignature: `a1b2c3d4`"
        ))

        // Then
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/CompositeCode/interlinedlist-macos-native/issues/new")
        let items = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "Crash: SIGSEGV (a1b2c3d4)")
        XCTAssertEqual(items.first { $0.name == "body" }?.value, "### Crash\n\nSignature: `a1b2c3d4`")
    }

    // MARK: - Invalid / hostile input

    func test_givenBodyContainingQuerySeparators_whenBuildingURL_thenTheyAreEncodedNotHonoured() throws {
        // A body that tries to terminate the query parameter and inject another
        // must be neutralised, or a crafted document title could rewrite the
        // issue's own fields.
        let url = try XCTUnwrap(CrashReportURLBuilder.issueURL(
            title: "Crash: SIGSEGV (a1b2c3d4)",
            body: "harmless&labels=security&assignee=someone#fragment"
        ))

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(items.count, 2, "Body must not be able to add query parameters.")
        XCTAssertNil(url.fragment, "Body must not be able to add a fragment.")
        XCTAssertEqual(
            items.first { $0.name == "body" }?.value,
            "harmless&labels=security&assignee=someone#fragment"
        )
    }

    func test_givenPlusSignInBody_whenBuildingURL_thenItSurvivesAsAPlusNotASpace() throws {
        // `+` is the classic form-encoding trap: left unescaped it decodes to
        // a space, silently corrupting stack frames like `foo + 40`.
        let url = try XCTUnwrap(CrashReportURLBuilder.issueURL(
            title: "t",
            body: "$s14InterlinedList3fooyyF + 40"
        ))
        XCTAssertTrue(url.absoluteString.contains("%2B"))
    }

    func test_givenNonASCIIBody_whenBuildingURL_thenURLIsStillValid() throws {
        let url = try XCTUnwrap(CrashReportURLBuilder.issueURL(
            title: "Crash: SIGSEGV (a1b2c3d4)",
            body: "Crashed while typing “smart quotes” — and an emoji 🐞"
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            components.queryItems?.first { $0.name == "body" }?.value,
            "Crashed while typing “smart quotes” — and an emoji 🐞"
        )
    }

    // MARK: - Boundary — truncation

    func test_givenOversizedBody_whenBuildingURL_thenURLFitsTheBudget() throws {
        // Given — a log tail far larger than any URL could carry.
        let hugeLog = (0..<2_000)
            .map { "2026-09-06T12:00:00.000Z [INFO] APIClient: line \($0) [/api/user]" }
            .joined(separator: "\n")
        let report = makeReport()
        let body = CrashReportURLBuilder.issueBody(for: report, logTail: hugeLog)
        XCTAssertGreaterThan(body.count, CrashReportURLBuilder.maxURLLength)

        // When
        let url = try XCTUnwrap(CrashReportURLBuilder.issueURL(
            title: CrashReportURLBuilder.issueTitle(for: report),
            body: body
        ))

        // Then
        XCTAssertLessThanOrEqual(url.absoluteString.count, CrashReportURLBuilder.maxURLLength)
    }

    func test_givenOversizedBody_whenBuildingURL_thenTheTrimmedBodyStillCarriesTheSignature() throws {
        // The whole point of ordering the body most-essential-first: a report
        // that has been cut to fit must still identify which crash it is.
        let hugeLog = String(repeating: "2026-09-06T12:00:00.000Z [INFO] APIClient: padding line\n", count: 500)
        let report = makeReport()
        let body = CrashReportURLBuilder.issueBody(for: report, logTail: hugeLog)

        let url = try XCTUnwrap(CrashReportURLBuilder.issueURL(
            title: CrashReportURLBuilder.issueTitle(for: report),
            body: body
        ))

        let decoded = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "body" }?.value
        )
        XCTAssertTrue(decoded.contains(report.signature), "Truncation dropped the signature.")
        XCTAssertTrue(decoded.contains("truncated to fit"), "Truncation was not disclosed to the reader.")
    }

    func test_givenBodyTruncatedInsideACodeFence_whenBuildingURL_thenTheFenceIsClosed() throws {
        // An unbalanced ``` renders the rest of the issue as code. Cheap to
        // avoid, and truncation lands inside the log fence almost every time.
        let hugeLog = String(repeating: "2026-09-06T12:00:00.000Z [INFO] APIClient: padding\n", count: 500)
        let report = makeReport()
        let body = CrashReportURLBuilder.issueBody(for: report, logTail: hugeLog)

        let url = try XCTUnwrap(CrashReportURLBuilder.issueURL(
            title: CrashReportURLBuilder.issueTitle(for: report),
            body: body
        ))
        let decoded = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "body" }?.value
        )
        let fences = decoded.components(separatedBy: "```").count - 1
        XCTAssertTrue(fences.isMultiple(of: 2), "Truncation left an unbalanced code fence (\(fences)).")
    }

    func test_givenEmptyBody_whenBuildingURL_thenURLIsStillValid() throws {
        let url = try XCTUnwrap(CrashReportURLBuilder.issueURL(title: "Crash: SIGSEGV (abc)", body: ""))
        XCTAssertTrue(url.absoluteString.hasSuffix("&body="))
    }

    func test_givenTitleAlreadyOverBudget_whenBuildingURL_thenReturnsNilRatherThanAMalformedLink() {
        // Fail loudly rather than hand the user a link GitHub will reject.
        let url = CrashReportURLBuilder.issueURL(
            title: String(repeating: "x", count: 200),
            body: "b",
            maxLength: 100
        )
        XCTAssertNil(url)
    }

    func test_givenReportWithNoFramesOrLog_whenBuildingBody_thenSectionsAreOmittedNotEmpty() {
        // Boundary: nothing to say beyond the environment. The body must not
        // contain a heading with nothing under it.
        let body = CrashReportURLBuilder.issueBody(for: makeReport(frames: []))
        XCTAssertFalse(body.contains("### Backtrace"))
        XCTAssertFalse(body.contains("### Log tail"))
        XCTAssertFalse(body.contains("### What I was doing"))
        XCTAssertTrue(body.contains("### Crash"))
    }

    func test_givenWhitespaceOnlyUserNote_whenBuildingBody_thenNoteSectionIsOmitted() {
        let body = CrashReportURLBuilder.issueBody(for: makeReport(), userNote: "   \n  ")
        XCTAssertFalse(body.contains("### What I was doing"))
    }
}
