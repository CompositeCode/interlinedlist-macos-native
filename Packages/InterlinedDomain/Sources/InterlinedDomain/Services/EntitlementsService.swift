import Foundation

/// A subscriber-gated capability (GitHub #40 / work-consolidation.md G37).
///
/// The published Free/Subscriber matrix (`/help/settings` and `/help/account`,
/// re-read live 2026-09-09) gates the cases below and nothing else. Free
/// features — posting, following, browsing and reading public lists and
/// documents, joining organizations, tags, reading templates, exporting data,
/// and **accepting** any share or email invite — are simply absent from this
/// enum, so the gating switch stays exhaustive by construction: every `Feature`
/// is subscriber-only.
///
/// ## The create-only rule — read this before adding a case
///
/// Subscription gates **creation**, never reading, editing, or undoing:
///
/// - *"If your subscription lapses, your existing lists, documents, and
///   organizations stay fully usable: you can still read and edit them. Only
///   creating new … is subscriber-only."*
/// - *"Adding rows to an existing list is free, even without a subscription."*
/// - Revoking a share link and removing a collaborator are free, so a
///   downgraded owner can always take access back.
///
/// The case names encode that rule deliberately — `.listCreation`, not
/// `.lists` — so no call site can gate an edit, a row insert, a revoke, or a
/// read on one of these by accident. If you find yourself reaching for a
/// `Feature` to guard a non-create path, the gate is wrong, not the name.
public enum Feature: Sendable, Equatable, Hashable, CaseIterable {

    // MARK: Composer

    /// Attaching images or video to a message.
    case mediaAttachments
    /// Scheduling a message for future publication.
    case scheduledPosts
    /// Cross-posting to Mastodon / Bluesky / LinkedIn / X.
    case crossPosting

    // MARK: Creation

    /// Creating a new list. Editing an existing list, and adding rows to it,
    /// are free.
    case listCreation
    /// Creating a new list folder.
    case listFolderCreation
    /// Creating a new document. Editing an existing document is free.
    case documentCreation
    /// Creating a new document template. Reading templates is free.
    case documentTemplateCreation
    /// Creating a new organization. Joining one is free.
    case organizationCreation

    // MARK: Sharing

    /// Sharing a list or document with a named person (adding a collaborator
    /// or changing their role). Removing a collaborator is free.
    case sharingWithPeople
    /// Inviting someone by email who does not yet have an account. Revoking an
    /// invite, and accepting one, are free.
    case emailInvites
    /// Creating a tokenized share link. Revoking one is free.
    case shareLinkCreation

    // MARK: AI

    /// The AI surface. AI is included in the subscription — there is no
    /// user-supplied API key.
    case aiFeatures

    /// The user-facing sentence explaining why this feature is unavailable.
    ///
    /// One source of truth, so `MessagesError`, `DocumentsError`, `OrgError`,
    /// and the App's upgrade prompts all say the same thing about the same
    /// feature. Phrased as the *action* the user was attempting, because that
    /// is what they just clicked.
    public var upgradeMessage: String {
        switch self {
        case .mediaAttachments:
            return "Attaching media requires an active subscription."
        case .scheduledPosts:
            return "Scheduling messages requires an active subscription."
        case .crossPosting:
            return "Cross-posting requires an active subscription."
        case .listCreation:
            return "Creating lists requires an active subscription."
        case .listFolderCreation:
            return "Creating list folders requires an active subscription."
        case .documentCreation:
            return "Creating documents requires an active subscription."
        case .documentTemplateCreation:
            return "Creating document templates requires an active subscription."
        case .organizationCreation:
            return "Creating organizations requires an active subscription."
        case .sharingWithPeople:
            return "Sharing with specific people requires an active subscription."
        case .emailInvites:
            return "Inviting people by email requires an active subscription."
        case .shareLinkCreation:
            return "Creating share links requires an active subscription."
        case .aiFeatures:
            return "AI features require an active subscription."
        }
    }
}

/// Maps the current account's `customerStatus` to feature flags so subscriber
/// gating is "one switch, not scattered ifs". Pure value type — give it a
/// `CurrentUser` and ask; no I/O, no async.
///
/// This answers exactly one of the three questions the client must ask before a
/// write ("is this tier entitled?"). Account status and email verification are
/// the other two; ``CapabilityGate`` composes all three in the documented
/// precedence order and is what UI and services should normally consult.
///
/// When the signed-in user's subscription state changes, the App layer rebuilds
/// the service from the refreshed `CurrentUser` (e.g. after a 403 triggers a
/// `customerStatus` re-fetch).
public struct EntitlementsService: Sendable, Equatable {

    /// The account these entitlements are computed for. A signed-out / unknown
    /// user is treated as `.free`.
    private let customerStatus: CustomerStatus

    /// Test-only override for ``canManageLists``. `nil` defers to the real
    /// subscriber-driven logic.
    private let listManagementOverride: Bool?

    public init(user: CurrentUser?) {
        self.customerStatus = user?.customerStatus ?? .free
        self.listManagementOverride = nil
    }

    /// Direct construction from a status, for tests and for callers that only
    /// hold the status.
    public init(customerStatus: CustomerStatus) {
        self.customerStatus = customerStatus
        self.listManagementOverride = nil
    }

    /// Construct with an explicit list-creation gate, so a test can exercise
    /// the allowed and blocked paths without standing up a whole account.
    public init(customerStatus: CustomerStatus, canManageLists: Bool) {
        self.customerStatus = customerStatus
        self.listManagementOverride = canManageLists
    }

    /// Whether the account is an active paid subscriber.
    public var isSubscriber: Bool {
        customerStatus.isSubscriber
    }

    /// Whether `feature` is available to the current account. The single switch
    /// every subscriber-gated call site routes through.
    ///
    /// Every `Feature` is subscriber-only by construction, so this is one
    /// branch today; it stays a `switch` so that adding a case with different
    /// logic is a compile-time prompt rather than a silent inheritance of
    /// `isSubscriber`.
    public func isEnabled(_ feature: Feature) -> Bool {
        switch feature {
        case .mediaAttachments, .scheduledPosts, .crossPosting,
             .listCreation, .listFolderCreation,
             .documentCreation, .documentTemplateCreation,
             .organizationCreation,
             .sharingWithPeople, .emailInvites, .shareLinkCreation,
             .aiFeatures:
            return isSubscriber
        }
    }

    /// Whether the current account may **create** a list.
    ///
    /// Despite the historical name this is a create-only gate, equivalent to
    /// `isEnabled(.listCreation)`. Reading a list, editing one, adding or
    /// editing rows, managing watchers, and managing connections are all free
    /// and must never be guarded by it — see the create-only rule on ``Feature``.
    public var canManageLists: Bool {
        listManagementOverride ?? isEnabled(.listCreation)
    }
}
