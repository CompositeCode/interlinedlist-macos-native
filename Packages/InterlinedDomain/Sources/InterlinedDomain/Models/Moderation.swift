import Foundation

// MARK: - ModeratedUser

/// A user the current account has blocked or muted (work-consolidation.md G2). The App
/// layer renders these in the Settings "Blocked & Muted" pane and uses the
/// membership to filter timelines / threads / DM eligibility.
public struct ModeratedUser: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let username: String?
    public let displayName: String?
    public let avatarURL: URL?

    public init(id: String, username: String? = nil, displayName: String? = nil, avatarURL: URL? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
    }

    /// `@handle` when a username is present, otherwise the id.
    public var handle: String { username.map { "@\($0)" } ?? id }

    /// Best available display name.
    public var name: String { displayName ?? username ?? id }
}

// MARK: - ReportReason

/// The reason attached to a user or message report. Values match the live API
/// contract (`harassment|spam|misinformation|inappropriate|other`). The domain
/// layer owns this enum so the App picks from a typed, exhaustive list and the
/// kit only ever sees the validated `rawValue`.
public enum ReportReason: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case harassment
    case spam
    case misinformation
    case inappropriate
    case other

    public var id: String { rawValue }

    /// Human-facing label for the report reason picker.
    public var label: String {
        switch self {
        case .harassment: return "Harassment"
        case .spam: return "Spam"
        case .misinformation: return "Misinformation"
        case .inappropriate: return "Inappropriate content"
        case .other: return "Other"
        }
    }
}
