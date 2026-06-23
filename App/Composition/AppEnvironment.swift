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
        listsStore: ListsStore
    ) {
        self.messages = messages
        self.lists = lists
        self.social = social
        self.session = session
        self.currentUserStore = currentUserStore
        self.composerEventBus = composerEventBus
        self.listsEventBus = listsEventBus
        self.listsStore = listsStore
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
        let messages = MessagesService(api: api, store: store)
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
        let currentUserStore = CurrentUserStore(session: session)
        let composerEventBus = ComposerEventBus()
        let listsEventBus = ListsEventBus()
        let listsStore = Self.makeListsStore()
        return AppEnvironment(
            messages: messages,
            lists: lists,
            social: social,
            session: session,
            currentUserStore: currentUserStore,
            composerEventBus: composerEventBus,
            listsEventBus: listsEventBus,
            listsStore: listsStore
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
