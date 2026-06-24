// StubFollowRelationshipReader
//
// Deterministic stand-in for `FollowRelationshipReading` used by
// `FollowButtonViewModelTests` and `ProfileViewModelTests`. Holds one
// outcome at a time keyed by userID; falls back to a default outcome
// when no per-id entry is set.

import Foundation
import InterlinedDomain
@testable import InterlinedList

actor StubFollowRelationshipReader: FollowRelationshipReading {

    private var outcomes: [String: Result<FollowRelationship, Error>] = [:]
    private var defaultOutcome: Result<FollowRelationship, Error> = .success(
        FollowRelationship(isFollowing: false, isFollowedBy: false, hasPendingRequest: false)
    )

    private(set) var recordedUserIDs: [String] = []

    func enqueue(_ relationship: FollowRelationship, for userID: String) {
        outcomes[userID] = .success(relationship)
    }

    func enqueueFailure(_ error: Error, for userID: String) {
        outcomes[userID] = .failure(error)
    }

    func setDefault(_ relationship: FollowRelationship) {
        defaultOutcome = .success(relationship)
    }

    func relationship(with userID: String) async throws -> FollowRelationship {
        recordedUserIDs.append(userID)
        let outcome = outcomes[userID] ?? defaultOutcome
        switch outcome {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}
