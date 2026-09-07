// CrashReport
//
// The domain value produced by parsing the crash *breadcrumb* the previous
// run left behind (GitHub issue #29, PR 1).
//
// Why a breadcrumb at all: a Swift trap (force-unwrapped nil, index out of
// range, `fatalError`) is delivered as a POSIX signal, not a catchable error,
// and a signal handler may not allocate, touch Foundation, or show UI. So the
// crashing process only ever writes a small pre-formatted text file; the *next*
// launch reads it, turns it into this type, and asks the user what to do.
//
// The type is deliberately dumb data: no I/O, no formatting policy. Parsing
// lives in `CrashReportStore`, redaction in `CrashReportRedactor`, and issue
// composition in `CrashReportURLBuilder`.

import Foundation

// MARK: - CrashBreadcrumbFormat

/// The on-disk breadcrumb grammar, shared by the writer (the App target's
/// `CrashSignalHandler`) and the reader (`CrashReportStore`).
///
/// It is a line-oriented plain-text format rather than JSON for one reason:
/// the signal handler that writes it cannot allocate, so it can only `write(2)`
/// byte buffers that were rendered before the crash. Every token below is an
/// ASCII literal the handler can hold in a pre-allocated C buffer.
///
/// A breadcrumb file holds one *or more* blocks, each introduced by `magic`:
/// the uncaught-`NSException` handler writes a block, and the `SIGABRT` that
/// follows makes the signal handler append a second one. The parser keeps the
/// first complete block, which is the richer exception block when both ran.
///
///     INTERLINEDLIST-CRASH/1
///     occurred=1757160000
///     version=0.1.0
///     build=42
///     os=15.4.0
///     signal=11
///     name=SIGSEGV
///     reason=<single line, newlines escaped as \n>
///     --frames--
///     0   InterlinedList   0x000000010a1b2c3d $s14InterlinedList3fooyyF + 40
///     --end--
public enum CrashBreadcrumbFormat {

    /// First line of every block. Doubles as the block separator and as the
    /// "this file is really ours" guard — a zero-byte or foreign file parses
    /// to `nil` rather than a bogus report.
    public static let magic = "INTERLINEDLIST-CRASH/1"

    /// Separates the `key=value` header from the raw backtrace lines.
    public static let framesMarker = "--frames--"

    /// Terminates a block. Absent when the process died mid-write; the parser
    /// treats end-of-file as an equally valid terminator.
    public static let endMarker = "--end--"

    /// `signal=` value used by the uncaught-`NSException` path, which is not a
    /// signal delivery at all.
    public static let exceptionSignal: Int32 = 0

    /// File name of the breadcrumb, written alongside the rotating app log so
    /// both artifacts live in one place a user can be pointed at.
    public static let fileName = "crash-breadcrumb.txt"

    /// The part of a block that is knowable *before* the crash: magic line
    /// plus the build and OS identity.
    ///
    /// The signal handler renders this once at install time into a
    /// pre-allocated C buffer, because at crash time it may not allocate or
    /// call into Foundation to build a string. Everything the handler adds
    /// afterwards (`occurred=`, `signal=`, the frames) is either a plain
    /// integer it can format arithmetically or bytes `backtrace_symbols_fd`
    /// writes itself.
    ///
    /// Note the absence of `name=`: mapping 11 → `SIGSEGV` would need a lookup
    /// the handler cannot safely perform, so the reader derives the name from
    /// the number instead (`CrashReport.signalName(_:)`).
    public static func staticHeader(
        appVersion: String,
        build: String,
        osVersion: String
    ) -> String {
        """
        \(magic)
        version=\(sanitize(appVersion))
        build=\(sanitize(build))
        os=\(sanitize(osVersion))

        """
    }

    /// Flattens a header value onto one physical line so it cannot forge extra
    /// `key=value` lines or a second block when parsed back.
    public static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

// MARK: - CrashReport

/// One crash recovered from the previous run.
public struct CrashReport: Sendable, Equatable, Codable, Identifiable {

    /// Stable across launches (see `signature`), so it is also a usable
    /// SwiftUI identity and — in PR 2 — the deduplication key.
    public var id: String { signature }

    /// POSIX signal number, or `CrashBreadcrumbFormat.exceptionSignal` (0)
    /// when the crash came in through the ObjC uncaught-exception path.
    public let signal: Int32

    /// `SIGSEGV`, `SIGABRT`, … or the `NSException` name.
    public let name: String

    /// The `NSException` reason, when there was one. Never populated on the
    /// signal path — a signal carries no message.
    public let reason: String?

    /// Raw `backtrace_symbols_fd` (or `NSException.callStackSymbols`) lines,
    /// in crash order, innermost frame first.
    public let frames: [String]

    /// `CFBundleShortVersionString` of the build that crashed.
    public let appVersion: String

    /// `CFBundleVersion` of the build that crashed.
    public let build: String

    /// `ProcessInfo.operatingSystemVersion` of the machine that crashed.
    public let osVersion: String

    /// When the crash happened, from `time(2)` inside the handler.
    public let occurredAt: Date

    /// Launch-stable fingerprint of the top frames — see `signature(name:frames:)`.
    public let signature: String

    public init(
        signal: Int32,
        name: String,
        reason: String? = nil,
        frames: [String],
        appVersion: String,
        build: String,
        osVersion: String,
        occurredAt: Date,
        signature: String? = nil
    ) {
        self.signal = signal
        self.name = name
        self.reason = reason
        self.frames = frames
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
        self.occurredAt = occurredAt
        self.signature = signature ?? Self.signature(name: name, frames: frames)
    }

    /// True when the crash arrived as an uncaught ObjC exception rather than
    /// a signal. Only affects presentation — both paths report identically.
    public var isException: Bool { signal == CrashBreadcrumbFormat.exceptionSignal }

    /// Short form used in an issue title, e.g. `Crash: SIGSEGV (a1b2c3d4)`.
    public var shortSignature: String { String(signature.prefix(8)) }

    // MARK: - Signature

    /// Number of leading frames folded into the signature. Deep enough to tell
    /// two different crash sites apart, shallow enough that the same bug
    /// reached from two callers still collapses to one signature.
    public static let signatureFrameCount = 5

    /// Launch-stable fingerprint of a crash.
    ///
    /// Deliberately **not** `Hasher`: Swift's standard hashing is seeded per
    /// process, so the same crash would fingerprint differently on every run
    /// and dedup (PR 2) could never match. This is FNV-1a over normalised
    /// frames instead — pure, deterministic, and identical across launches
    /// and machines.
    public static func signature(name: String, frames: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325          // FNV-1a 64-bit offset basis
        func mix(_ string: String) {
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3      // FNV-1a 64-bit prime
            }
            hash ^= 0x0A
            hash = hash &* 0x0000_0100_0000_01B3
        }
        mix(name)
        for frame in frames.prefix(signatureFrameCount) {
            mix(normalizedFrame(frame))
        }
        return String(hash, radix: 16)
    }

    /// Strips everything address-dependent out of one `backtrace_symbols_fd`
    /// line so the same crash fingerprints identically across launches.
    ///
    /// Input:  `3   InterlinedList   0x000000010a1b2c3d  $s14InterlinedList3fooyyF + 40`
    /// Output: `InterlinedList $s14InterlinedList3fooyyF`
    ///
    /// The frame index, the ASLR-slid load address and the `+ <offset>` tail
    /// all change run to run; the binary name and the mangled symbol do not.
    public static func normalizedFrame(_ frame: String) -> String {
        var fields = frame.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // Leading frame index.
        if let first = fields.first, first.allSatisfy(\.isNumber) { fields.removeFirst() }
        // The `+ <offset>` tail.
        if let plus = fields.lastIndex(of: "+"), plus >= fields.count - 2 {
            fields.removeSubrange(plus...)
        }
        // Any bare hex load address.
        fields.removeAll { $0.hasPrefix("0x") }
        return fields.joined(separator: " ")
    }

    // MARK: - Signal names

    /// Human name for the signals the handler installs for, so a report reads
    /// `SIGSEGV` rather than `11`. Unknown numbers fall back to `signal <n>`
    /// instead of losing the information.
    public static func signalName(_ signal: Int32) -> String {
        switch signal {
        case SIGABRT: return "SIGABRT"
        case SIGBUS:  return "SIGBUS"
        case SIGFPE:  return "SIGFPE"
        case SIGILL:  return "SIGILL"
        case SIGSEGV: return "SIGSEGV"
        case SIGTRAP: return "SIGTRAP"
        case CrashBreadcrumbFormat.exceptionSignal: return "NSException"
        default: return "signal \(signal)"
        }
    }
}
