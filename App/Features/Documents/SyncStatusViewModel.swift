// SyncStatusViewModel
//
// Drives the toolbar "Sync" status indicator + manual button for the M4
// Documents feature (PLAN.md §6 M4). Owns three concerns:
//   1. The display state — `idle`, `syncing`, `lastSynced(at:)`,
//      `failed(message:)`.
//   2. The manual `syncNow()` trigger fired from the toolbar / menu.
//   3. The last-synced-at timestamp surfaced as "2m ago".
//
// Reads through `DocumentsServicing.syncNow()` only — view does not
// touch the engine directly so tests substitute a stub.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class SyncStatusViewModel {

    /// Possible UI states for the toolbar status indicator.
    enum State: Sendable, Equatable {
        case idle
        case syncing
        case lastSynced(at: Date)
        case failed(message: String)
    }

    private let documents: DocumentsServicing
    private let clock: @Sendable () -> Date

    // MARK: - Observable state

    /// The current display state. Drives the toolbar label + colour.
    private(set) var state: State = .idle

    /// True while a manual sync is in flight. Used by the toolbar
    /// button to switch to a `ProgressView` glyph.
    var isSyncing: Bool {
        if case .syncing = state { return true }
        return false
    }

    // MARK: - Init

    /// - Parameters:
    ///   - documents: networking seam.
    ///   - clock: injected so tests can substitute a fixed clock for
    ///     "last synced N seconds ago" assertions.
    init(documents: DocumentsServicing, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.documents = documents
        self.clock = clock
    }

    // MARK: - Intents

    /// Fires one manual sync cycle. Surfaces the result through `state`
    /// — `syncing` while in flight, `lastSynced(at:)` on success,
    /// `failed(message:)` on error.
    func syncNow() async {
        state = .syncing
        do {
            let report = try await documents.syncNow()
            state = .lastSynced(at: report.lastSyncAt ?? clock())
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    /// Mirror of `syncNow()` triggered externally (e.g. by the
    /// on-launch auto-sync) — updates the status without a new round-
    /// trip. Used by the parent view to keep the indicator current
    /// with whatever the engine is doing.
    func recordExternalSyncSuccess(at date: Date) {
        state = .lastSynced(at: date)
    }
}
