import Foundation

/// Configured JSON coders for the InterlinedList API.
///
/// The API emits ISO-8601 timestamps, usually with fractional seconds
/// (`2026-06-20T14:00:00.000Z`) but occasionally without. The decoder accepts
/// both; the encoder always writes fractional seconds.
///
/// `ISO8601DateFormatter` is not `Sendable`, so the shared instances are held as
/// `nonisolated(unsafe)` globals and every access is serialized through a lock.
public enum JSONCoding {

    private static let lock = NSLock()

    private nonisolated(unsafe) static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Self.parseISO8601(string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date: \(string)"
            )
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.iso8601String(date))
        }
        return encoder
    }

    // MARK: - ISO-8601 helpers (lock-guarded)

    /// Parses an ISO-8601 timestamp with or without fractional seconds.
    public static func parseISO8601(_ string: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string)
    }

    /// Formats a `Date` as an ISO-8601 string with fractional seconds, suitable
    /// for the `lastSyncAt` query parameter.
    public static func iso8601String(_ date: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        return fractionalFormatter.string(from: date)
    }
}
