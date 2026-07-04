import Foundation

/// Domain-layer value wrapping a CSV export response from the server
/// (`GET /api/exports/*`).
///
/// Shape mirrors `InterlinedKit.CSVExport` but lives at the domain boundary
/// so App-layer features never need to import `InterlinedKit` directly
/// (Decision 0003). `ExportsService` maps from the kit's raw tuple to this
/// type before returning it to any consumer above the domain seam.
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
}
