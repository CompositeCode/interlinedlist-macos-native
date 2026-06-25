import Foundation
import InterlinedDomain

/// Internal mapping between the SwiftData `LinkedIdentityRecord` and the
/// domain `LinkedIdentity` value type. Mirrors the `NotificationRecordMapping`
/// pattern — `@Model` instances stay inside the actor; only `Sendable` value
/// types cross the boundary.
///
/// `IdentityProvider` is persisted as its `wireToken` and rehydrated via
/// `IdentityProvider(wireToken:)`; URLs round-trip through their absolute
/// strings (a malformed stored string simply decodes back to `nil`, the same
/// lenient handling `NotificationRecordMapping` uses for avatar URLs).

extension LinkedIdentityRecord {

    /// Build a new record from a domain `LinkedIdentity`.
    convenience init(from identity: LinkedIdentity) {
        self.init(
            id: identity.id,
            providerRaw: identity.provider.wireToken,
            handle: identity.handle,
            profileURLString: identity.profileURL?.absoluteString,
            avatarURLString: identity.avatarURL?.absoluteString,
            connectedAt: identity.connectedAt,
            lastVerifiedAt: identity.lastVerifiedAt
        )
    }

    /// Hydrate the row into a domain `LinkedIdentity` value.
    func toLinkedIdentity() -> LinkedIdentity {
        LinkedIdentity(
            id: id,
            provider: IdentityProvider(wireToken: providerRaw),
            handle: handle,
            profileURL: profileURLString.flatMap(URL.init(string:)),
            avatarURL: avatarURLString.flatMap(URL.init(string:)),
            connectedAt: connectedAt,
            lastVerifiedAt: lastVerifiedAt
        )
    }
}
