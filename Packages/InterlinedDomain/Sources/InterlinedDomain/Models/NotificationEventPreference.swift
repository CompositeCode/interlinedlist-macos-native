import Foundation
import InterlinedKit

/// The delivery channels for one notification event (work-consolidation.md G18).
///
/// A channel the server does not mention is `nil` rather than `false`, so the
/// pane can render only the channels this event actually supports instead of
/// showing a dead "Email" switch for an event that has no email delivery.
public struct NotificationChannels: Sendable, Equatable {
    public var push: Bool?
    public var inApp: Bool?
    public var email: Bool?

    public init(push: Bool? = nil, inApp: Bool? = nil, email: Bool? = nil) {
        self.push = push
        self.inApp = inApp
        self.email = email
    }
}

/// One row of the server-driven notification-preferences catalogue.
///
/// Labels and descriptions come from the server, so a new event type appears in
/// the pane without a client release — that is the whole point of G18's
/// data-driven design.
public struct NotificationEventPreference: Sendable, Equatable, Identifiable {
    /// Stable event key, e.g. `dig`. Also the identity.
    public let key: String
    /// Display label. Falls back to the key so an unlabelled event still
    /// renders something recognisable rather than an empty row.
    public let label: String
    public let description: String?
    public var channels: NotificationChannels

    public var id: String { key }

    public init(
        key: String,
        label: String,
        description: String? = nil,
        channels: NotificationChannels = NotificationChannels()
    ) {
        self.key = key
        self.label = label
        self.description = description
        self.channels = channels
    }
}

extension NotificationChannels {
    public init(from dto: NotificationChannelsDTO) {
        self.init(push: dto.push, inApp: dto.inApp, email: dto.email)
    }

    /// The write projection — `PATCH` carries only the channels.
    var dto: NotificationChannelsDTO {
        NotificationChannelsDTO(push: push, inApp: inApp, email: email)
    }
}

extension NotificationEventPreference {
    public init(from dto: NotificationEventDTO) {
        self.init(
            key: dto.key,
            label: dto.label ?? dto.key,
            description: dto.description,
            channels: dto.channels.map(NotificationChannels.init(from:)) ?? NotificationChannels()
        )
    }
}
