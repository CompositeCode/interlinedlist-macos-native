// CrashSignalHandler
//
// Records a breadcrumb when the process dies (GitHub issue #29, PR 1). The
// *next* launch reads it and offers to file a GitHub issue; see
// `CrashReportServicing` in InterlinedDomain and `CrashReportPrompt` in the
// Settings feature.
//
// ── Why signals at all ────────────────────────────────────────────────────
// What actually kills a Swift app — a force-unwrapped nil, an out-of-range
// index, `fatalError`, a failed `precondition` — is a *trap*, delivered as
// SIGILL / SIGTRAP. None of it passes through `NSSetUncaughtExceptionHandler`,
// which only ever sees ObjC exceptions. Covering real crashes needs signal
// handlers. Both paths are installed here; the ObjC one is a bonus because it
// can capture a reason string, which a signal can never carry.
//
// ── Async-signal-safety: the rule this file lives by ──────────────────────
// A signal handler may only call async-signal-safe functions. In practice that
// bans everything interesting: no `malloc`, so no Swift `String`, `Array`,
// class instance, escaping closure, or existential; no Foundation; no SwiftUI;
// no ARC traffic; and no *first* touch of a lazily-initialised Swift global,
// because that runs `swift_once` and takes a lock.
//
// So the handler below touches only:
//   • file-scope globals of *primitive* type, every one of them written by
//     `install(...)` before any crash can occur, which forces initialisation
//     while it is still safe to do so;
//   • raw pointers into buffers `install(...)` allocated and never frees;
//   • the C functions `write`, `time`, `backtrace`, `backtrace_symbols_fd`,
//     `fsync`, `signal` and `raise`, all on the POSIX async-signal-safe list.
//     Apple documents `backtrace_symbols_fd` as usable from a handler
//     precisely because, unlike `backtrace_symbols`, it does not allocate.
//
// There is no allocation, no Swift runtime call and no Foundation type below
// the `install` boundary. Every string the handler emits — including the field
// *keys* — is pre-rendered at install time, and integer→text conversion is
// hand-rolled arithmetic straight into a pre-allocated buffer, because even
// `snprintf` is not guaranteed safe here.
//
// ── How that claim was checked, and how to re-check it ────────────────────
// Claims about allocation are worth nothing unless verified against what the
// compiler actually emitted, so this file's handler was audited by dumping its
// call graph from the object file:
//
//   objdump --macho --disassemble --no-show-raw-insn \\
//     <DerivedData>/.../Objects-normal/arm64/CrashSignalHandler.o \\
//     | awk '/^_?\$s.*(crashSignalHandler|crashWriteAll|crashFormat|crashWriteField).*:$/{p=1;next}
//            /^[^ ].*:$/{p=0} p && /bl\t/' | sed 's/.*bl\t//' | sort -u | xargs -n1 swift demangle
//
// The only names that may appear are the four functions above, the
// `crashState` addressor, `Darwin.errno.getter`, `Darwin.SIG_DFL.getter`, and
// `backtrace`, `backtrace_symbols_fd`, `fsync`, `raise`, `signal`, `time`,
// `write`. Anything else — `swift_beginAccess`, `swift_retain`, `malloc`,
// `_assertionFailure`, any Foundation symbol — is a regression. Two of those
// were in fact present in the first draft of this file and are why the state
// below is shaped the way it is.
//
// ── Why it re-raises ──────────────────────────────────────────────────────
// After writing, the handler restores the default disposition and re-raises,
// so macOS still produces its own symbolicated `.ips` report and the process
// still exits with the true crash status. We are adding a breadcrumb, not
// intercepting the crash.
//
// ── Why it is installed from AppEnvironment ───────────────────────────────
// The obvious install site is `applicationDidFinishLaunching`, which lives in
// `AppDelegate.swift` — the single sanctioned AppKit file, which Decision 0005
// says explicitly not to extend. This file needs no AppKit at all (Darwin for
// the signal machinery, Foundation only above the handler), so it is installed
// from `AppEnvironment.live()` instead: the earliest pure-SwiftUI point in the
// process, at `@StateObject` init. A crash *before* that point is simply not
// captured, which is a cheaper price than a new AppKit exception.
//
// There is deliberately no clean-exit hook either. The breadcrumb file is
// created empty at install and only ever written to while dying, so
// "non-empty breadcrumb" *is* the crash signal — no `applicationWillTerminate`
// is needed, and `AppDelegate.swift` stays untouched.

import Darwin
import Foundation
import InterlinedDomain

// MARK: - Signal-time state

/// Everything the handler reads, in one flat allocation.
///
/// The shape is not incidental. A handful of `var` globals would be the
/// obvious spelling, but Swift enforces exclusive access on every global
/// `var` read, which means a `swift_beginAccess` / `swift_endAccess` pair
/// inside the handler. Those maintain a thread-local access list, and a signal
/// delivered while the main thread is midway through updating that list would
/// have the handler walk it in an inconsistent state.
///
/// So all mutable state lives behind a single `let` pointer instead. Reading a
/// `let` global goes through `swift_once`, whose fast path — after
/// `install(...)` has already forced initialisation — is an atomic load and a
/// branch, with no lock and no list to corrupt. Everything past the pointer is
/// plain memory: POD fields, no ARC, no exclusivity checks.
///
/// Every field is a C-compatible primitive. Nothing here is a `String`, an
/// `Array`, or anything else that could be lazily materialised at crash time.
private struct CrashHandlerState {

    /// Descriptor for the breadcrumb file, opened at install time. `-1` means
    /// the handler has nothing to write to and should get out of the way.
    /// Assigned *last* during install, so it doubles as the "everything else
    /// is ready" flag the handler tests.
    var fd: Int32 = -1

    /// Pre-rendered magic + version + build + OS lines.
    var header: UnsafeMutablePointer<CChar>?
    var headerCount: Int = 0

    /// `occurred=` — the field key, pre-rendered.
    var occurredKey: UnsafeMutablePointer<CChar>?
    var occurredKeyCount: Int = 0

    /// `signal=` — the field key, pre-rendered.
    var signalKey: UnsafeMutablePointer<CChar>?
    var signalKeyCount: Int = 0

    /// `--frames--\n`.
    var framesMarker: UnsafeMutablePointer<CChar>?
    var framesMarkerCount: Int = 0

    /// `--end--\n`.
    var endMarker: UnsafeMutablePointer<CChar>?
    var endMarkerCount: Int = 0

    /// Scratch for hand-rolled integer formatting: 20 digits for a `UInt64`
    /// plus the newline the field writer appends.
    var numberScratch: UnsafeMutablePointer<CChar>?

    /// Scratch for `backtrace(3)` — pre-allocated because the handler may not.
    var frameSlots: UnsafeMutablePointer<UnsafeMutableRawPointer?>?

    /// Depth captured. Deep enough to cross the Swift runtime frames that sit
    /// between the trap and the offending line, bounded so a runaway unwind
    /// cannot produce an unbounded file.
    var maxFrames: Int32 = 64

    /// Set on entry to the handler. A *different* fatal signal raised while we
    /// are writing — a bad pointer inside `backtrace`, say — would otherwise
    /// re-enter and start a second block on top of the half-written first one.
    /// `sa_mask` blocks the six we install for; this catches the rest and any
    /// second thread that faults concurrently. Not atomic, and it does not
    /// need to be: the worst outcome of a lost race is a duplicated block, and
    /// the parser already keeps only the first.
    var isHandling: Int32 = 0
}

/// The one global the handler touches. Allocated once, never freed — the
/// handler may need it at any moment for the life of the process, so there is
/// no "after" in which to free it.
private nonisolated(unsafe) let crashState: UnsafeMutablePointer<CrashHandlerState> = {
    let pointer = UnsafeMutablePointer<CrashHandlerState>.allocate(capacity: 1)
    pointer.initialize(to: CrashHandlerState())
    return pointer
}()

/// Signals that mean "this process is dying and it is our fault". `SIGILL` and
/// `SIGTRAP` matter most: those are how Swift traps arrive. Read only from
/// `install(...)`, never from the handler.
private let crashSignals: [Int32] = [SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP]

/// ASCII `0`, spelled as a literal rather than `UInt8(ascii:)`. The stdlib
/// initialiser is a real call carrying a precondition, and a `_assertionFailure`
/// edge inside a signal handler is exactly the kind of thing this file exists
/// to avoid.
private let crashASCIIZero: UInt8 = 48

/// ASCII newline, for the same reason.
private let crashASCIINewline: UInt8 = 10

// MARK: - Signal-safe primitives

/// `write(2)` until the whole buffer is out, retrying a signal-interrupted
/// write and giving up on any other error. It loops because a short write on a
/// regular file is legal, and silently losing the tail of a report would be
/// worse than a marginally longer handler.
private func crashWriteAll(_ fd: Int32, _ bytes: UnsafePointer<CChar>, _ count: Int) {
    var written = 0
    while written < count {
        let result = write(fd, bytes + written, count - written)
        if result > 0 {
            written &+= result
        } else if result < 0 && errno == EINTR {
            continue
        } else {
            return                              // unrecoverable; the report is best-effort
        }
    }
}

/// Renders `value` as decimal ASCII into `buffer` (which must hold at least 20
/// bytes) and returns the length written.
///
/// Deliberately allocation- and trap-free: it counts the digits with a first
/// pass of integer division, then fills the caller's buffer back-to-front
/// using wrapping arithmetic. No scratch array, no `String`, no `snprintf`,
/// and no overflow check that could reach `_assertionFailure`.
private func crashFormat(_ value: UInt64, into buffer: UnsafeMutablePointer<CChar>) -> Int {
    if value == 0 {
        buffer[0] = CChar(bitPattern: crashASCIIZero)
        return 1
    }
    var digitCount = 0
    var probe = value
    while probe > 0 {
        digitCount &+= 1
        probe /= 10
    }
    var remaining = value
    var index = digitCount &- 1
    while remaining > 0 {
        let digit = UInt8(truncatingIfNeeded: remaining % 10)
        buffer[index] = CChar(bitPattern: crashASCIIZero &+ digit)
        remaining /= 10
        index &-= 1
    }
    return digitCount
}

/// Writes one `<key><number>\n` line from pre-rendered parts.
private func crashWriteField(
    _ fd: Int32,
    key: UnsafeMutablePointer<CChar>?,
    keyCount: Int,
    scratch: UnsafeMutablePointer<CChar>?,
    value: UInt64
) {
    guard let key, keyCount > 0, let scratch else { return }
    crashWriteAll(fd, key, keyCount)
    let length = crashFormat(value, into: scratch)
    scratch[length] = CChar(bitPattern: crashASCIINewline)
    crashWriteAll(fd, scratch, length &+ 1)
}

// MARK: - The handler

/// The installed `sa_handler`.
///
/// A file-scope `func` that captures nothing, so Swift converts it to a
/// `@convention(c)` function pointer with no context object and therefore no
/// allocation. Read the body against the safety rules at the top of this file
/// before changing a single line of it.
private func crashSignalHandler(_ signalNumber: Int32) {
    // One read of the `let` global, then plain memory for the rest.
    let state = crashState
    let fd = state.pointee.fd
    // Re-entry: something faulted while we were writing. Do not try again —
    // just restore the default disposition and let the process die, so a
    // cascading fault cannot turn a crash into a hang.
    if state.pointee.isHandling != 0 {
        signal(signalNumber, SIG_DFL)
        raise(signalNumber)
        return
    }
    state.pointee.isHandling = 1
    if fd >= 0 {
        if let header = state.pointee.header, state.pointee.headerCount > 0 {
            crashWriteAll(fd, header, state.pointee.headerCount)
        }
        // `time(3)` is on the POSIX async-signal-safe list. A failed call
        // returns -1, in which case we write 0 and the reader falls back to
        // "now" — a wrong timestamp is not worth risking anything for.
        let now = time(nil)
        crashWriteField(
            fd,
            key: state.pointee.occurredKey,
            keyCount: state.pointee.occurredKeyCount,
            scratch: state.pointee.numberScratch,
            // Non-trapping conversions throughout: a trapping integer
            // initialiser would give this function an edge into
            // `_assertionFailure`, which allocates. Even an unreachable one
            // does not belong in a signal handler.
            value: now > 0 ? UInt64(bitPattern: Int64(truncatingIfNeeded: now)) : 0
        )
        crashWriteField(
            fd,
            key: state.pointee.signalKey,
            keyCount: state.pointee.signalKeyCount,
            scratch: state.pointee.numberScratch,
            value: UInt64(truncatingIfNeeded: UInt32(bitPattern: signalNumber))
        )

        if let marker = state.pointee.framesMarker, state.pointee.framesMarkerCount > 0 {
            crashWriteAll(fd, marker, state.pointee.framesMarkerCount)
        }
        if let slots = state.pointee.frameSlots {
            let captured = backtrace(slots, state.pointee.maxFrames)
            backtrace_symbols_fd(slots, captured, fd)
        }
        if let marker = state.pointee.endMarker, state.pointee.endMarkerCount > 0 {
            crashWriteAll(fd, marker, state.pointee.endMarkerCount)
        }
        // Force the bytes to disk before we re-raise: the re-raised signal
        // takes the process out immediately, and we would rather pay an fsync
        // in a dying process than lose the report.
        fsync(fd)
    }

    // Restore the default disposition and re-raise so macOS still writes its
    // own symbolicated report. We are adding a breadcrumb, not swallowing the
    // crash.
    signal(signalNumber, SIG_DFL)
    raise(signalNumber)
}

// MARK: - Install

enum CrashSignalHandler {

    /// Guards against a second install — SwiftUI can evaluate a scene body
    /// more than once — leaking descriptors or re-truncating a breadcrumb we
    /// are in the middle of reading.
    private nonisolated(unsafe) static var isInstalled = false

    /// The pre-rendered header, kept as a `String` for the *ObjC* path only.
    /// The signal handler reads the C-buffer copy instead; this one exists
    /// because `crashHeaderBytes` is intentionally not NUL-terminated.
    private nonisolated(unsafe) static var headerText = ""

    /// Alternate signal stack. A stack-overflow `SIGSEGV` arrives with no
    /// usable stack left, so without this the handler itself faults and the
    /// report is lost. Allocated once and never freed — the handler may need
    /// it at any moment for the life of the process.
    private nonisolated(unsafe) static var alternateStack: UnsafeMutableRawPointer?

    /// Opens the breadcrumb, pre-renders every byte the handler will need, and
    /// registers the handlers. Everything unsafe happens *here*, at launch, on
    /// the main thread, where allocation is fine.
    ///
    /// - Important: call this **after** the previous run's breadcrumb has been
    ///   read — opening truncates the file. `AppEnvironment.live()` enforces
    ///   that ordering.
    /// - Parameters:
    ///   - breadcrumbURL: destination file. `nil` (the XCTest case, where
    ///     `FileLog` is disabled) makes this a no-op.
    ///   - appVersion / build / osVersion: baked into the pre-rendered header.
    /// - Returns: whether the handlers were installed, for the caller to log.
    @discardableResult
    static func install(
        breadcrumbURL: URL?,
        appVersion: String,
        build: String,
        osVersion: String
    ) -> Bool {
        guard !isInstalled, let breadcrumbURL else { return false }

        // O_TRUNC: a clean run must leave a zero-byte file, because
        // "non-empty" is what the next launch reads as "we crashed".
        let fd = breadcrumbURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        }
        guard fd >= 0 else { return false }
        // Keep the descriptor out of any child process (the bundled sync
        // agent) so a fork/exec cannot inherit a writable handle on it.
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)

        headerText = CrashBreadcrumbFormat.staticHeader(
            appVersion: appVersion,
            build: build,
            osVersion: osVersion
        )
        // Touching `crashState` here is what forces its `swift_once` to run,
        // so by the time a signal can arrive the handler's only global read is
        // already on the fast path.
        let state = crashState
        state.pointee.header = allocateBytes(headerText, count: &state.pointee.headerCount)
        state.pointee.occurredKey = allocateBytes("occurred=", count: &state.pointee.occurredKeyCount)
        state.pointee.signalKey = allocateBytes("signal=", count: &state.pointee.signalKeyCount)
        state.pointee.framesMarker = allocateBytes(
            CrashBreadcrumbFormat.framesMarker + "\n",
            count: &state.pointee.framesMarkerCount
        )
        state.pointee.endMarker = allocateBytes(
            CrashBreadcrumbFormat.endMarker + "\n",
            count: &state.pointee.endMarkerCount
        )
        // Both scratch buffers are initialised rather than merely allocated so
        // their pages are already resident and dirty; a handler running after
        // a stack overflow should not need the VM system to fault one in.
        let scratch = UnsafeMutablePointer<CChar>.allocate(capacity: 32)
        scratch.initialize(repeating: 0, count: 32)
        state.pointee.numberScratch = scratch
        let frameCount = Int(state.pointee.maxFrames)
        let slots = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: frameCount)
        slots.initialize(repeating: nil, count: frameCount)
        state.pointee.frameSlots = slots

        installAlternateStack()

        // Assigned last: the handler tests this descriptor, so it must not go
        // live until every buffer above exists.
        state.pointee.fd = fd

        var action = sigaction()
        action.__sigaction_u.__sa_handler = crashSignalHandler
        // SA_ONSTACK pairs with `installAlternateStack()` above — together
        // they are what make a stack-overflow crash reportable at all.
        // SA_RESETHAND is deliberately *not* set; the explicit SIG_DFL +
        // re-raise at the end of the handler states the intent more plainly.
        action.sa_flags = Int32(SA_ONSTACK)
        // Block every fatal signal we handle for the duration of the handler,
        // so one cannot interrupt another mid-write and interleave two blocks
        // in the breadcrumb.
        sigemptyset(&action.sa_mask)
        for signalNumber in crashSignals {
            sigaddset(&action.sa_mask, signalNumber)
        }
        for signalNumber in crashSignals {
            sigaction(signalNumber, &action, nil)
        }

        // The ObjC path. Not a signal context, so this closure may allocate —
        // but it must capture nothing, because `NSSetUncaughtExceptionHandler`
        // takes a bare C function pointer.
        NSSetUncaughtExceptionHandler { exception in
            CrashSignalHandler.recordUncaughtException(exception)
        }

        isInstalled = true
        return true
    }

    /// Gives the process a dedicated stack for signal handlers to run on.
    private static func installAlternateStack() {
        let size = max(Int(SIGSTKSZ), 64 * 1024)
        let memory = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        alternateStack = memory
        var stack = stack_t(ss_sp: memory, ss_size: size, ss_flags: 0)
        sigaltstack(&stack, nil)
    }

    /// Writes an exception block. Runs on the normal ObjC unwind path — before
    /// the `abort()` that becomes SIGABRT — so Foundation is legal here and we
    /// can afford a real reason string.
    ///
    /// The SIGABRT that follows appends a second block; the reader keeps the
    /// first, which is this richer one.
    private static func recordUncaughtException(_ exception: NSException) {
        let fd = crashState.pointee.fd
        guard fd >= 0 else { return }
        // `sanitize` flattens newlines so a multi-line reason cannot forge
        // extra `key=value` lines or a second block when parsed back.
        let name = CrashBreadcrumbFormat.sanitize(exception.name.rawValue)
        let reason = CrashBreadcrumbFormat.sanitize(exception.reason ?? "")
        let frames = exception.callStackSymbols
            .prefix(Int(crashState.pointee.maxFrames))
            .joined(separator: "\n")
        let block = headerText
            + "occurred=\(Int(Date().timeIntervalSince1970))\n"
            + "signal=\(CrashBreadcrumbFormat.exceptionSignal)\n"
            + "name=\(name)\n"
            + "reason=\(reason)\n"
            + CrashBreadcrumbFormat.framesMarker + "\n"
            + frames + "\n"
            + CrashBreadcrumbFormat.endMarker + "\n"
        var bytes = Array(block.utf8)
        bytes.withUnsafeMutableBufferPointer { buffer in
            buffer.withMemoryRebound(to: CChar.self) { rebound in
                if let base = rebound.baseAddress {
                    crashWriteAll(fd, base, rebound.count)
                }
            }
        }
        fsync(fd)
    }

    /// Copies `string`'s UTF-8 into a heap buffer that is deliberately never
    /// freed and deliberately **not** NUL-terminated — the handler writes it
    /// by explicit length, and it must stay readable for the life of the
    /// process, so there is no "after" in which to free it.
    private static func allocateBytes(
        _ string: String,
        count: inout Int
    ) -> UnsafeMutablePointer<CChar> {
        let bytes = Array(string.utf8)
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: max(bytes.count, 1))
        for (index, byte) in bytes.enumerated() {
            buffer[index] = CChar(bitPattern: byte)
        }
        count = bytes.count
        return buffer
    }

    #if DEBUG
    /// Debug-only crash triggers used to verify the whole loop by hand
    /// (crash → relaunch → sheet). The signal handler itself cannot be unit
    /// tested in-process — it ends the process by design — so this is how it
    /// gets exercised. Never compiled into a release build.
    enum SimulatedCrash: String, CaseIterable, Identifiable {
        case trap, segmentationFault, abort, uncaughtException

        var id: String { rawValue }

        var title: String {
            switch self {
            case .trap:              return "Swift trap (fatalError)"
            case .segmentationFault: return "Segmentation fault (SIGSEGV)"
            case .abort:             return "Abort (SIGABRT)"
            case .uncaughtException: return "Uncaught NSException"
            }
        }
    }

    /// Kills this process on purpose. Only reachable from the debug-only
    /// affordance in the crash-reporting Settings pane.
    static func simulateCrash(_ kind: SimulatedCrash) {
        switch kind {
        case .trap:
            fatalError("Simulated crash: fatalError trap (issue #29 verification)")
        case .segmentationFault:
            raise(SIGSEGV)
        case .abort:
            raise(SIGABRT)
        case .uncaughtException:
            NSException(
                name: .init("InterlinedListSimulatedCrash"),
                reason: "Simulated crash: uncaught exception (issue #29 verification)",
                userInfo: nil
            ).raise()
        }
    }
    #endif
}
