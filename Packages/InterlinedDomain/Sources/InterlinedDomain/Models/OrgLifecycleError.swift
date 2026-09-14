import Foundation

// MARK: - OrgLifecycleError

/// Client-side preconditions on the destructive organization verbs
/// (work-consolidation.md G25).
///
/// These are the rules `/help/organizations` states, enforced **before** the
/// network call so the user gets an immediate, specific sentence instead of a
/// generic server rejection:
///
/// - *"You cannot leave the system 'The Public' organization."*
/// - *"The last remaining owner cannot be demoted or removed"* — and cannot
///   leave until another owner is in place.
/// - Deleting an organization is owner-only.
///
/// The server enforces all of this too; the client check is about the message,
/// not about trusting the client. Where a rule needs data the client may not
/// have (an owner count from a partially-loaded roster), the check deliberately
/// **passes** and lets the server be the backstop — a precondition that guesses
/// would block legitimate actions, which is the worse failure.
public enum OrgLifecycleError: LocalizedError, Equatable {

    /// Tried to leave "The Public" (or any `isSystem` org).
    case cannotLeaveSystemOrganization(name: String)

    /// Tried to leave while the only remaining owner.
    case lastOwnerCannotLeave

    /// Tried to demote or remove the only remaining owner.
    case lastOwnerCannotBeDemoted

    /// Tried to suspend the only remaining owner.
    case lastOwnerCannotBeSuspended

    /// Tried to delete an org the caller does not own.
    case onlyOwnerCanDelete

    /// Tried to act without knowing who the signed-in user is.
    case unknownCurrentUser

    /// Tried to manage the org's LinkedIn credential without owner/admin.
    case linkedInRequiresOwnerOrAdmin

    public var errorDescription: String? {
        switch self {
        case .cannotLeaveSystemOrganization(let name):
            return "\(name) is a system organization that everyone belongs to — you can't leave it."
        case .lastOwnerCannotLeave:
            return "You're the last owner. Make someone else an owner before you leave."
        case .lastOwnerCannotBeDemoted:
            return "This is the last owner. Promote another member to owner first."
        case .lastOwnerCannotBeSuspended:
            return "This is the last owner. Promote another member to owner before suspending them."
        case .onlyOwnerCanDelete:
            return "Only an owner can delete this organization."
        case .unknownCurrentUser:
            return "Sign in again — the app couldn't tell which account you're using."
        case .linkedInRequiresOwnerOrAdmin:
            return "Only owners and admins can manage the organization's LinkedIn connection."
        }
    }
}

// MARK: - OrgOwnershipRules

/// The pure, testable predicates behind `OrgLifecycleError`.
///
/// Kept free of any service or networking dependency so the rules can be
/// unit-tested directly and reused by both the service seam and the UI's
/// enable/disable state — the UI must not re-derive them by hand.
public enum OrgOwnershipRules {

    /// Owners among a roster. A suspended owner still counts: they hold the
    /// role, so demoting the only *other* owner would still strand the org.
    public static func ownerCount(in members: [OrgMember]) -> Int {
        members.filter { $0.role == .owner }.count
    }

    /// Whether `userId` is the only owner in `members`.
    ///
    /// Answers `false` when the roster contains no owner at all — that means
    /// the roster is partial (or the caller isn't in it), and a precondition
    /// must not block on data it does not have.
    public static func isLastOwner(userId: String, in members: [OrgMember]) -> Bool {
        let owners = members.filter { $0.role == .owner }
        guard owners.count == 1 else { return false }
        return owners[0].userId == userId
    }

    /// Validates a leave. `members` may be empty when the roster has not been
    /// loaded; the last-owner half is then skipped and the server decides.
    public static func validateLeave(
        organization: Organization,
        userId: String,
        members: [OrgMember]
    ) -> OrgLifecycleError? {
        if organization.isSystem {
            return .cannotLeaveSystemOrganization(name: organization.name)
        }
        if isLastOwner(userId: userId, in: members) {
            return .lastOwnerCannotLeave
        }
        return nil
    }

    /// Validates a role change on `member`. Demoting the last owner is the
    /// only rejected transition; promoting anyone is always allowed.
    public static func validateRoleChange(
        member: OrgMember,
        to newRole: OrgRole,
        members: [OrgMember]
    ) -> OrgLifecycleError? {
        guard member.role == .owner, newRole != .owner else { return nil }
        return isLastOwner(userId: member.userId, in: members) ? .lastOwnerCannotBeDemoted : nil
    }

    /// Validates a removal. The last owner cannot be removed.
    public static func validateRemoval(
        member: OrgMember,
        members: [OrgMember]
    ) -> OrgLifecycleError? {
        isLastOwner(userId: member.userId, in: members) ? .lastOwnerCannotBeDemoted : nil
    }

    /// Validates a suspension. Suspending the last owner would leave the org
    /// with no usable owner, so it is refused for the same reason as demotion.
    /// Un-suspending is always allowed.
    public static func validateSuspension(
        member: OrgMember,
        suspended: Bool,
        members: [OrgMember]
    ) -> OrgLifecycleError? {
        guard suspended else { return nil }
        return isLastOwner(userId: member.userId, in: members) ? .lastOwnerCannotBeSuspended : nil
    }

    /// Validates a delete. Owner-only, per `/help/organizations`.
    public static func validateDelete(callerRole: OrgRole?) -> OrgLifecycleError? {
        callerRole == .owner ? nil : .onlyOwnerCanDelete
    }
}
