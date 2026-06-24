// FollowRelationshipReader
//
// App-layer adapter that reads `FollowRelationship` for a userId.
//
// **Why this file exists.** `SocialServicing.status(of:)` returns the
// Kit-level `FollowStatusDTO` today (the read-side surface predates
// Wave 6.1's domain shift on the write side). A view model that needs
// the relationship for the M5 follow-button initial state therefore
// can't call `status(of:)` directly without `import InterlinedKit`,
// which Decision 0003 forbids for `App/Features/**`.
//
// The composition root **is** allowed to import the kit (Decision 0003
// names `App/Composition/AppEnvironment.swift` explicitly). This file
// is a sibling adapter that crosses the same boundary: it imports the
// kit only to bind `FollowStatusDTO`, immediately wraps it in the
// domain `FollowRelationship`, and hands the domain value back. View
// models depend on `FollowRelationshipReading` (the protocol below),
// never on the adapter's concrete type, so unit tests substitute a
// stub.
//
// This is a temporary shim — the cleanest fix is to migrate
// `SocialServicing.status(of:)` to return a domain `FollowRelationship`,
// which removes the need for any adapter. Tracked as a follow-up so
// future App code doesn't have to know this file exists.

import Foundation
import InterlinedDomain
import InterlinedKit

/// The follow-relationship read surface the App-layer M5 view models
/// bind against. Returns the domain `FollowRelationship` so callers
/// never need to know about the underlying Kit DTO.
protocol FollowRelationshipReading: Sendable {
    func relationship(with userID: String) async throws -> FollowRelationship
}

/// Concrete reader backed by `SocialServicing.status(of:)`. The wrap
/// from `FollowStatusDTO` to `FollowRelationship` is total and
/// lossless — see `FollowMappers.swift` for the domain extension.
final class SocialFollowRelationshipReader: FollowRelationshipReading {

    private let social: SocialServicing

    init(social: SocialServicing) {
        self.social = social
    }

    func relationship(with userID: String) async throws -> FollowRelationship {
        let dto = try await social.status(of: userID)
        return FollowRelationship(from: dto)
    }
}
