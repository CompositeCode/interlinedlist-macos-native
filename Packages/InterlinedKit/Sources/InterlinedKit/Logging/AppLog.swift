import Foundation
import os

/// App-wide logging facade.
///
/// Every call mirrors to Apple's unified logging (visible live in Console.app
/// and `log stream`) **and** appends to a rotating file under the app's
/// container so a user can send it for debugging later. Under the sandbox the
/// file lives at:
///
///   ~/Library/Containers/<bundle-id>/Data/Library/Logs/InterlinedList/interlinedlist.log
///
/// The unified-logging side keeps the existing on-device behaviour; the file
/// side is the new, retrievable artifact. User-facing UI text is produced
/// separately (see `APIError.userFacingMessage`) — the log holds the full
/// technical detail, the UI shows the friendly message.
public struct AppLog: Sendable {

    /// Log severity. Mirrors the `os.Logger` levels we actually use.
    public enum Level: String, Sendable {
        case debug, info, notice, warning, error, fault
    }

    /// The unified-logging subsystem shared across the app and its packages.
    public static let subsystem = "com.interlinedlist.macos"

    private let category: String
    private let osLogger: Logger
    private let file: FileLog

    /// - Parameters:
    ///   - category: groups related messages (e.g. `"APIClient"`).
    ///   - file: the file sink. Defaults to the process-wide `.shared` log so
    ///     every category writes to the same file; injectable for tests.
    public init(category: String, file: FileLog = .shared) {
        self.category = category
        self.osLogger = Logger(subsystem: AppLog.subsystem, category: category)
        self.file = file
    }

    public func error(_ message: @autoclosure () -> String)   { log(.error, message()) }
    public func warning(_ message: @autoclosure () -> String) { log(.warning, message()) }
    public func notice(_ message: @autoclosure () -> String)  { log(.notice, message()) }
    public func info(_ message: @autoclosure () -> String)    { log(.info, message()) }
    public func debug(_ message: @autoclosure () -> String)   { log(.debug, message()) }

    public func log(_ level: Level, _ message: String) {
        // `.public` privacy: these strings are already scrubbed of user data
        // by the callers (we log error *structure*, not response bodies).
        switch level {
        case .debug:   osLogger.debug("\(message, privacy: .public)")
        case .info:    osLogger.info("\(message, privacy: .public)")
        case .notice:  osLogger.notice("\(message, privacy: .public)")
        case .warning: osLogger.warning("\(message, privacy: .public)")
        case .error:   osLogger.error("\(message, privacy: .public)")
        case .fault:   osLogger.fault("\(message, privacy: .public)")
        }
        file.append(level: level, category: category, message: message)
    }
}

/// The rotating file sink behind `AppLog`.
///
/// Thread-safety is provided by a private serial queue; writes are
/// fire-and-forget so logging never blocks the caller. `@unchecked Sendable`
/// is sound because every stored property is immutable and the only mutable
/// state (the file on disk, the shared date formatter) is touched solely on
/// `queue`.
public final class FileLog: @unchecked Sendable {

    /// The process-wide log used by `AppLog` when no sink is injected.
    public static let shared = FileLog()

    private let queue = DispatchQueue(label: "com.interlinedlist.filelog")
    private let fileURL: URL?
    private let maxBytes: Int
    private let formatter: ISO8601DateFormatter

    /// - Parameters:
    ///   - directory: where the log file is written. `nil` disables file
    ///     logging entirely (every `append` becomes a no-op) — used under
    ///     XCTest so unit runs never touch the real `~/Library`.
    ///   - fileName: the active log file's name.
    ///   - maxBytes: rotate once the active file reaches this size. One
    ///     previous generation is kept as `<fileName>.1`.
    public init(
        directory: URL? = FileLog.defaultDirectory(),
        fileName: String = "interlinedlist.log",
        maxBytes: Int = 5 * 1024 * 1024
    ) {
        self.maxBytes = maxBytes
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter

        if let directory {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            self.fileURL = directory.appendingPathComponent(fileName)
        } else {
            self.fileURL = nil
        }
    }

    /// The app's log directory inside the (sandbox) container's `Library/Logs`,
    /// or `nil` when running under XCTest so tests don't write to real Library.
    public static func defaultDirectory() -> URL? {
        if isRunningUnderTests { return nil }
        guard let library = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        return library.appendingPathComponent("Logs/InterlinedList", isDirectory: true)
    }

    /// True inside a unit-test host. `XCTestConfigurationFilePath` covers Xcode;
    /// SwiftPM's `swift test` doesn't set it, so also sniff the loaded XCTest
    /// runtime (never linked into the shipping app).
    private static var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// The active log file on disk, if file logging is enabled. Useful for a
    /// future "Export Logs…" affordance.
    public var currentFileURL: URL? { fileURL }

    /// Appends one line: `<ISO-8601 timestamp> [LEVEL] <category>: <message>`.
    public func append(level: AppLog.Level, category: String, message: String) {
        guard let fileURL else { return }
        let now = Date()
        queue.async {
            self.rotateIfNeeded(fileURL: fileURL)
            let line = "\(self.formatter.string(from: now)) "
                + "[\(level.rawValue.uppercased())] \(category): \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                // File doesn't exist yet (first write, or just rotated).
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    /// Rotates `interlinedlist.log` → `interlinedlist.log.1` once it grows past
    /// `maxBytes`, discarding any older generation. Must run on `queue`.
    private func rotateIfNeeded(fileURL: URL) {
        let fm = FileManager.default
        guard
            let attributes = try? fm.attributesOfItem(atPath: fileURL.path),
            let size = attributes[.size] as? Int,
            size >= maxBytes
        else { return }
        let backup = fileURL.appendingPathExtension("1")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: fileURL, to: backup)
    }
}
