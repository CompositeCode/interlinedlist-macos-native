import XCTest
@testable import InterlinedDomain

/// BDD-named coverage for `CrashReportRedactor` (GitHub issue #29, PR 1).
///
/// These are the highest-value tests in the crash-reporting change. The
/// destination repository is public and permanent, so a miss here is a
/// credential disclosure rather than a bug. The invalid-input suite is
/// therefore table-driven over *real-shaped* log lines — lines matching what
/// `AppLog` / `APIClient` actually emit — and asserts both halves of the
/// contract: the secret is gone, and the marker that replaced it is present.
final class CrashReportRedactorTests: XCTestCase {

    // MARK: - Happy path — a clean log survives intact

    func test_givenLogWithNoSecrets_whenRedacting_thenTextIsUnchanged() {
        // Given — the diagnostic lines we explicitly want to KEEP: status
        // codes, route paths, timestamps and AppLog category names.
        let log = """
        2026-09-06T12:00:00.000Z [NOTICE] APIClient: HTTP 404 [/api/lists/abc]: no server message
        2026-09-06T12:00:01.000Z [WARNING] APIClient: Bearer request returned 401 [/api/user] — retrying via session transport
        2026-09-06T12:00:02.000Z [ERROR] DocumentSyncEngine: sync cycle failed after 3 attempts
        """

        // When
        let redacted = CrashReportRedactor.redact(log)

        // Then — nothing was touched.
        XCTAssertEqual(redacted, log)
    }

    func test_givenBearerFollowedByAnEnglishWord_whenRedacting_thenTheWordSurvives() {
        // Regression guard. `APIClient.swift` really logs this line, and the
        // first version of the deny-list rewrote it to
        // "Bearer [redacted-token] returned 401" — a false positive that
        // destroys a diagnostic and makes every genuine marker less credible.
        let line = "[WARNING] APIClient: Bearer request returned 401 [/api/user] — retrying via session transport"

        // When
        let redacted = CrashReportRedactor.redact(line)

        // Then
        XCTAssertEqual(redacted, line)
    }

    func test_givenShortAlphanumericBearerToken_whenRedacting_thenStillRemoved() {
        // The qualifier that fixed the false positive must not open a hole:
        // eight characters with a digit still reads as a credential.
        let redacted = CrashReportRedactor.redact("[DEBUG] APIClient: Bearer a1b2c3d4")
        XCTAssertFalse(redacted.contains("a1b2c3d4"))
        XCTAssertTrue(redacted.contains("[redacted-token]"))
    }

    func test_givenRealStackFrames_whenRedacting_thenFramesSurvive() {
        // Given — mangled Swift symbols contain no `=`, `@` or `Bearer`, so
        // running frames through the deny-list must be a no-op.
        let frames = [
            "0   InterlinedList   0x0000000104a1b2c3 $s14InterlinedList16DocumentsServiceC4syncyyYaKF + 240",
            "1   libswiftCore.dylib 0x00000001998c1234 $ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF + 100"
        ]

        // When
        let redacted = CrashReportRedactor.redact(frames: frames)

        // Then
        XCTAssertEqual(redacted, frames)
    }

    // MARK: - Invalid input — every secret shape must die
    //
    // One table, one assertion pair per row. `mustNotContain` is the secret;
    // `mustContain` is the marker proving the *intended* rule fired rather
    // than some accident of another rule.

    private struct RedactionCase {
        let name: String
        let line: String
        let mustNotContain: [String]
        let mustContain: String
    }

    func test_givenSecretBearingLogLines_whenRedacting_thenSecretsDoNotSurvive() {
        let cases: [RedactionCase] = [
            RedactionCase(
                name: "Authorization header",
                line: #"2026-09-06T12:00:00.000Z [DEBUG] APIClient: headers ["Authorization": "Bearer sk_live_9f8e7d6c5b4a3210"]"#,
                mustNotContain: ["sk_live_9f8e7d6c5b4a3210"],
                mustContain: "[redacted-token]"
            ),
            RedactionCase(
                name: "bare Bearer token",
                line: "2026-09-06T12:00:00.000Z [ERROR] APIClient: retrying with Bearer abc123DEF456ghi789",
                mustNotContain: ["abc123DEF456ghi789"],
                mustContain: "[redacted-token]"
            ),
            RedactionCase(
                name: "JWT with no surrounding key",
                line: "2026-09-06T12:00:00.000Z [DEBUG] AuthService: stored eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NSJ9.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk",
                mustNotContain: ["eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9", "dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk"],
                mustContain: "[redacted-token]"
            ),
            RedactionCase(
                name: "JWT inside a URL query",
                line: "2026-09-06T12:00:00.000Z [NOTICE] APIClient: HTTP 200 [/api/share/resolve?t=eyJhbGciOiJIUzI1NiJ9.eyJpZCI6OX0.sig]",
                mustNotContain: ["eyJhbGciOiJIUzI1NiJ9"],
                mustContain: "[redacted-token]"
            ),
            RedactionCase(
                name: "token= in a query string",
                line: "2026-09-06T12:00:00.000Z [ERROR] APIClient: Transport failed [/api/user?token=9f8e7d6c5b4a]",
                mustNotContain: ["9f8e7d6c5b4a"],
                mustContain: "[redacted]"
            ),
            RedactionCase(
                name: "JSON accessToken field",
                line: #"2026-09-06T12:00:00.000Z [DEBUG] SessionService: response {"accessToken":"tok_abcdef123456","expires":900}"#,
                mustNotContain: ["tok_abcdef123456"],
                mustContain: "[redacted]"
            ),
            RedactionCase(
                name: "password field",
                line: #"2026-09-06T12:00:00.000Z [DEBUG] AuthService: body {"password":"hunter2-correct-horse"}"#,
                mustNotContain: ["hunter2-correct-horse"],
                mustContain: "[redacted]"
            ),
            RedactionCase(
                name: "Keychain item value",
                line: "2026-09-06T12:00:00.000Z [INFO] KeychainTokenStore: keychainValue=AAAABBBBCCCCDDDD read from shared group",
                mustNotContain: ["AAAABBBBCCCCDDDD"],
                mustContain: "[redacted]"
            ),
            RedactionCase(
                name: "client secret",
                line: "2026-09-06T12:00:00.000Z [ERROR] LinkedInService: client_secret: 7c9a1f2b3d4e5f60 rejected",
                mustNotContain: ["7c9a1f2b3d4e5f60"],
                mustContain: "[redacted]"
            ),
            RedactionCase(
                name: "email address in prose",
                line: "2026-09-06T12:00:00.000Z [INFO] SessionService: resolved session for ada.lovelace@example.com",
                mustNotContain: ["ada.lovelace@example.com", "ada.lovelace"],
                mustContain: "[redacted-email]"
            ),
            RedactionCase(
                name: "document title",
                line: #"2026-09-06T12:00:00.000Z [DEBUG] DocumentsService: saved title="Q4 acquisition targets — confidential""#,
                mustNotContain: ["Q4 acquisition targets"],
                mustContain: "[redacted-content]"
            ),
            RedactionCase(
                name: "document body",
                line: #"2026-09-06T12:00:00.000Z [DEBUG] DocumentSyncEngine: pushing content="the merger closes on the 14th""#,
                mustNotContain: ["the merger closes"],
                mustContain: "[redacted-content]"
            ),
            RedactionCase(
                name: "list row content",
                line: #"2026-09-06T12:00:00.000Z [DEBUG] ListsService: row body="salary band 4 — 180000""#,
                mustNotContain: ["salary band 4", "180000"],
                mustContain: "[redacted-content]"
            ),
            RedactionCase(
                name: "account handle",
                line: "2026-09-06T12:00:00.000Z [INFO] SocialService: username=ada_lovelace followed 3 accounts",
                mustNotContain: ["ada_lovelace"],
                mustContain: "[redacted-content]"
            ),
            RedactionCase(
                name: "cookie header",
                line: "2026-09-06T12:00:00.000Z [DEBUG] APIClient: Cookie: session-abc-def-123456",
                mustNotContain: ["session-abc-def-123456"],
                mustContain: "[redacted]"
            )
        ]

        for testCase in cases {
            // When
            let redacted = CrashReportRedactor.redact(testCase.line)

            // Then
            for secret in testCase.mustNotContain {
                XCTAssertFalse(
                    redacted.contains(secret),
                    "\(testCase.name): secret '\(secret)' survived redaction.\nGot: \(redacted)"
                )
            }
            XCTAssertTrue(
                redacted.contains(testCase.mustContain),
                "\(testCase.name): expected marker '\(testCase.mustContain)'.\nGot: \(redacted)"
            )
        }
    }

    func test_givenMultipleSecretsOnOneLine_whenRedacting_thenAllAreRemoved() {
        // Given — the realistic worst case: a single reflected error carrying
        // a token, an address and a title at once.
        let line = #"[ERROR] APIClient: Transport failed [/api/documents?token=abc123XYZ] user=ada@example.com title="Board minutes""#

        // When
        let redacted = CrashReportRedactor.redact(line)

        // Then
        XCTAssertFalse(redacted.contains("abc123XYZ"))
        XCTAssertFalse(redacted.contains("ada@example.com"))
        XCTAssertFalse(redacted.contains("Board minutes"))
        // …and the diagnostically useful part survives.
        XCTAssertTrue(redacted.contains("/api/documents"))
        XCTAssertTrue(redacted.contains("Transport failed"))
    }

    // MARK: - Upstream failure — malformed input must not throw

    func test_givenMalformedUTF8_whenRedacting_thenDoesNotThrowAndStillRedacts() {
        // Given — the log tail is decoded lossily from raw bytes, so it can
        // contain replacement characters. Redaction must survive them.
        var bytes: [UInt8] = Array("[INFO] APIClient: Bearer secret_token_here ".utf8)
        bytes.append(contentsOf: [0xFF, 0xFE, 0xC0])          // invalid UTF-8
        bytes.append(contentsOf: Array(" trailing@example.com".utf8))
        let text = String(decoding: bytes, as: UTF8.self)

        // When
        let redacted = CrashReportRedactor.redact(text)

        // Then
        XCTAssertFalse(redacted.contains("secret_token_here"))
        XCTAssertFalse(redacted.contains("trailing@example.com"))
    }

    func test_givenEveryRule_whenCompiling_thenAllPatternsAreValid() {
        // A rule that fails to compile is silently skipped at runtime, which
        // would mean a live deny-list entry doing nothing. Fail the gate here
        // instead.
        for rule in CrashReportRedactor.rules {
            XCTAssertNoThrow(
                try NSRegularExpression(pattern: rule.pattern),
                "Rule '\(rule.rationale)' has an invalid pattern: \(rule.pattern)"
            )
        }
        XCTAssertEqual(CrashReportRedactor.rules.count, 6, "Deny-list size changed — was that a signed-off security decision?")
    }

    // MARK: - Boundary

    func test_givenEmptyString_whenRedacting_thenReturnsEmptyString() {
        XCTAssertEqual(CrashReportRedactor.redact(""), "")
    }

    func test_givenEmptyFrames_whenRedacting_thenReturnsEmptyArray() {
        XCTAssertTrue(CrashReportRedactor.redact(frames: []).isEmpty)
    }

    func test_givenSecretAtVeryStartOfInput_whenRedacting_thenStillRemoved() {
        // Boundary: no leading context for the pattern to anchor against.
        let redacted = CrashReportRedactor.redact("Bearer abc123DEF456 is the header")
        XCTAssertFalse(redacted.contains("abc123DEF456"))
    }

    func test_givenTruncatedJWT_whenRedacting_thenTheFragmentIsStillRemoved() {
        // Boundary: a JWT cut off by log rotation keeps its `eyJ` prefix but
        // loses its later segments. The pattern makes those segments optional
        // precisely so the fragment is still caught.
        let redacted = CrashReportRedactor.redact("[DEBUG] AuthService: token eyJhbGciOiJIUzI1NiIsInR5cCI6")
        XCTAssertFalse(redacted.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6"))
        XCTAssertTrue(redacted.contains("[redacted"))
    }

    func test_givenVeryLongPayload_whenRedacting_thenEverySecretIsStillRemoved() {
        // Boundary: the real payload is thousands of lines. Regex application
        // must be global, not first-match-only.
        var lines: [String] = []
        for index in 0..<500 {
            lines.append("2026-09-06T12:00:00.000Z [INFO] APIClient: HTTP 200 [/api/lists/\(index)]")
            lines.append("2026-09-06T12:00:00.000Z [DEBUG] AuthService: Bearer token_number_\(index)_secret")
        }

        // When
        let redacted = CrashReportRedactor.redact(lines.joined(separator: "\n"))

        // Then — not one of the 500 survives.
        for index in 0..<500 {
            XCTAssertFalse(
                redacted.contains("token_number_\(index)_secret"),
                "Secret on line \(index) survived — redaction is not global."
            )
        }
    }
}
