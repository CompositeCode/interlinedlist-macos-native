// AppEnvironment
//
// Composition root for the App target (PLAN.md §3 — the App target is
// UI-only and depends on domain protocols). Constructs the concrete
// graph of services once at launch and exposes only the protocol-typed
// surfaces the view layer binds against.
//
// View models never construct services themselves — they read this
// environment via the `appEnvironment` value or as an `EnvironmentObject`
// and depend on the domain protocols (`MessagesServicing`, …) so they
// remain trivially substitutable in tests.

import Foundation
import SwiftUI
import InterlinedDomain
import InterlinedKit
import InterlinedPersistence

/// Top-level service container constructed in `InterlinedListApp` at
/// launch. Pure DI: the type owns nothing reactive itself; it just
/// publishes already-wired services for views to consume.
@MainActor
final class AppEnvironment: ObservableObject {

    /// The timeline + message read / write service the Timeline and
    /// Compose features bind against. Exposed as the protocol so test
    /// doubles substitute in.
    let messages: MessagesServicing

    /// The public-list browse service the Lists feature binds against
    /// (PLAN.md §1 "Public list browsing", §6 M1). Exposed as the
    /// protocol so test doubles substitute in.
    let lists: ListsServicing

    /// The read-only social surface the Social feature binds against for
    /// the M1 profile UI (PLAN.md §1 "Profile" / "Follow system", §6 M1).
    let social: SocialServicing

    /// The current-session source the App layer reads when deciding
    /// whether to show ownership-gated affordances (M2 edit / delete
    /// menu items on a message row, PLAN.md §6 M2). Exposed as the
    /// protocol so tests substitute a stub session.
    let session: SessionManaging

    /// SwiftUI-friendly mirror of `session` for views and view models.
    /// Populated asynchronously from the session state stream — when
    /// `currentUserID` is `nil`, ownership-gated UI must hide itself
    /// (PLAN.md §6 M2 rule: never "enabled but broken").
    let currentUserStore: CurrentUserStore

    /// The current account's entitlements, computed live from
    /// `currentUserStore.currentUser` (Deliverable B / PLAN.md §6 M6 — feature
    /// gating). The composer reads this on every render to decide whether the
    /// media / scheduled / cross-post controls are enabled. This is the
    /// authoritative *UI* gate; the domain `MessagesService` enforces the same
    /// status as a backstop. Read on the main actor — a pure value, no I/O.
    var liveEntitlements: EntitlementsService {
        EntitlementsService(user: currentUserStore.currentUser)
    }

    /// Re-resolves the signed-in account's `customerStatus` (PLAN.md §8 — a
    /// gated call returning 403 means the subscription lapsed mid-session, so
    /// the UI must re-gate). The composer calls this when a gated `createPost`
    /// surfaces a 403; `restore()` flows the refreshed `CurrentUser` through
    /// both the UI gate (`currentUserStore.currentUser`) and the domain backstop
    /// (the `LiveEntitlements` box). Errors are intentionally swallowed — a
    /// failed re-fetch leaves the prior (conservative) gate in place.
    func refreshEntitlements() async {
        _ = try? await currentUserStore.restore()
    }

    /// Cross-window event bus the composer / repost sheet / detail
    /// view post to after a successful create / reply / repost /
    /// update / delete. Open Timeline / Detail views subscribe and
    /// mutate their rendered lists in place without a full refetch.
    let composerEventBus: ComposerEventBus

    /// Cross-window event bus for the M3 Lists feature
    /// (PLAN.md §6 M3 — list / row / schema / watcher / connection
    /// writes). Owned-list sidebar, schema editor, rows table,
    /// watchers panel, and the connections graph all subscribe so a
    /// write in any open window mutates other views in place without
    /// a refetch.
    let listsEventBus: ListsEventBus

    /// The lists cache port (PLAN.md §5 — "stale-while-revalidate").
    /// M3 wires a `SwiftDataListsStore.inMemory()`; future on-disk
    /// persistence drops in by swapping the factory. Falls back to
    /// `NullListsStore` if the in-memory container cannot be built.
    let listsStore: ListsStore

    /// The documents read / write / sync service the M4 Documents UI
    /// binds against (PLAN.md §6 M4). Exposed as the protocol so test
    /// doubles substitute in.
    let documentsService: DocumentsServicing

    /// The owner of `/api/documents/sync` — the M4 offline backbone
    /// (PLAN.md §3, §6 M4). The App layer reaches in directly for the
    /// `syncNow()` button on the toolbar; the rest of the App talks to
    /// the service surface above.
    let documentSyncEngine: DocumentSyncEngine

    /// The shared sync event stream the documents UI subscribes to so
    /// open windows refresh on `deltaApplied`, banner on
    /// `conflictResolved`, and drop optimistic chrome on `pushed`. Held
    /// here so the test composition can substitute a hand-driven stream.
    let documentSyncEvents: AsyncStream<DocumentSyncEvent>

    /// The notifications tray + mark-read service the M5 tray UI binds
    /// against (PLAN.md §1 "Notifications", §6 M5). Exposed as the
    /// protocol so test doubles substitute in.
    let notificationsService: NotificationsServicing

    /// Cross-window event bus for the M5 Notifications + Social
    /// Requests features (PLAN.md §6 M5 — dock badge, tray, requests).
    /// Tray writes, mark-read mutations, and request approve/reject
    /// flows post to this bus so other open windows (dock badge
    /// coordinator, requests panel, inline tray rows) update in place
    /// without a refetch.
    let notificationsEventBus: NotificationsEventBus

    /// Cache of follower / following / mutual counts per user
    /// (PLAN.md §5 — stale-while-revalidate). The M5 profile header
    /// paints instantly from the cache before the network refresh
    /// lands. Exposed as the concrete actor; the App layer reads it
    /// through value-typed projections (`CachedFollowCounts`) so the
    /// store never escapes its isolation domain.
    let followCountsStore: SwiftDataFollowCountsStore?

    /// Reads the M5 follow-relationship state without forcing the
    /// view layer to import `InterlinedKit` (see
    /// `FollowRelationshipReader.swift` for the rationale). Exposed
    /// as the protocol so tests substitute a stub.
    let followRelationshipReader: FollowRelationshipReading

    /// The organizations surface the M6 Organizations feature binds
    /// against (PLAN.md §1 "Organizations", §6 M6). Exposed as the
    /// protocol so test doubles substitute in.
    let orgService: OrgServicing

    /// The account-self surface the M6 Settings > Linked-accounts pane
    /// binds against — linked identities and (browser-handoff) OAuth
    /// link URLs (PLAN.md §1 "Profile & account", §6 M6). Exposed as
    /// the protocol so test doubles substitute in.
    let userService: UserServicing

    /// Designated initializer used by tests and previews that want to
    /// inject a fully synthetic service graph. Production code calls
    /// `live()` instead.
    init(
        messages: MessagesServicing,
        lists: ListsServicing,
        social: SocialServicing,
        session: SessionManaging,
        currentUserStore: CurrentUserStore,
        composerEventBus: ComposerEventBus,
        listsEventBus: ListsEventBus,
        listsStore: ListsStore,
        documentsService: DocumentsServicing,
        documentSyncEngine: DocumentSyncEngine,
        documentSyncEvents: AsyncStream<DocumentSyncEvent>,
        notificationsService: NotificationsServicing,
        notificationsEventBus: NotificationsEventBus,
        followCountsStore: SwiftDataFollowCountsStore?,
        followRelationshipReader: FollowRelationshipReading,
        orgService: OrgServicing,
        userService: UserServicing
    ) {
        self.messages = messages
        self.lists = lists
        self.social = social
        self.session = session
        self.currentUserStore = currentUserStore
        self.composerEventBus = composerEventBus
        self.listsEventBus = listsEventBus
        self.listsStore = listsStore
        self.documentsService = documentsService
        self.documentSyncEngine = documentSyncEngine
        self.documentSyncEvents = documentSyncEvents
        self.notificationsService = notificationsService
        self.notificationsEventBus = notificationsEventBus
        self.followCountsStore = followCountsStore
        self.followRelationshipReader = followRelationshipReader
        self.orgService = orgService
        self.userService = userService
    }

    /// Builds the production service graph:
    ///
    /// `KeychainTokenStore` → `DefaultAuthTransport` (Bearer-only for
    /// M1; the session establisher is `NullSessionEstablisher` because
    /// the timeline feature only touches Bearer endpoints) →
    /// `APIClient` → `SwiftDataMessageStore` → `MessagesService`.
    ///
    /// M2 adds `AuthService` → `SessionService` → `CurrentUserStore`
    /// so the timeline / detail UI can ownership-gate the edit / delete
    /// menu items, and a singleton `ComposerEventBus` so the composer
    /// window can notify the open Timeline of a successful write.
    ///
    /// TODO: M4 — swap the in-memory message store for a persistent
    /// one once `InterlinedPersistence` exposes a public factory for
    /// the on-disk `ModelContainer`. The schema types are package-
    /// internal today, so the App target cannot construct a persistent
    /// container without crossing the package boundary. Per PLAN.md §5
    /// the cache accelerates rendering but is best-effort; the
    /// in-memory variant keeps stale-while-revalidate working within
    /// a single session, and document sync (M4) is what actually
    /// needs persistence.
    static func live() -> AppEnvironment {
        let tokenStore = KeychainTokenStore()
        let authTransport = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: URLSession.shared,
            sessionEstablisher: NullSessionEstablisher()
        )
        let api = APIClient(authTransport: authTransport)
        let store = Self.makeMessageStore()
        // Deliverable B (PLAN.md §8): the domain `MessagesService` gate must
        // track the live account, not a `.free` snapshot taken at launch. The
        // box starts `.free` (signed-out) and is updated by `CurrentUserStore`
        // on every resolved session state, so a real subscriber is granted M6
        // features once sign-in resolves and a mid-session lapse re-gates. The
        // provider closure is evaluated by the service on every gated call.
        let liveEntitlements = LiveEntitlements()
        let messages = MessagesService(
            api: api,
            store: store,
            entitlementsProvider: { liveEntitlements.current() }
        )
        // Reuse the same kit-layer APIClient: M1 list browsing hits the
        // same Bearer-only public endpoints the timeline does, so a
        // second client would be redundant and would double up auth
        // bookkeeping at no benefit.
        let lists = ListsService(api: api)
        let social = SocialService(api: api)
        // Auth + session — the kit-level `AuthService` owns the token
        // store and credential exchange; `SessionService` adds the
        // `GET /api/user` read that turns a stored token into a
        // `CurrentUser`. Cache is shared with the messages store so
        // sign-out clears the timeline cache.
        let auth = AuthService(api: api, tokenStore: tokenStore)
        let session = SessionService(auth: auth, api: api, cache: store)
        // Hand the same box to the store so resolved sessions publish their
        // `customerStatus` into the source the domain gate reads (Deliverable B).
        let currentUserStore = CurrentUserStore(session: session, liveEntitlements: liveEntitlements)
        let composerEventBus = ComposerEventBus()
        let listsEventBus = ListsEventBus()
        let listsStore = Self.makeListsStore()
        // M4 Documents (PLAN.md §6 M4). The sync engine owns
        // `/api/documents/sync`; the service wraps single-shot CRUD +
        // delegates sync to the engine. View models read only the
        // domain protocol, so swapping the transport / store later is
        // a one-line change. Persistence is best-effort: if the
        // in-memory SwiftData container can't be constructed at all,
        // the no-op `NullDocumentStore` keeps the service usable for
        // online-only CRUD and the sync engine effectively becomes
        // a noop.
        let documentStore = Self.makeDocumentStore()
        let documentTransport = KitDocumentSyncTransport(api: api)
        let documentSyncEngine = DocumentSyncEngine(
            transport: documentTransport,
            store: documentStore,
            clock: { Date() }
        )
        let documentsService = DocumentsService(
            api: api,
            sync: documentSyncEngine
        )
        let documentSyncEvents = documentSyncEngine.events
        // M5 — Notifications + Social write surface (PLAN.md §6 M5).
        // `NotificationsService` already exists with the read + mark
        // surfaces; the App-layer event bus + dock-badge coordinator
        // are wired in `InterlinedListApp` so subscription lifetimes
        // align with the SwiftUI scene's `.task`.
        let notificationsService = NotificationsService(api: api)
        let notificationsEventBus = NotificationsEventBus()
        let followCountsStore = Self.makeFollowCountsStore()
        let followRelationshipReader = SocialFollowRelationshipReader(social: social)
        // M6 — Organizations + linked-accounts (PLAN.md §6 M6). Both reuse
        // the same kit-layer `APIClient` like `lists` / `social` do: the org
        // endpoints are Bearer and the user identity / org endpoints are the
        // decision-0001 session allowlist, both already routed by the shared
        // `authTransport`. `UserService` takes the default production base URL
        // for the browser-handoff OAuth link flow.
        let orgService = OrgService(api: api)
        let userService = UserService(api: api)
        return AppEnvironment(
            messages: messages,
            lists: lists,
            social: social,
            session: session,
            currentUserStore: currentUserStore,
            composerEventBus: composerEventBus,
            listsEventBus: listsEventBus,
            listsStore: listsStore,
            documentsService: documentsService,
            documentSyncEngine: documentSyncEngine,
            documentSyncEvents: documentSyncEvents,
            notificationsService: notificationsService,
            notificationsEventBus: notificationsEventBus,
            followCountsStore: followCountsStore,
            followRelationshipReader: followRelationshipReader,
            orgService: orgService,
            userService: userService
        )
    }

    // MARK: - Store construction

    /// Returns an in-memory `SwiftDataMessageStore`, falling back to a
    /// no-op cache if even that cannot be constructed (sandbox edge
    /// cases). Persistence is a stale-while-revalidate accelerator
    /// (PLAN.md §5) — losing it is not fatal.
    private static func makeMessageStore() -> MessageStore {
        if let inMemory = try? SwiftDataMessageStore.inMemory() {
            return inMemory
        }
        return NullMessageStore()
    }

    /// Returns an in-memory `SwiftDataListsStore`, falling back to a
    /// no-op cache if even that cannot be constructed. Mirrors the
    /// `makeMessageStore` policy: persistence is best-effort.
    private static func makeListsStore() -> ListsStore {
        if let inMemory = try? SwiftDataListsStore.inMemory() {
            return inMemory
        }
        return NullListsStore()
    }

    /// Returns an in-memory `SwiftDataDocumentStore`, falling back to a
    /// `NullDocumentStore` when SwiftData refuses to construct one
    /// (sandbox edge cases). The sync engine is built around the
    /// `DocumentStore` protocol so the fallback keeps the engine
    /// constructable; in that degraded mode every call is a no-op.
    /// On-disk persistence drops in by swapping the factory for
    /// `SwiftDataDocumentStore.onDisk(at:)`.
    private static func makeDocumentStore() -> DocumentStore {
        if let inMemory = try? SwiftDataDocumentStore.inMemory() {
            return inMemory
        }
        return NullDocumentStore()
    }

    /// Returns an in-memory `SwiftDataFollowCountsStore`, or `nil` if
    /// SwiftData refuses to construct one (sandbox edge cases). The
    /// M5 profile view treats the cache as best-effort — a `nil` store
    /// simply means counts always come from the network with no
    /// stale-while-revalidate paint.
    private static func makeFollowCountsStore() -> SwiftDataFollowCountsStore? {
        try? SwiftDataFollowCountsStore.inMemory()
    }
}

// MARK: - NullMessageStore

/// No-op cache used only when the in-memory SwiftData store cannot be
/// constructed at all. The service contract treats every cache as
/// best-effort so a no-op is a safe last-resort fallback.
private struct NullMessageStore: MessageStore {
    func cachedTimeline(scope: TimelineScope, tag: String?) async -> [Message] { [] }
    func replaceTimeline(_ messages: [Message], scope: TimelineScope, tag: String?) async {}
    func cachedMessage(id: String) async -> Message? { nil }
    func upsert(_ messages: [Message]) async {}
    func clear() async {}
}

// MARK: - Environment plumbing

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppEnvironment? = nil
}

extension EnvironmentValues {
    /// The shared service container. `nil` outside a wired-up scene —
    /// every production scene must inject one via `.environment(...)`.
    var appEnvironment: AppEnvironment? {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
