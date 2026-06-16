import Foundation

// MARK: - CSVExport

/// The result of a CSV export endpoint (`GET /api/exports/*`).
///
/// Export endpoints return a CSV file, not JSON, so the kit surfaces the raw
/// bytes plus the server's `Content-Type` rather than a decoded DTO. Callers
/// run these through `APIClient.sendRaw(_:)`; this value type wraps that
/// `(Data, String?)` pair with convenience accessors for writing to an
/// `NSSavePanel` destination or rendering a preview.
public struct CSVExport: Sendable, Equatable {
    /// The raw CSV bytes exactly as returned by the server.
    public let data: Data
    /// The server-reported MIME type (expected `text/csv`), if present.
    public let contentType: String?

    public init(data: Data, contentType: String? = nil) {
        self.data = data
        self.contentType = contentType
    }

    /// The CSV decoded as UTF-8 text. `nil` if the bytes are not valid UTF-8.
    public var text: String? {
        String(data: data, encoding: .utf8)
    }

    /// Convenience builder from `APIClient.sendRaw(_:)`'s return tuple.
    public static func from(_ raw: (Data, String?)) -> CSVExport {
        CSVExport(data: raw.0, contentType: raw.1)
    }
}
