import Foundation
import InterlinedKit

// MARK: - LinkedInServicing

/// The LinkedIn posting-targets surface (the-gaps.md G11a) — read the user's
/// available cross-post destinations (personal profile + any org pages) so the
/// composer can offer a target picker. Read-only for now; the enable/sync
/// writes (`PUT /api/linkedin/posting-targets`, `POST /api/linkedin/sync-pages`)
/// and org pages (G11b) are deferred.
public protocol LinkedInServicing: Sendable {
    func postingTargets() async throws -> LinkedInPostingTargets
}

// MARK: - LinkedInService

public final class LinkedInService: LinkedInServicing {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func postingTargets() async throws -> LinkedInPostingTargets {
        LinkedInPostingTargets(from: try await api.send(LinkedIn.postingTargets()))
    }
}
