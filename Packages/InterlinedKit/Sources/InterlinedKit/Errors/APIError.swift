import Foundation

/// Seed error type for the InterlinedList API layer.
///
/// Wave 1 will expand this into a richer enum that maps status codes,
/// `{ "error": "…" }` response bodies, and transport failures per PLAN.md §3.
/// For M0 it carries a single human-readable message so the type exists,
/// is `Sendable`, and can be threaded through stubs and tests.
public struct APIError: Error, Equatable, Sendable {
    /// Server-supplied (or locally synthesised) human-readable message.
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

extension APIError: CustomStringConvertible {
    public var description: String { message }
}
