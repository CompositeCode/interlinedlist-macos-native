// ListFoldersViewModel
//
// Drives the Lists-sidebar folder tree (the-gaps.md G6). Owns the loaded
// `[ListFolderNode]` tree, the loading / error state, and the create /
// rename / move / delete actions. Reads through `ListFoldersServicing`
// only — no direct API or entitlements access — so unit tests substitute
// a stub service.
//
// Subscriber gate: folder *creation* is subscriber-only. The domain
// service throws `ListFoldersError.subscriberRequired` before any HTTP
// when the account is not a subscriber. This view model catches that
// specific case and raises `showSubscriberUpsell` instead of surfacing a
// raw error, so the view can present an upsell / disabled affordance
// rather than an error banner. Every other failure flows into `error`.
//
// Mutations refresh the tree from the service's authoritative return
// (create / rename / move return the updated `ListFolder`; the tree is
// rebuilt from a fresh `folders()` fetch so nesting stays correct without
// the view model re-implementing tree assembly). Delete uses optimistic
// removal with snapshot rollback on failure.
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ListFoldersViewModel {

    // MARK: - Dependencies

    private let service: ListFoldersServicing

    // MARK: - Observable state

    /// The assembled folder tree, roots first.
    private(set) var tree: [ListFolderNode] = []

    /// True while a load / mutation round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// Surfaced error from the most recent failed load / rename / move /
    /// delete. The subscriber-gate case is routed to
    /// `showSubscriberUpsell` instead, so this never carries a
    /// `subscriberRequired`.
    private(set) var error: Error?

    /// Raised when a create was blocked because the account is not a
    /// subscriber. The view presents an upsell / disabled state. Reset by
    /// `dismissUpsell()` or the next successful create.
    private(set) var showSubscriberUpsell: Bool = false

    /// True once the first load has resolved (success or failure).
    private(set) var hasLoadedOnce: Bool = false

    /// Per-folder debounce set so a rapid double-tap on delete doesn't
    /// double-fire the service call.
    private var pendingOperations: Set<String> = []

    // MARK: - Init

    init(service: ListFoldersServicing) {
        self.service = service
    }

    // MARK: - Intents

    /// First-time + refresh load. Replaces the rendered tree.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            tree = try await service.tree()
            error = nil
            hasLoadedOnce = true
        } catch {
            self.error = error
            hasLoadedOnce = true
        }
    }

    /// Creates a folder under `parentId` (or at root when nil), then
    /// refreshes the tree. A `subscriberRequired` failure raises the
    /// upsell instead of an error; an `invalidName` (or any other) failure
    /// flows into `error`. Returns the created folder on success so the
    /// caller can, e.g., select it.
    @discardableResult
    func create(name: String, parentId: String? = nil) async -> ListFolder? {
        showSubscriberUpsell = false
        do {
            let folder = try await service.create(name: name, parentId: parentId)
            await reloadTree()
            error = nil
            return folder
        } catch ListFoldersError.subscriberRequired {
            showSubscriberUpsell = true
            return nil
        } catch {
            self.error = error
            return nil
        }
    }

    /// Renames a folder, then refreshes the tree.
    func rename(id: String, to name: String) async {
        do {
            _ = try await service.rename(id: id, name: name)
            await reloadTree()
            error = nil
        } catch {
            self.error = error
        }
    }

    /// Moves a folder under a new parent (or to root when nil), then
    /// refreshes the tree.
    func move(id: String, toParent parentId: String?) async {
        do {
            _ = try await service.move(id: id, toParent: parentId)
            await reloadTree()
            error = nil
        } catch {
            self.error = error
        }
    }

    /// Deletes a folder. Optimistic: prune the subtree locally, call the
    /// service, restore the snapshot on failure.
    func delete(id: String) async {
        guard !pendingOperations.contains(id) else { return }
        pendingOperations.insert(id)
        defer { pendingOperations.remove(id) }
        let snapshot = tree
        tree = Self.pruning(id: id, from: tree)
        do {
            try await service.delete(id: id)
            error = nil
        } catch {
            tree = snapshot
            self.error = error
        }
    }

    /// Dismisses the subscriber upsell (the "Upgrade" sheet was shown /
    /// cancelled).
    func dismissUpsell() {
        showSubscriberUpsell = false
    }

    /// Convenience for tests + previews — seed the rendered tree without
    /// going through the service.
    func seedForTest(tree: [ListFolderNode]) {
        self.tree = tree
        self.hasLoadedOnce = true
    }

    // MARK: - Internals

    /// Refetches and reassembles the tree after a mutation. Failures here
    /// surface as `error` but do not undo the mutation (the server already
    /// applied it; a subsequent `load()` reconciles).
    private func reloadTree() async {
        do {
            tree = try await service.tree()
        } catch {
            self.error = error
        }
    }

    /// Returns `nodes` with the node identified by `id` (and its subtree)
    /// removed. Pure; used for the optimistic delete prune.
    private static func pruning(id: String, from nodes: [ListFolderNode]) -> [ListFolderNode] {
        nodes.compactMap { node in
            guard node.id != id else { return nil }
            return ListFolderNode(
                folder: node.folder,
                children: pruning(id: id, from: node.children)
            )
        }
    }
}
