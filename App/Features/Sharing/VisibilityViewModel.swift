// VisibilityViewModel
//
// Drives `VisibilityView` — the "Make Public" section of the web sharing
// dialog (work-consolidation.md G3) for a list or a document. Off means only
// invited people can access the resource; on lets anyone with the link view
// it. There is no dedicated visibility endpoint — public is a field on the
// resource — so this toggles through the existing `DocumentsServicing` /
// `ListsServicing` partial-update methods (`isPublic:` only; every other field
// is `nil`, so the update is scoped to visibility).
//
// Target dispatch: a `ShareTarget` selects which service to call. Injecting
// both services keeps the view layer target-agnostic and the view model
// testable against the project's existing document/list stubs.
//
// Optimistic toggle: flip `isPublic` immediately, call the service, adopt the
// server's returned value on success, and restore the prior value on failure.
// A single in-flight guard collapses a rapid double-tap.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class VisibilityViewModel {

    // MARK: - Dependencies

    private let documents: DocumentsServicing
    private let lists: ListsServicing
    let target: ShareTarget

    // MARK: - Observable state

    /// Whether the resource is currently public. Bound to the toggle.
    private(set) var isPublic: Bool

    /// True while an update round-trip is in flight (disables the toggle).
    private(set) var isUpdating: Bool = false

    /// Surfaced error from the most recent failed update.
    private(set) var error: Error?

    // MARK: - Init

    init(target: ShareTarget, documents: DocumentsServicing, lists: ListsServicing, isPublic: Bool) {
        self.target = target
        self.documents = documents
        self.lists = lists
        self.isPublic = isPublic
    }

    // MARK: - Intents

    /// Sets the resource's public flag. Optimistic: flip immediately, call the
    /// matching partial-update, adopt the server's returned value on success,
    /// restore the prior value on failure. A no-op when the value is unchanged
    /// or an update is already in flight.
    func setPublic(_ newValue: Bool) async {
        guard !isUpdating else { return }
        guard newValue != isPublic else { return }
        let previous = isPublic
        isUpdating = true
        isPublic = newValue
        defer { isUpdating = false }
        do {
            isPublic = try await update(isPublic: newValue)
            error = nil
        } catch {
            isPublic = previous
            self.error = error
        }
    }

    // MARK: - Target dispatch

    /// Applies the visibility change and returns the server's authoritative
    /// `isPublic`. Only the `isPublic` field is sent; the rest are `nil`, so
    /// the partial update leaves title / body / folder / parent untouched.
    private func update(isPublic: Bool) async throws -> Bool {
        switch target {
        case .document(let id):
            let doc = try await documents.update(id: id, title: nil, body: nil, folderId: nil, isPublic: isPublic)
            return doc.isPublic
        case .list(let id):
            // `OwnedList` models visibility as a closed enum, not a bool — map
            // the server's returned visibility back to the public flag.
            let list = try await lists.update(listId: id, title: nil, description: nil, isPublic: isPublic, parentId: nil)
            return list.visibility.isPubliclyVisible
        }
    }
}
