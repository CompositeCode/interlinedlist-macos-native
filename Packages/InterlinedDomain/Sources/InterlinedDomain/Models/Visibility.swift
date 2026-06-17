import Foundation

/// Whether a message is visible to everyone or only to the author / followers.
///
/// The API expresses visibility as a single `publiclyVisible: Bool` on the
/// wire (`MessageDTO`). The domain layer models it as a closed enum so view
/// code switches on a named case instead of a bare boolean, and so future
/// visibility levels can be added in one place.
public enum Visibility: Sendable, Equatable, Hashable, CaseIterable {
    /// Visible to everyone, including signed-out browsers.
    case `public`
    /// Visible only to the author (and, per account settings, followers).
    case `private`

    /// Maps the wire boolean to a visibility case.
    public init(publiclyVisible: Bool) {
        self = publiclyVisible ? .public : .private
    }

    /// The wire boolean for this visibility, for round-tripping into a
    /// `CreateMessageRequest` when composing.
    public var isPubliclyVisible: Bool {
        self == .public
    }
}
