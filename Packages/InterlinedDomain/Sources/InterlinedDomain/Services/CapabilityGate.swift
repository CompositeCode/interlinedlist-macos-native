import Foundation

// MARK: - GatedAction

/// Something the account might not be allowed to do right now (GitHub #40, #41,
/// #42).
///
/// This is the single currency the UI and the domain services ask about, so a
/// call site poses **one** question — "may I do this, and if not why?" — instead
/// of separately interrogating account status, email verification, and
/// subscription tier and then trying to reconcile three answers.
///
/// Ask it through ``CapabilityGate``.
public enum GatedAction: Sendable, Equatable, Hashable, CaseIterable {

    // MARK: Posting and social

    /// Publishing a message.
    case postMessage
    /// Replying to a message. A reply is a message, so it carries the same
    /// verification requirement as ``postMessage``.
    case replyToMessage
    /// Digging / pushing a message.
    case reactToMessage
    /// Following another account.
    case followUser

    // MARK: Direct messages

    /// Sending a direct message.
    case directMessages
    /// Attaching a photo to a direct message.
    case directMessageImages

    // MARK: Composer extras

    /// Attaching images or video to a message.
    case mediaAttachments
    /// Cross-posting to Mastodon / Bluesky / LinkedIn / X.
    case crossPosting
    /// Scheduling a message for later.
    case scheduledPosts

    // MARK: Creation

    case listCreation
    case documentCreation
    case documentTemplateCreation
    case organizationCreation

    // MARK: Sharing

    case sharingWithPeople
    case emailInvites
    case shareLinkCreation

    // MARK: AI

    case aiFeatures

    /// The subscriber dimension of this action, if it has one. `nil` means the
    /// action is free on every tier (posting, replying, reacting, following,
    /// and sending a plain DM all are).
    public var requiredFeature: Feature? {
        switch self {
        case .postMessage, .replyToMessage, .reactToMessage, .followUser,
             .directMessages, .directMessageImages:
            return nil
        case .mediaAttachments: return .mediaAttachments
        case .crossPosting: return .crossPosting
        case .scheduledPosts: return .scheduledPosts
        case .listCreation: return .listCreation
        case .documentCreation: return .documentCreation
        case .documentTemplateCreation: return .documentTemplateCreation
        case .organizationCreation: return .organizationCreation
        case .sharingWithPeople: return .sharingWithPeople
        case .emailInvites: return .emailInvites
        case .shareLinkCreation: return .shareLinkCreation
        case .aiFeatures: return .aiFeatures
        }
    }

    /// Whether a read-only account (`.restricted` / `.suspended`) is blocked
    /// from this action.
    ///
    /// `/help/account`: a read-only account *"can't post, reply, react, follow,
    /// send messages, or create content"*. Sharing an item that already exists,
    /// and using AI, are not in that list, so they stay available — the gate
    /// blocks exactly what the documentation blocks and no more.
    public var isBlockedWhileReadOnly: Bool {
        switch self {
        case .postMessage, .replyToMessage, .reactToMessage, .followUser,
             .directMessages, .directMessageImages,
             .mediaAttachments, .crossPosting, .scheduledPosts,
             .listCreation,
             .documentCreation, .documentTemplateCreation,
             .organizationCreation:
            return true
        case .sharingWithPeople, .emailInvites, .shareLinkCreation, .aiFeatures:
            return false
        }
    }

    /// Whether a `.new` account on probation is locked out of this action.
    ///
    /// `/help/account` names the locked set exactly: *"direct messages, image
    /// and video uploads, cross-posting, scheduled posts, and creating lists,
    /// documents, and organizations"*. Plain posting is deliberately **not** in
    /// it — it is rate-limited, not blocked, and the client must not disable it.
    ///
    /// List *folders* and document *templates* are read as sub-kinds of
    /// "creating lists" and "creating documents"; the help text does not call
    /// them out separately.
    public var isLockedOnProbation: Bool {
        switch self {
        case .directMessages, .directMessageImages,
             .mediaAttachments, .crossPosting, .scheduledPosts,
             .listCreation,
             .documentCreation, .documentTemplateCreation,
             .organizationCreation:
            return true
        case .postMessage, .replyToMessage, .reactToMessage, .followUser,
             .sharingWithPeople, .emailInvites, .shareLinkCreation, .aiFeatures:
            return false
        }
    }

    /// Whether this action requires a verified email address.
    ///
    /// `/help/settings`: *"You must verify your email before posting messages or
    /// attaching media."* `/help/direct-messages`: *"You'll need a verified
    /// email address to send images."* Sending a text-only DM is not listed.
    public var requiresVerifiedEmail: Bool {
        switch self {
        case .postMessage, .replyToMessage, .mediaAttachments, .directMessageImages:
            return true
        case .reactToMessage, .followUser, .directMessages,
             .crossPosting, .scheduledPosts,
             .listCreation,
             .documentCreation, .documentTemplateCreation,
             .organizationCreation,
             .sharingWithPeople, .emailInvites, .shareLinkCreation, .aiFeatures:
            return false
        }
    }
}

// MARK: - CapabilityDenial

/// Why an action is unavailable, in the precedence order the gate applies.
///
/// The order matters: an account can fail more than one check at once, and the
/// UI must show the reason the user can actually act on. A `.restricted`
/// subscriber is told they are under review, not that they need to upgrade.
public enum CapabilityDenial: Sendable, Equatable, Hashable {

    /// The account is closed. Reachable only in theory — a banned account
    /// cannot sign in — but modelled so the switch is total.
    case accountBanned

    /// The account is temporarily read-only. Carries the status so the UI can
    /// distinguish "under review" (`.restricted`) from "actioned by the team"
    /// (`.suspended`); both are appealable via support.
    case accountReadOnly(AccountStatus)

    /// The account is new and this action is locked until it is reviewed or the
    /// email is verified.
    case newAccountLocked

    /// The account's email address is not verified yet.
    case emailUnverified

    /// The action needs an active subscription. Carries the feature so the
    /// upgrade prompt can name it.
    case subscriberRequired(Feature)
}

/// What the user can actually do about a denial.
///
/// The gate names the remedy; the App layer decides how to present it (a
/// deep link, a sheet, a disabled control with a tooltip). Keeping the choice
/// here means the banner, the composer, and Settings cannot drift into offering
/// three different next steps for the same underlying block.
public enum CapabilityRemedy: Sendable, Equatable, Hashable {
    /// Verify the email address. Also the documented fastest way off `.new`.
    case verifyEmail
    /// Appeal to support — the documented path for `.restricted` / `.suspended`.
    case contactSupport
    /// Subscribe, to unlock a named feature.
    case upgrade(Feature)
    /// Nothing the user can do (a banned account, or simply waiting out
    /// probation review).
    ///
    /// Deliberately *not* spelled `none`: an enum case by that name collides
    /// with `Optional.none` at every `CapabilityRemedy?` switch site.
    case noneAvailable
}

extension CapabilityDenial {

    /// The sentence shown to the user. Explains *why*, in the platform's own
    /// vocabulary, without blaming them.
    public var message: String {
        switch self {
        case .accountBanned:
            return "This account is closed."
        case .accountReadOnly(.suspended):
            return "Your account is suspended and is read-only while it is reviewed. "
                + "You can still read and browse, and you can appeal."
        case .accountReadOnly:
            return "Your account is temporarily read-only while it is reviewed. "
                + "You can still read and browse, and you can appeal."
        case .newAccountLocked:
            return "This is locked while your account is new. "
                + "Verifying your email is the fastest way to unlock it."
        case .emailUnverified:
            return "Verify your email address before posting or attaching media."
        case .subscriberRequired(let feature):
            return feature.upgradeMessage
        }
    }

    /// The next step to offer alongside ``message``.
    public var remedy: CapabilityRemedy {
        switch self {
        case .accountBanned: return .noneAvailable
        case .accountReadOnly: return .contactSupport
        case .newAccountLocked: return .verifyEmail
        case .emailUnverified: return .verifyEmail
        case .subscriberRequired(let feature): return .upgrade(feature)
        }
    }
}

// MARK: - CapabilityDecision

/// The gate's answer: allowed, or denied with a single actionable reason.
public enum CapabilityDecision: Sendable, Equatable, Hashable {
    case allowed
    case denied(CapabilityDenial)

    public var isAllowed: Bool { self == .allowed }

    /// The reason, or `nil` when allowed.
    public var denial: CapabilityDenial? {
        guard case .denied(let reason) = self else { return nil }
        return reason
    }
}

// MARK: - CapabilityGate

/// The one place that answers "may this account do X right now, and if not
/// why?" (GitHub #40 / #41 / #42).
///
/// Three independent mechanisms can each say no:
///
/// 1. **Account status** — `/help/account`. The hardest gate: a paying
///    subscriber who is `.restricted` still cannot post.
/// 2. **Email verification** — `/help/settings`. Independent of both others.
/// 3. **Subscription tier** — `/help/settings`. The softest, and the only one
///    the user can fix by paying.
///
/// Evaluating them in that order is what makes the message actionable. A new,
/// unverified, free account that tries to attach media fails all three; telling
/// it to *upgrade* would be useless advice, because verifying the email is both
/// the cheaper fix and the documented way off `.new`.
///
/// Pure value type — no I/O, no async. Rebuild it whenever `CurrentUser`
/// changes.
public struct CapabilityGate: Sendable, Equatable {

    public let accountStatus: AccountStatus
    public let entitlements: EntitlementsService
    public let isEmailVerified: Bool

    /// Builds the gate from the signed-in account.
    ///
    /// A `nil` user is signed-out: `.free`, unverified, but `.active` in status
    /// so the gate never invents a restriction for someone it knows nothing
    /// about.
    public init(user: CurrentUser?) {
        self.accountStatus = user?.accountStatus ?? .active
        self.entitlements = EntitlementsService(user: user)
        self.isEmailVerified = user?.isEmailVerified ?? false
    }

    /// Direct construction, for tests and for composition-root wiring that
    /// holds the three inputs separately.
    public init(
        accountStatus: AccountStatus,
        entitlements: EntitlementsService,
        isEmailVerified: Bool
    ) {
        self.accountStatus = accountStatus
        self.entitlements = entitlements
        self.isEmailVerified = isEmailVerified
    }

    /// Evaluates `action` against all three gates, hardest first.
    public func evaluate(_ action: GatedAction) -> CapabilityDecision {
        // 1. Account status — the hardest gate. `.unknown` fails open here
        //    because `AccountStatus` reports it as neither restricted nor on
        //    probation, so an unrecognised server value disables nothing.
        if accountStatus == .banned {
            return .denied(.accountBanned)
        }
        if accountStatus.isWriteRestricted, action.isBlockedWhileReadOnly {
            return .denied(.accountReadOnly(accountStatus))
        }
        if accountStatus.isOnProbation, action.isLockedOnProbation {
            return .denied(.newAccountLocked)
        }

        // 2. Email verification — independent of tier, and the fix that also
        //    moves a `.new` account off probation fastest.
        if action.requiresVerifiedEmail, !isEmailVerified {
            return .denied(.emailUnverified)
        }

        // 3. Subscription tier — the softest gate, and the only one an upgrade
        //    prompt can resolve.
        if let feature = action.requiredFeature, !entitlements.isEnabled(feature) {
            return .denied(.subscriberRequired(feature))
        }

        return .allowed
    }

    /// Convenience boolean for call sites that only need yes/no.
    public func allows(_ action: GatedAction) -> Bool {
        evaluate(action).isAllowed
    }

    /// The reason `action` is unavailable, or `nil` when it is available.
    public func denial(for action: GatedAction) -> CapabilityDenial? {
        evaluate(action).denial
    }
}
