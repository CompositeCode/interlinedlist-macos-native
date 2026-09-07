import XCTest
@testable import InterlinedDomain

/// BDD-named coverage for `CrashReportStore` and `CrashReport` (GitHub issue
/// #29, PR 1).
///
/// The store runs on the launch path, so the invalid / failure cases matter as
/// much as the happy one: a garbage breadcrumb must degrade to "no crash", not
/// to a crash while reporting a crash. Every case here writes into a temporary
/// directory — never `~/Library`.
final class CrashReportStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crash-report-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeStore(breadcrumb: String? = nil, log: String? = nil) throws -> CrashReportStore {
        let breadcrumbURL = directory.appendingPathComponent("crash-breadcrumb.txt")
        let logURL = directory.appendingPathComponent("interlinedlist.log")
        if let breadcrumb { try Data(breadcrumb.utf8).write(to: breadcrumbURL) }
        if let log { try Data(log.utf8).write(to: logURL) }
        return CrashReportStore(breadcrumbURL: breadcrumbURL, logURL: logURL)
    }

    /// A breadcrumb in exactly the shape `CrashSignalHandler` writes.
    private let signalBreadcrumb = """
    INTERLINEDLIST-CRASH/1
    version=0.1.0
    build=42
    os=15.4.0
    occurred=1757160000
    signal=11
    --frames--
    0   InterlinedList   0x0000000104a1b2c3 $s14InterlinedList8CrasherC4bangyyF + 40
    1   InterlinedList   0x0000000104a1b300 $s14InterlinedList8CrasherC4bootyyF + 12
    --end--

    """

    // MARK: - Happy path

    func test_givenSignalBreadcrumb_whenReadingPending_thenReportRoundTrips() throws {
        // Given
        let store = try makeStore(breadcrumb: signalBreadcrumb)

        // When
        let report = try XCTUnwrap(store.readPending())

        // Then — every header field survived, and the name was derived from
        // the signal number (the handler cannot safely write it).
        XCTAssertEqual(report.signal, 11)
        XCTAssertEqual(report.name, "SIGSEGV")
        XCTAssertEqual(report.appVersion, "0.1.0")
        XCTAssertEqual(report.build, "42")
        XCTAssertEqual(report.osVersion, "15.4.0")
        XCTAssertEqual(report.occurredAt, Date(timeIntervalSince1970: 1_757_160_000))
        XCTAssertEqual(report.frames.count, 2)
        XCTAssertTrue(report.frames[0].contains("CrasherC4bang"))
        XCTAssertFalse(report.isException)
        XCTAssertFalse(report.signature.isEmpty)
    }

    func test_givenExceptionBlockFollowedBySignalBlock_whenReading_thenExceptionBlockWins() throws {
        // Given — what actually lands on disk when an uncaught NSException is
        // raised: the exception handler writes a block, then the SIGABRT that
        // follows appends a second one. The richer block is first and must win.
        let breadcrumb = """
        INTERLINEDLIST-CRASH/1
        version=0.1.0
        build=42
        os=15.4.0
        occurred=1757160000
        signal=0
        name=NSInvalidArgumentException
        reason=-[NSNull length]: unrecognized selector
        --frames--
        0   CoreFoundation   0x00000001998c1234 __exceptionPreprocess + 176
        --end--
        INTERLINEDLIST-CRASH/1
        version=0.1.0
        build=42
        os=15.4.0
        occurred=1757160001
        signal=6
        --frames--
        0   libsystem_kernel.dylib   0x00000001998c9999 __pthread_kill + 8
        --end--

        """
        let store = try makeStore(breadcrumb: breadcrumb)

        // When
        let report = try XCTUnwrap(store.readPending())

        // Then
        XCTAssertTrue(report.isException)
        XCTAssertEqual(report.name, "NSInvalidArgumentException")
        XCTAssertEqual(report.reason, "-[NSNull length]: unrecognized selector")
        XCTAssertEqual(report.frames.count, 1, "Frames from the second block must not leak into the first.")
    }

    func test_givenEscapedNewlineInReason_whenReading_thenNewlineIsRestored() throws {
        // The writer flattens newlines so a multi-line reason cannot forge
        // extra header lines; the reader has to undo that.
        let breadcrumb = """
        INTERLINEDLIST-CRASH/1
        signal=0
        name=Boom
        reason=first line\\nsecond line
        --end--

        """
        let store = try makeStore(breadcrumb: breadcrumb)

        let report = try XCTUnwrap(store.readPending())
        XCTAssertEqual(report.reason, "first line\nsecond line")
    }

    // MARK: - Invalid input

    func test_givenCorruptBreadcrumb_whenReadingPending_thenTreatedAsNoCrash() throws {
        // Given — a file that is not ours at all.
        let store = try makeStore(breadcrumb: "this is not a crash breadcrumb\nnor is this\n")

        // When / Then — absent, not a throw and not a bogus report.
        XCTAssertNil(store.readPending())
    }

    func test_givenBreadcrumbTruncatedBeforeSignalLine_whenReading_thenTreatedAsNoCrash() throws {
        // Given — the process died mid-write, before the one field that makes
        // a block meaningful.
        let store = try makeStore(breadcrumb: """
        INTERLINEDLIST-CRASH/1
        version=0.1.0
        build=42
        """)

        // Then
        XCTAssertNil(store.readPending())
    }

    func test_givenBreadcrumbWithNonNumericSignal_whenReading_thenTreatedAsNoCrash() throws {
        let store = try makeStore(breadcrumb: """
        INTERLINEDLIST-CRASH/1
        signal=not-a-number
        --end--
        """)
        XCTAssertNil(store.readPending())
    }

    func test_givenBreadcrumbTruncatedMidBacktrace_whenReading_thenReportSurvivesWithPartialFrames() throws {
        // Given — no `--end--`, because the process died writing frames. EOF
        // is an equally valid terminator; throwing the report away here would
        // discard the most interesting crashes.
        let store = try makeStore(breadcrumb: """
        INTERLINEDLIST-CRASH/1
        version=0.1.0
        build=42
        os=15.4.0
        signal=4
        --frames--
        0   InterlinedList   0x0000000104a1b2c3 $s14InterlinedList3fooyyF + 40
        1   InterlinedList   0x0000000104a1b2
        """)

        // When
        let report = try XCTUnwrap(store.readPending())

        // Then
        XCTAssertEqual(report.name, "SIGILL")
        XCTAssertEqual(report.frames.count, 2)
    }

    // MARK: - Upstream failure — the filesystem is not cooperating

    func test_givenMissingBreadcrumbFile_whenReadingPending_thenReturnsNilWithoutThrowing() {
        let store = CrashReportStore(
            breadcrumbURL: directory.appendingPathComponent("does-not-exist.txt"),
            logURL: directory.appendingPathComponent("also-missing.log")
        )
        XCTAssertNil(store.readPending())
        XCTAssertEqual(store.logTail(maxBytes: 1_000), "")
    }

    func test_givenNilURLs_whenUsingStore_thenEveryCallIsInert() {
        // The XCTest configuration: `FileLog.defaultDirectory()` returns nil,
        // so the store must be a no-op rather than reaching for a fallback
        // path inside the real Library.
        let store = CrashReportStore(breadcrumbURL: nil, logURL: nil)
        XCTAssertNil(store.readPending())
        XCTAssertEqual(store.logTail(maxBytes: 1_000), "")
        store.clearPending()                       // must not throw or trap
    }

    func test_givenUnwritableBreadcrumb_whenClearing_thenDegradesSilently() throws {
        // Given — a breadcrumb inside a directory that no longer exists.
        let store = CrashReportStore(
            breadcrumbURL: directory
                .appendingPathComponent("gone", isDirectory: true)
                .appendingPathComponent("crash.txt"),
            logURL: nil
        )

        // When / Then — clearing must never block or throw at launch.
        store.clearPending()
    }

    // MARK: - Boundary

    func test_givenZeroByteBreadcrumb_whenReadingPending_thenTreatedAsNoCrash() throws {
        // This is the *clean run* case, and the single most important boundary
        // in the feature: the handler opens the file with O_TRUNC at install,
        // so every launch that did not crash finds exactly this.
        let store = try makeStore(breadcrumb: "")
        XCTAssertNil(store.readPending())
    }

    func test_givenOversizedBreadcrumb_whenReadingPending_thenFramesAreCapped() throws {
        // Given — a runaway unwind producing far more frames than the cap.
        var breadcrumb = """
        INTERLINEDLIST-CRASH/1
        version=0.1.0
        build=42
        os=15.4.0
        signal=11
        --frames--

        """
        for index in 0..<5_000 {
            breadcrumb += "\(index)   InterlinedList   0x0000000104a1b2c3 $s14InterlinedList7recurseyyF + \(index)\n"
        }
        let store = try makeStore(breadcrumb: breadcrumb)

        // When
        let report = try XCTUnwrap(store.readPending())

        // Then — bounded, and still a usable report.
        XCTAssertEqual(report.frames.count, CrashReportStore.maxFrames)
        XCTAssertEqual(report.name, "SIGSEGV")
    }

    func test_givenBreadcrumbWithNoFrames_whenReading_thenReportIsStillProduced() throws {
        // Boundary: `backtrace` returned nothing. A signal number alone is
        // still worth reporting.
        let store = try makeStore(breadcrumb: """
        INTERLINEDLIST-CRASH/1
        signal=6
        --frames--
        --end--
        """)
        let report = try XCTUnwrap(store.readPending())
        XCTAssertTrue(report.frames.isEmpty)
        XCTAssertEqual(report.name, "SIGABRT")
    }

    // MARK: - clearPending

    func test_givenBreadcrumbOnDisk_whenClearing_thenNextReadFindsNothing() throws {
        // Given
        let store = try makeStore(breadcrumb: signalBreadcrumb)
        XCTAssertNotNil(store.readPending())

        // When
        store.clearPending()

        // Then — one crash prompts exactly once.
        XCTAssertNil(store.readPending())
    }

    // MARK: - Log tail

    func test_givenShortLog_whenReadingTail_thenWholeLogIsReturnedRedacted() throws {
        // Given
        let store = try makeStore(log: """
        2026-09-06T12:00:00.000Z [INFO] APIClient: HTTP 200 [/api/user]
        2026-09-06T12:00:01.000Z [DEBUG] AuthService: Bearer sk_live_abcdef0123456789

        """)

        // When
        let tail = store.logTail(maxBytes: 10_000)

        // Then — the whole log, with the credential gone.
        XCTAssertTrue(tail.contains("HTTP 200 [/api/user]"))
        XCTAssertFalse(tail.contains("sk_live_abcdef0123456789"))
        XCTAssertTrue(tail.contains("[redacted-token]"))
    }

    func test_givenLogLargerThanCap_whenReadingTail_thenOnlyTheTailIsReturned() throws {
        // Given — 1,000 numbered lines.
        var log = ""
        for index in 0..<1_000 {
            log += "2026-09-06T12:00:00.000Z [INFO] APIClient: line \(index)\n"
        }
        let store = try makeStore(log: log)

        // When
        let tail = store.logTail(maxBytes: 2_000)

        // Then — bounded, and it is the *newest* lines that survived.
        XCTAssertLessThanOrEqual(tail.utf8.count, 2_000)
        XCTAssertTrue(tail.contains("line 999"))
        XCTAssertFalse(tail.contains("line 0\n"))
    }

    func test_givenTokenSplitAcrossTheTruncationPoint_whenReadingTail_thenNoFragmentSurvives() throws {
        // THE boundary case for this feature. Cutting a fixed number of bytes
        // off the end of a log lands mid-token about as often as not, and the
        // leading fragment of a bearer token matches no deny-list rule — so
        // redaction alone would let it through. The store defends by dropping
        // the partial first line after the cut. This test pins that behaviour.
        var log = ""
        for index in 0..<200 {
            log += "2026-09-06T12:00:00.000Z [INFO] APIClient: padding line \(index)\n"
        }
        // A long, distinctive credential placed so the byte cut lands inside it.
        let secret = String(repeating: "S3CR3T", count: 20)
        log += "2026-09-06T12:00:00.000Z [DEBUG] AuthService: Bearer \(secret)\n"
        for index in 0..<50 {
            log += "2026-09-06T12:00:01.000Z [INFO] APIClient: trailing line \(index)\n"
        }
        let store = try makeStore(log: log)

        // Choose a cap that lands the byte cut *inside* the credential itself,
        // not merely on its line — that is the case redaction cannot save us
        // from, because half a token matches no pattern.
        let bytes = Array(log.utf8)
        let secretBytes = Array(secret.utf8)
        let secretStart = try XCTUnwrap(
            (0...(bytes.count - secretBytes.count)).first { offset in
                Array(bytes[offset..<(offset + secretBytes.count)]) == secretBytes
            },
            "test fixture no longer contains the secret"
        )
        let cutOffset = secretStart + secretBytes.count / 2      // mid-token
        let maxBytes = bytes.count - cutOffset

        // Sanity-check the fixture: without the line trim, this cut really
        // would leave a readable fragment behind.
        let rawTail = String(decoding: bytes[cutOffset...], as: UTF8.self)
        XCTAssertTrue(rawTail.contains("S3CR3T"), "Fixture is not exercising a split token.")

        // When
        let tail = store.logTail(maxBytes: maxBytes)

        // Then — no fragment of the secret survives, in whole or in part.
        XCTAssertFalse(tail.contains("S3CR3T"), "A fragment of a split credential survived truncation.\nTail head: \(tail.prefix(200))")
        // …and the tail is still useful.
        XCTAssertTrue(tail.contains("trailing line 49"))
    }

    func test_givenEmptyLog_whenReadingTail_thenReturnsEmptyString() throws {
        let store = try makeStore(log: "")
        XCTAssertEqual(store.logTail(maxBytes: 1_000), "")
    }

    func test_givenZeroMaxBytes_whenReadingTail_thenReturnsEmptyString() throws {
        let store = try makeStore(log: "2026-09-06T12:00:00.000Z [INFO] APIClient: hello\n")
        XCTAssertEqual(store.logTail(maxBytes: 0), "")
    }

    // MARK: - Signature stability

    func test_givenSameCrashTwice_whenSigning_thenSignaturesMatch() {
        // Dedup (PR 2) and the issue title both depend on this being stable
        // across launches — which is exactly why it is FNV-1a and not
        // `Hasher`, whose seed changes every process.
        let frames = [
            "0   InterlinedList   0x0000000104a1b2c3 $s14InterlinedList8CrasherC4bangyyF + 40",
            "1   InterlinedList   0x0000000104a1b300 $s14InterlinedList8CrasherC4bootyyF + 12"
        ]
        XCTAssertEqual(
            CrashReport.signature(name: "SIGSEGV", frames: frames),
            CrashReport.signature(name: "SIGSEGV", frames: frames)
        )
    }

    func test_givenSameCrashAtDifferentLoadAddresses_whenSigning_thenSignaturesMatch() {
        // ASLR slides the load address and the `+ offset` on every launch. The
        // same bug must still fingerprint identically or dedup never matches.
        let runOne = ["3   InterlinedList   0x0000000104a1b2c3 $s14InterlinedList3fooyyF + 40"]
        let runTwo = ["3   InterlinedList   0x00000001f9d0e5a1 $s14InterlinedList3fooyyF + 48"]
        XCTAssertEqual(
            CrashReport.signature(name: "SIGSEGV", frames: runOne),
            CrashReport.signature(name: "SIGSEGV", frames: runTwo)
        )
    }

    func test_givenDifferentCrashSites_whenSigning_thenSignaturesDiffer() {
        let alpha = ["0   InterlinedList   0x0000000104a1b2c3 $s14InterlinedList3fooyyF + 40"]
        let beta  = ["0   InterlinedList   0x0000000104a1b2c3 $s14InterlinedList3baryyF + 40"]
        XCTAssertNotEqual(
            CrashReport.signature(name: "SIGSEGV", frames: alpha),
            CrashReport.signature(name: "SIGSEGV", frames: beta)
        )
    }

    func test_givenNoFrames_whenSigning_thenSignatureIsStillProduced() {
        // Boundary: `backtrace` returned nothing. The signal name alone still
        // has to yield a usable, non-empty signature.
        let signature = CrashReport.signature(name: "SIGABRT", frames: [])
        XCTAssertFalse(signature.isEmpty)
        XCTAssertNotEqual(signature, CrashReport.signature(name: "SIGSEGV", frames: []))
    }

    func test_givenFrameWithAddressAndOffset_whenNormalising_thenOnlyBinaryAndSymbolRemain() {
        XCTAssertEqual(
            CrashReport.normalizedFrame("3   InterlinedList   0x000000010a1b2c3d  $s14InterlinedList3fooyyF + 40"),
            "InterlinedList $s14InterlinedList3fooyyF"
        )
    }
}
