// SavedViewsViewModel
//
// Drives the saved-views control on the owned/shared list rows surface
// (work-consolidation.md G40 / issue #81). Owns the loaded views, which one is
// applied, and the create / rename / delete / fork / make-default writes.
//
// Reads through `ListsServicing` only — per decision 0003 this file consumes
// `InterlinedDomain` and never `InterlinedKit`.
//
// **What "applying a view" can actually do today.** The server normalises
// `config` down to four keys and stores exactly one `mode` (`records`), so the
// only stored value with a visible client effect is `density`. That is what
// `appliedDensity` projects. `filters` and `search` are carried through every
// write untouched rather than dropped, because the web may have written values
// this client cannot yet interpret — see `SavedListViewConfig.filters` for why
// their grammar is unconfirmed. Inventing UI for them would be inventing a
// contract.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class SavedViewsViewModel {

    private let lists: ListsServicing
    private let eventBus: ListsEventBus
    let listId: String

    // MARK: - Observable state

    /// Every view on this list, in the server's order: the list's shared views
    /// plus the caller's personal ones. Never re-sorted — `position` repeats
    /// across scope buckets, so sorting on it would interleave the two sets.
    private(set) var views: [SavedListView] = []

    /// The applied view's id, or `nil` for the list's plain unsaved
    /// arrangement. Seeded from `isDefault` on the first load.
    private(set) var selectedViewID: String?

    private(set) var isLoading: Bool = false

    /// The most recent failure. Cleared at the start of the next write.
    private(set) var error: Error?

    /// In-flight write set keyed by view id, so a double-click on Delete or a
    /// rapid default flip cannot fire the same write twice.
    private(set) var pendingOperations: Set<String> = []

    /// Set when a write was rejected for a reason the user can fix — today only
    /// a blank name. Held separately from `error` so the sheet can render it on
    /// the offending field rather than as a banner.
    private(set) var validationMessage: String?

    // MARK: - Derived

    var selectedView: SavedListView? {
        guard let selectedViewID else { return nil }
        return views.first { $0.id == selectedViewID }
    }

    /// The list's own views — visible to everyone with access.
    var sharedViews: [SavedListView] { views.filter(\.isShared) }

    /// The caller's private views.
    var personalViews: [SavedListView] { views.filter { !$0.isShared } }

    /// The density the rows pane should render at. Falls back to the server's
    /// own create default when no view is applied, so an unsaved list and a
    /// freshly-created view look identical rather than subtly different.
    var appliedDensity: SavedListViewDensity {
        selectedView?.config.density ?? SavedListViewConfig.serverDefault.density
    }

    /// The config a *new* view should start from: whatever is applied now, so
    /// "Save current arrangement" means what it says.
    var currentConfig: SavedListViewConfig {
        selectedView?.config ?? .serverDefault
    }

    // MARK: - Init

    init(lists: ListsServicing, eventBus: ListsEventBus, listId: String) {
        self.lists = lists
        self.eventBus = eventBus
        self.listId = listId
    }

    // MARK: - Loading

    /// Loads the list's views and applies the caller's default, if they set one.
    ///
    /// `isDefault` is **per user**, so on a shared list two people legitimately
    /// open the same list into different arrangements — honouring it here is
    /// the point of the flag, not a nicety.
    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let loaded = try await lists.savedViews(of: listId)
            views = loaded
            selectedViewID = loaded.first(where: \.isDefault)?.id
        } catch {
            self.error = error
        }
    }

    // MARK: - Selection

    /// Applies a view, or `nil` for the list's plain arrangement. Local only —
    /// picking a view is not a write, so it costs no round-trip and works
    /// offline over whatever is already loaded.
    func select(viewID: String?) {
        guard viewID == nil || views.contains(where: { $0.id == viewID }) else { return }
        selectedViewID = viewID
    }

    // MARK: - Writes

    /// Creates a view capturing the current arrangement.
    ///
    /// Blank names are refused here as well as in the service: the sheet's
    /// Save button is disabled for one, so reaching this guard means a keyboard
    /// path got through, and a silent no-op would look like a hung sheet.
    func create(name: String, scope: SavedListViewScope, makeDefault: Bool) async {
        guard prepareWrite(named: name) else { return }
        do {
            let created = try await lists.createSavedView(
                listId: listId,
                name: name,
                scope: scope,
                config: currentConfig,
                isDefault: makeDefault
            )
            // A new default demotes the old one server-side, so rebuild the
            // flags locally rather than only appending.
            views = applyingDefault(created.isDefault ? created.id : nil, to: views + [created])
            selectedViewID = created.id
            publish()
        } catch {
            surface(error)
        }
    }

    /// Renames a view. Optimistic: the picker label swaps immediately and is
    /// restored if the write fails, because a rename that appears to do nothing
    /// for a second reads as a broken control.
    func rename(viewID: String, to name: String) async {
        guard prepareWrite(named: name),
              !pendingOperations.contains(viewID),
              let index = views.firstIndex(where: { $0.id == viewID }) else { return }
        let snapshot = views
        let original = views[index]
        views[index] = original.renamed(to: name.trimmingCharacters(in: .whitespacesAndNewlines))
        pendingOperations.insert(viewID)
        defer { pendingOperations.remove(viewID) }
        do {
            // Name only — a partial `config` would REPLACE the stored one and
            // silently reset whatever it omitted, so a rename must never carry
            // one.
            let confirmed = try await lists.updateSavedView(
                listId: listId,
                viewId: viewID,
                name: name,
                config: nil,
                isDefault: nil
            )
            if let currentIndex = views.firstIndex(where: { $0.id == viewID }) {
                views[currentIndex] = confirmed
            }
            publish()
        } catch {
            views = snapshot
            surface(error)
        }
    }

    /// Marks a view as the caller's default for this list, clearing the
    /// previous one locally — the server allows only one.
    func makeDefault(viewID: String) async {
        guard !pendingOperations.contains(viewID),
              views.contains(where: { $0.id == viewID }) else { return }
        let snapshot = views
        error = nil
        validationMessage = nil
        views = applyingDefault(viewID, to: views)
        pendingOperations.insert(viewID)
        defer { pendingOperations.remove(viewID) }
        do {
            let confirmed = try await lists.updateSavedView(
                listId: listId,
                viewId: viewID,
                name: nil,
                config: nil,
                isDefault: true
            )
            if let currentIndex = views.firstIndex(where: { $0.id == viewID }) {
                views[currentIndex] = confirmed
            }
            publish()
        } catch {
            views = snapshot
            surface(error)
        }
    }

    /// Changes the applied view's density and saves it.
    ///
    /// Sends the **complete** config, not just the changed key: `PUT` replaces
    /// the config object whole, so omitting `filters` or `search` here would
    /// wipe values the web may have set. No-op with nothing applied — there is
    /// no view to store the change in.
    func setDensity(_ density: SavedListViewDensity) async {
        guard let view = selectedView, !pendingOperations.contains(view.id) else { return }
        var config = view.config
        guard config.density != density else { return }
        config.density = density
        error = nil
        validationMessage = nil
        let snapshot = views
        pendingOperations.insert(view.id)
        defer { pendingOperations.remove(view.id) }
        do {
            let confirmed = try await lists.updateSavedView(
                listId: listId,
                viewId: view.id,
                name: nil,
                config: config,
                isDefault: nil
            )
            // Take the server's row: an unknown density silently falls back, so
            // the stored arrangement and the requested one can differ.
            if let index = views.firstIndex(where: { $0.id == view.id }) {
                views[index] = confirmed
            }
            publish()
        } catch {
            views = snapshot
            surface(error)
        }
    }

    /// Deletes a view. Optimistic remove with snapshot rollback.
    func delete(viewID: String) async {
        guard !pendingOperations.contains(viewID),
              views.contains(where: { $0.id == viewID }) else { return }
        let snapshot = views
        let previousSelection = selectedViewID
        error = nil
        validationMessage = nil
        views.removeAll { $0.id == viewID }
        if selectedViewID == viewID { selectedViewID = nil }
        pendingOperations.insert(viewID)
        defer { pendingOperations.remove(viewID) }
        do {
            try await lists.deleteSavedView(listId: listId, viewId: viewID)
            publish()
        } catch {
            views = snapshot
            selectedViewID = previousSelection
            surface(error)
        }
    }

    /// Forks a view into a personal copy owned by the caller, and applies it.
    ///
    /// The escape hatch: a collaborator who wants the owner's shared view but
    /// their own tweaks takes a copy instead of editing the list's. A `nil`
    /// name lets the server pick one.
    func fork(viewID: String, name: String?) async {
        guard !pendingOperations.contains(viewID),
              views.contains(where: { $0.id == viewID }) else { return }
        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationMessage = ListsError.invalidViewName.localizedDescription
            return
        }
        error = nil
        validationMessage = nil
        pendingOperations.insert(viewID)
        defer { pendingOperations.remove(viewID) }
        do {
            let forked = try await lists.forkSavedView(listId: listId, viewId: viewID, name: name)
            views.append(forked)
            selectedViewID = forked.id
            publish()
        } catch {
            surface(error)
        }
    }

    // MARK: - Event-bus consumption

    /// Applies a `ListsEvent`. Pure local mutation — no refetch.
    func apply(event: ListsEvent) {
        switch event {
        case .savedViewsChanged(let id, let updated) where id == listId:
            views = updated
            // Keep the applied view if it survived; otherwise fall back to
            // whatever is now the default, then to the plain arrangement.
            if let selectedViewID, updated.contains(where: { $0.id == selectedViewID }) { return }
            selectedViewID = updated.first(where: \.isDefault)?.id
        case .listDeleted(let id) where id == listId:
            views = []
            selectedViewID = nil
        default:
            break
        }
    }

    // MARK: - Internals

    /// Clears the previous error state and rejects a blank name before any
    /// round-trip. Returns `false` when the caller should stop.
    private func prepareWrite(named name: String) -> Bool {
        error = nil
        validationMessage = nil
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = ListsError.invalidViewName.localizedDescription
            return false
        }
        return true
    }

    /// Rebuilds the collection so exactly `viewID` carries `isDefault`.
    private func applyingDefault(_ viewID: String?, to collection: [SavedListView]) -> [SavedListView] {
        collection.map { $0.settingDefault($0.id == viewID) }
    }

    private func publish() {
        eventBus.post(.savedViewsChanged(listId: listId, views: views))
    }

    /// Routes a failure onto the right surface: a domain validation error the
    /// user can fix goes to the field, anything else to the error banner.
    private func surface(_ error: Error) {
        if let listsError = error as? ListsError, listsError == .invalidViewName {
            validationMessage = listsError.localizedDescription
        } else {
            self.error = error
        }
    }
}

// MARK: - Local edits

private extension SavedListView {
    /// A copy with a new name, for the optimistic rename. `SavedListView` is
    /// immutable by design (every field comes from the server), so local edits
    /// are explicit copies rather than in-place mutation.
    func renamed(to newName: String) -> SavedListView {
        SavedListView(
            id: id,
            listID: listID,
            ownerID: ownerID,
            name: newName,
            scope: scope,
            config: config,
            isDefault: isDefault,
            position: position
        )
    }

    /// A copy with `isDefault` set, for keeping the single-default rule true
    /// locally while the write is in flight.
    func settingDefault(_ value: Bool) -> SavedListView {
        SavedListView(
            id: id,
            listID: listID,
            ownerID: ownerID,
            name: name,
            scope: scope,
            config: config,
            isDefault: value,
            position: position
        )
    }
}
