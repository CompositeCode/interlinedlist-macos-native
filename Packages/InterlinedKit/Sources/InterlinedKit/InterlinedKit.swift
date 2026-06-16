// InterlinedKit
//
// Networking and API client layer for InterlinedList. See PLAN.md §3 for
// the layered breakdown:
//
//   APIClient/   — Request value type, HTTPDataTransport seam, JSON coders,
//                  the URLSession-backed `APIClient` and `RetryPolicy`.
//   Auth/        — `TokenStore` (Keychain + in-memory), `AuthService`, and
//                  `AuthTransport` implementing decision 0001.
//   Endpoints/   — per-group request builders (Messages, Lists, Documents,
//                  …). Each group is a separate file added by the step-2
//                  agents using the pattern documented in `Request.swift`.
//   DTOs/        — Codable types mirroring API response shapes 1:1.
//   Pagination/  — `Paginated<T>` envelope + `PageIterator` async sequence.
//   Errors/      — `APIError` and `APIErrorBody`.

import Foundation

/// Namespace marker for the InterlinedKit module. Holds a single constant
/// so tests have a stable, public symbol to assert against and so any future
/// kit-wide configuration has a documented home.
public enum InterlinedKit {
    /// The semantic version of the kit's public surface. Incremented when
    /// breaking changes ship.
    public static let schemaVersion: String = "0.1.0-Wave1"

    /// The production base URL. Tests construct an `APIClient` with a stub
    /// URL; production code that needs to override (staging, mocks) injects
    /// its own.
    public static let defaultBaseURL: URL = URL(string: "https://interlinedlist.com")!
}
