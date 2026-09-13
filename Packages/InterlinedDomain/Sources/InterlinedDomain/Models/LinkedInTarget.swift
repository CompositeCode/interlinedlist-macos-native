import Foundation
import InterlinedKit

// MARK: - LinkedInTarget

/// A LinkedIn destination the user can cross-post to (work-consolidation.md G11a).
public struct LinkedInTarget: Sendable, Equatable, Hashable, Identifiable {

    /// The three destination kinds the API defines
    /// (`/help/api/linkedin-integration`).
    ///
    /// `orgPage` was previously modelled as `org`, which matched no wire token,
    /// so real org-page targets decoded as `.other`. The rename is the fix.
    public enum Kind: String, Sendable, Equatable, Hashable {
        /// The user's own LinkedIn profile.
        case personal
        /// A company page assigned to the user through an **organization's**
        /// shared credential. This is the kind that silently becomes the
        /// user's default destination (work-consolidation.md G25).
        case orgPage
        /// A company page the user administers through their *own* LinkedIn
        /// connection (requires the `rw_organization_admin` scope).
        case personalPage
        /// A token the client does not recognise.
        case other
    }

    public let kind: Kind
    public let label: String
    public let avatarURL: URL?
    public let isEnabled: Bool

    /// The record id to send in a message's `linkedInTargets` — `pageId` for
    /// an `orgPage`, `personalPageId` for a `personalPage`, `nil` for the
    /// personal profile (which needs no id).
    public let pageRecordId: String?

    /// LinkedIn's own page identifier, on either page kind.
    public let linkedInPageId: String?

    /// Identity has to include the record id: a user can be assigned two
    /// company pages that share a label, and collapsing them would drop one
    /// from any `Identifiable` list.
    public var id: String { "\(kind.rawValue):\(pageRecordId ?? label)" }

    /// Whether this target publishes to a company page rather than a personal
    /// profile — the distinction the composer has to make visible.
    public var isCompanyPage: Bool { kind == .orgPage || kind == .personalPage }

    public init(
        kind: Kind,
        label: String,
        avatarURL: URL? = nil,
        isEnabled: Bool = false,
        pageRecordId: String? = nil,
        linkedInPageId: String? = nil
    ) {
        self.kind = kind
        self.label = label
        self.avatarURL = avatarURL
        self.isEnabled = isEnabled
        self.pageRecordId = pageRecordId
        self.linkedInPageId = linkedInPageId
    }
}

extension LinkedInTarget {
    public init(from dto: LinkedInTargetDTO) {
        let kind: Kind
        switch dto.kind.lowercased() {
        case "personal": kind = .personal
        // "org" / "organization" are accepted alongside the real "orgPage"
        // token so an older or renamed server spelling still resolves.
        case "orgpage", "org", "organization": kind = .orgPage
        case "personalpage": kind = .personalPage
        default: kind = .other
        }
        self.init(
            kind: kind,
            label: dto.label,
            // Pages carry `logoUrl`; the personal profile carries `avatarUrl`.
            avatarURL: (dto.avatarUrl ?? dto.logoUrl).flatMap(URL.init(string:)),
            isEnabled: dto.enabled ?? false,
            pageRecordId: dto.pageId ?? dto.personalPageId,
            linkedInPageId: dto.linkedInPageId
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

    /// Where an ordinary LinkedIn cross-post actually lands when the user
    /// enables the toggle **without** picking a destination
    /// (work-consolidation.md G25).
    ///
    /// Per `/help/organizations`: *"For a member who has an assignment, the
    /// assigned org page also becomes their default LinkedIn destination: if
    /// they enable LinkedIn cross-posting without picking a specific
    /// destination, the post goes to the assigned page rather than their
    /// personal profile."*
    ///
    /// So the precedence is org page → personal profile → whatever else is
    /// offered. Naming the personal profile here — which is what a
    /// personal-first lookup does — would tell a member with an org assignment
    /// that they are posting to themselves while the server publishes to a
    /// company page.
    ///
    /// A page only counts as the default when it is `isEnabled`; a target the
    /// user has switched off is not where the post goes.
    public var defaultDestination: LinkedInTarget? {
        targets.first { $0.kind == .orgPage && $0.isEnabled }
            ?? targets.first { $0.kind == .personal }
            ?? targets.first
    }
}

extension LinkedInPostingTargets {
    public init(from dto: LinkedInPostingTargetsResponse) {
        self.init(
            targets: dto.targets.map(LinkedInTarget.init(from:)),
            orgScopeMissing: dto.orgScopeMissing ?? false
        )
    }
}
