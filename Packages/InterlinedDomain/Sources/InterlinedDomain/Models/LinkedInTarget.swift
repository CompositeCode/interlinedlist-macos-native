import Foundation
import InterlinedKit

// MARK: - LinkedInTarget

/// A LinkedIn destination the user can cross-post to (work-consolidation.md G11a).
public struct LinkedInTarget: Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Equatable, Hashable {
        case personal
        case org
        case other
    }

    public let kind: Kind
    public let label: String
    public let avatarURL: URL?
    public let isEnabled: Bool

    public var id: String { "\(kind.rawValue):\(label)" }

    public init(kind: Kind, label: String, avatarURL: URL? = nil, isEnabled: Bool = false) {
        self.kind = kind
        self.label = label
        self.avatarURL = avatarURL
        self.isEnabled = isEnabled
    }
}

extension LinkedInTarget {
    public init(from dto: LinkedInTargetDTO) {
        let kind: Kind
        switch dto.kind.lowercased() {
        case "personal": kind = .personal
        case "org", "organization": kind = .org
        default: kind = .other
        }
        self.init(
            kind: kind,
            label: dto.label,
            avatarURL: dto.avatarUrl.flatMap(URL.init(string:)),
            isEnabled: dto.enabled ?? false
        )
    }
}

// MARK: - LinkedInPostingTargets

/// The user's LinkedIn posting targets plus whether org pages are unavailable.
public struct LinkedInPostingTargets: Sendable, Equatable {
    public let targets: [LinkedInTarget]
    /// `true` when the LinkedIn org scope isn't granted (org pages unavailable —
    /// G11b, deferred).
    public let orgScopeMissing: Bool

    public init(targets: [LinkedInTarget], orgScopeMissing: Bool = false) {
        self.targets = targets
        self.orgScopeMissing = orgScopeMissing
    }

    public static let empty = LinkedInPostingTargets(targets: [], orgScopeMissing: false)
}

extension LinkedInPostingTargets {
    public init(from dto: LinkedInPostingTargetsResponse) {
        self.init(
            targets: dto.targets.map(LinkedInTarget.init(from:)),
            orgScopeMissing: dto.orgScopeMissing ?? false
        )
    }
}
