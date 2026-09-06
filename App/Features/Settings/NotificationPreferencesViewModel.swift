// NotificationPreferencesViewModel
//
// Drives Settings ▸ Notifications (work-consolidation.md G18). The catalogue is
// server-driven — labels, descriptions and which channels exist all come from
// the payload — so this view model holds an opaque list of events and never
// hard-codes an event type.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class NotificationPreferencesViewModel {

    private let service: NotificationPreferencesServicing?

    /// The working copy bound to the pane's switches.
    var events: [NotificationEventPreference] = []
    /// The last catalogue the server confirmed, for change detection.
    private(set) var lastSaved: [NotificationEventPreference] = []

    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var error: Error?

    var isUnavailable: Bool { service == nil }
    var hasChanges: Bool { events != lastSaved }

    init(service: NotificationPreferencesServicing?) {
        self.service = service
    }

    func load() async {
        guard let service else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let loaded = try await service.catalogue()
            events = loaded
            lastSaved = loaded
        } catch {
            self.error = error
        }
    }

    func save() async {
        guard let service, hasChanges, !isSaving else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            // Send only what changed — an untouched event has no reason to be
            // rewritten, and a narrower PATCH is less likely to clobber a change
            // made on another device between this load and save.
            let changed = events.filter { event in
                lastSaved.first { $0.key == event.key }?.channels != event.channels
            }
            let updated = try await service.update(changed)
            events = updated
            lastSaved = updated
        } catch {
            self.error = error
        }
    }

    /// Binding helper for one event's channel toggle. Returns nil when the
    /// server did not offer that channel for the event, so the view can omit
    /// the switch rather than render a dead one.
    func channelValue(_ key: String, _ channel: NotificationChannel) -> Bool? {
        guard let event = events.first(where: { $0.key == key }) else { return nil }
        switch channel {
        case .push:  return event.channels.push
        case .inApp: return event.channels.inApp
        case .email: return event.channels.email
        }
    }

    func setChannel(_ key: String, _ channel: NotificationChannel, to value: Bool) {
        guard let index = events.firstIndex(where: { $0.key == key }) else { return }
        switch channel {
        case .push:  events[index].channels.push = value
        case .inApp: events[index].channels.inApp = value
        case .email: events[index].channels.email = value
        }
    }
}

/// The delivery channels the pane can render. App-layer only — the domain model
/// carries the values, this just names them for the view's iteration.
enum NotificationChannel: String, CaseIterable, Identifiable {
    case push
    case inApp
    case email

    var id: String { rawValue }

    var title: String {
        switch self {
        case .push:  return "Push"
        case .inApp: return "In app"
        case .email: return "Email"
        }
    }
}
