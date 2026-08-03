// LaunchPrefetchCoordinator
//
// Layer 3 of the persistent stale-while-revalidate (SWR) feature
// (PLAN.md §5). At launch the main window warms the section view models
// in the background so that navigating to any section paints from the
// on-disk cache instantly rather than waiting for that section's own
// `.task` to fire and round-trip the network.
//
// The coordinator is the *only* place these pre-warm view models are
// constructed. `MainWindowView` holds one coordinator, threads the
// pre-warmed VMs into `SidebarDetailDispatcher`, and each root view skips
// its own initial load when handed a pre-warmed VM (the "skip initial
// load for pre-warmed VMs" guard).
//
// Warming is cache-first: each VM's `initialLoad()` / `reload(in:)` /
// `load()` reads the cache off the service actor (so the main thread is
// never blocked), paints it, then revalidates over the network. Ownership-
// gated sections (Lists, Organizations) still paint their cache; the
// network refresh no-ops gracefully when signed out — a failed refresh
// over an empty cache leaves the section in its today's empty/error state,
// which is never rendered until the user actually navigates there.
//
// Decision 0003: the App target binds domain protocols only. This type
// consumes the already-wired `AppEnvironment` and never imports
// `InterlinedKit`.

import Foundation
import InterlinedDomain

/// Builds and warms the four/five section view models at launch. Held by
/// `MainWindowView` as `@State`; its `warm()` runs once from the window's
/// `.task`.
@MainActor
final class LaunchPrefetchCoordinator {

    // MARK: - Pre-warmed view models
    //
    // Non-nil after `warm()`. Threaded into `SidebarDetailDispatcher` so the
    // section root views adopt them instead of building their own.

    let listsVM: OwnedListsViewModel
    let folderTreeVM: FolderTreeViewModel
    let documentsListVM: DocumentsListViewModel
    let scheduledVM: ScheduledPostsViewModel
    let organizationsVM: OrganizationsListViewModel

    /// Guards against a double `warm()` if the window's `.task` re-fires.
    private var didWarm = false

    // MARK: - Init

    /// Designated initializer over the domain protocols the section view
    /// models bind against — so tests can substitute the App-target stubs
    /// (`Stub*Service`) without constructing a full `AppEnvironment`.
    init(
        lists: ListsServicing,
        documents: DocumentsServicing,
        messages: MessagesServicing,
        orgService: OrgServicing,
        userService: UserServicing
    ) {
        self.listsVM = OwnedListsViewModel(lists: lists)
        self.folderTreeVM = FolderTreeViewModel(documents: documents)
        self.documentsListVM = DocumentsListViewModel(documents: documents)
        self.scheduledVM = ScheduledPostsViewModel(messages: messages)
        self.organizationsVM = OrganizationsListViewModel(
            orgService: orgService,
            userService: userService
        )
    }

    /// Production convenience initializer: wires from the composition root.
    convenience init(environment: AppEnvironment) {
        self.init(
            lists: environment.lists,
            documents: environment.documentsService,
            messages: environment.messages,
            orgService: environment.orgService,
            userService: environment.userService
        )
    }

    // MARK: - Warm

    /// Kicks off each section's cache-first initial load. Each runs in its
    /// own detached-from-the-caller `Task` so a slow network refresh in one
    /// section never delays another (or the window's `.task` returning). The
    /// cache read inside each `initialLoad` happens on the service actor, so
    /// the main thread is not blocked while cache is fetched.
    func warm() {
        guard !didWarm else { return }
        didWarm = true
        Task { await warmAll() }
    }

    /// The awaitable core the fire-and-forget `warm()` wraps. Runs all five
    /// section loads concurrently and returns when every one has settled.
    /// Tests call this directly for a deterministic assertion point.
    func warmAll() async {
        async let lists: Void = listsVM.initialLoad()
        async let folders: Void = folderTreeVM.initialLoad()
        async let docs: Void = documentsListVM.reload(in: nil)
        async let scheduled: Void = scheduledVM.load()
        async let orgs: Void = organizationsVM.load()
        _ = await (lists, folders, docs, scheduled, orgs)
    }
}
