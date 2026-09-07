import XCTest
@testable import InterlinedDomain

/// BDD-named coverage for `CrashReportService` (GitHub issue #29, PR 1).
///
/// Two things are pinned here that nothing else can pin:
///
///  1. **The snapshot-before-truncation ordering.** Installing the signal
///     handler opens the breadcrumb with `O_TRUNC`, so the service must have
///     already read it. Get this backwards and no crash is ever reported —
///     silently, and only in production.
///  2. **The real handler's output.** The fixture below is a byte-for-byte
///     capture of what `CrashSignalHandler` actually wrote when a real
///     `SIGSEGV` was delivered to a running build, so the parser is tested
///     against reality rather than against a hand-written guess at it.
final class CrashReportServiceTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crash-service-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    /// Verbatim output of the shipping signal handler, captured by launching a
    /// Debug build and sending it `SIGSEGV` from outside the process. Trimmed
    /// to the first few frames; the shape is unmodified.
    private let realHandlerOutput = """
    INTERLINEDLIST-CRASH/1
    version=0.1.0
    build=1
    os=26.5.2
    occurred=1788761410
    signal=11
    --frames--
    0   InterlinedList.debug.dylib          0x0000000106c24bd8 $s14InterlinedList18crashSignalHandler33_A8E2322CD5899C7B9462EDABB2304276LLyys5Int32VF + 524
    1   InterlinedList.debug.dylib          0x0000000106c25b64 $s14InterlinedList18crashSignalHandler33_A8E2322CD5899C7B9462EDABB2304276LLyys5Int32VFTo + 12
    2   libsystem_platform.dylib            0x0000000186873744 _sigtramp + 56
    3   CoreFoundation                      0x00000001869270d8 __CFRunLoopServiceMachPort + 160
    4   AppKit                              0x000000018ad4713c -[NSApplication run] + 368
    --end--

    """

    private func makeService(breadcrumb: String?, log: String? = nil) throws -> (CrashReportService, URL) {
        let breadcrumbURL = directory.appendingPathComponent("crash-breadcrumb.txt")
        let logURL = directory.appendingPathComponent("interlinedlist.log")
        if let breadcrumb { try Data(breadcrumb.utf8).write(to: breadcrumbURL) }
        if let log { try Data(log.utf8).write(to: logURL) }
        let store = CrashReportStore(breadcrumbURL: breadcrumbURL, logURL: logURL)
        return (CrashReportService(store: store), breadcrumbURL)
    }

    // MARK: - Happy path — against real handler output

    func test_givenBreadcrumbWrittenByTheRealHandler_whenReadingPending_thenItParses() async throws {
        // Given
        let (service, _) = try makeService(breadcrumb: realHandlerOutput)

        // When
        let pending = await service.pendingReport()
        let report = try XCTUnwrap(pending)

        // Then
        XCTAssertEqual(report.signal, 11)
        XCTAssertEqual(report.name, "SIGSEGV")
        XCTAssertEqual(report.appVersion, "0.1.0")
        XCTAssertEqual(report.build, "1")
        XCTAssertEqual(report.osVersion, "26.5.2")
        XCTAssertEqual(report.occurredAt, Date(timeIntervalSince1970: 1_788_761_410))
        XCTAssertEqual(report.frames.count, 5)
        XCTAssertTrue(report.frames.last?.contains("NSApplication run") == true)
        XCTAssertFalse(report.signature.isEmpty)
    }

    // MARK: - Ordering — the invariant that silently breaks the whole feature

    func test_givenHandlerTruncatesTheFileAfterConstruction_whenReadingPending_thenTheSnapshotSurvives() async throws {
        // Given — a breadcrumb on disk, and a service constructed over it.
        let (service, breadcrumbURL) = try makeService(breadcrumb: realHandlerOutput)

        // When — the signal handler installs, which opens the same file with
        // O_TRUNC. Simulated here by emptying it.
        try Data().write(to: breadcrumbURL)

        // Then — the report is still available, because it was snapshotted at
        // construction. This is exactly the ordering `AppEnvironment.live()`
        // relies on.
        let pending = await service.pendingReport()
        let report = try XCTUnwrap(pending)
        XCTAssertEqual(report.name, "SIGSEGV")
    }

    func test_givenServiceConstructedAfterTruncation_whenReadingPending_thenThereIsNoReport() async throws {
        // The mirror image: build the service too late and the crash is gone.
        // Pinned so a refactor that reorders `live()` fails here rather than
        // in production.
        let breadcrumbURL = directory.appendingPathComponent("crash-breadcrumb.txt")
        try Data(realHandlerOutput.utf8).write(to: breadcrumbURL)
        try Data().write(to: breadcrumbURL)                  // handler installs first
        let service = CrashReportService(store: CrashReportStore(breadcrumbURL: breadcrumbURL, logURL: nil))

        let pending = await service.pendingReport()
        XCTAssertNil(pending)
    }

    // MARK: - Clearing

    func test_givenPendingReport_whenClearing_thenTheFileIsEmptied() async throws {
        // Given
        let (service, breadcrumbURL) = try makeService(breadcrumb: realHandlerOutput)

        // When
        await service.clearPendingReport()

        // Then — the on-disk artifact is gone even though the in-memory
        // snapshot was taken earlier.
        let size = try Data(contentsOf: breadcrumbURL).count
        XCTAssertEqual(size, 0)
    }

    // MARK: - Log tail

    func test_givenLogOnDisk_whenReadingTail_thenItIsReturnedRedacted() async throws {
        let (service, _) = try makeService(
            breadcrumb: nil,
            log: "2026-09-06T12:00:00.000Z [DEBUG] AuthService: Bearer sk_live_abcdef0123456789\n"
        )

        let tail = await service.logTail(maxBytes: 10_000)

        XCTAssertFalse(tail.contains("sk_live_abcdef0123456789"))
        XCTAssertTrue(tail.contains("[redacted-token]"))
    }

    // MARK: - Boundary

    func test_givenNoBreadcrumbFile_whenReadingPending_thenThereIsNoReport() async throws {
        let (service, _) = try makeService(breadcrumb: nil)
        let pending = await service.pendingReport()
        XCTAssertNil(pending)
        await service.clearPendingReport()               // must not throw
    }

    func test_givenZeroByteBreadcrumb_whenReadingPending_thenThereIsNoReport() async throws {
        // The clean-run case, confirmed against a real build: the handler
        // opens the file at install with O_TRUNC, so every non-crashing launch
        // leaves exactly this.
        let (service, _) = try makeService(breadcrumb: "")
        let pending = await service.pendingReport()
        XCTAssertNil(pending)
    }

    func test_givenNilStoreURLs_whenUsingService_thenEveryCallIsInert() async {
        // The XCTest configuration, where `FileLog` is disabled.
        let service = CrashReportService(store: CrashReportStore(breadcrumbURL: nil, logURL: nil))
        let pending = await service.pendingReport()
        XCTAssertNil(pending)
        let tail = await service.logTail(maxBytes: 1_000)
        XCTAssertEqual(tail, "")
        XCTAssertNil(service.logFileURL)
        XCTAssertNil(service.breadcrumbURL)
        await service.clearPendingReport()
    }
}
