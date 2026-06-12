// InterlinedKit
//
// Networking and API client layer for InterlinedList.
// This is a milestone M0 placeholder namespace. The real API client,
// auth (Keychain-backed TokenStore), endpoint builders, DTOs, pagination,
// and error mapping arrive in Wave 1 per PLAN.md §3 and §6.

import Foundation

/// Namespace marker for the InterlinedKit module.
///
/// See PLAN.md §3 for the layered breakdown:
/// `APIClient`, `Endpoints`, `DTOs`, `Auth`, `Pagination`, `Errors`.
public enum InterlinedKit {
    /// The semantic version of the kit's public surface. Incremented when
    /// breaking changes ship.
    public static let schemaVersion: String = "0.0.1-M0"
}
