import Foundation

/// Centralised, identical encoder and decoder configuration used by every
/// piece of the kit (the client, the per-endpoint helpers, and tests). This
/// guarantees that what an endpoint sends and what it receives are speaking
/// the exact same JSON dialect.
///
/// **Date strategy:** ISO 8601 with fractional seconds **and** plain ISO
/// 8601 — the InterlinedList API emits both depending on the field, so we
/// accept either and emit the richer form.
public enum JSONCoders {

    /// Shared decoder. Configure once, reuse everywhere.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Self.iso8601Fractional.date(from: string) {
                return date
            }
            if let date = Self.iso8601.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date string, got \"\(string)\""
            )
        }
        return decoder
    }

    /// Shared encoder. Mirrors the decoder's date strategy.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.iso8601Fractional.string(from: date))
        }
        return encoder
    }

    // MARK: - Internals

    nonisolated(unsafe) static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
