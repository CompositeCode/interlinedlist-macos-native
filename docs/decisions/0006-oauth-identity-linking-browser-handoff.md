# Decision 0006 — OAuth identity linking: browser handoff, native completion deferred

- **Status:** Accepted (2026-06-25)
- **Wave:** Locked in during Wave 7 (M6 Subscriber + orgs), after the 7.0 OAuth spike.
- **Related:** [Spike 0002 — OAuth identity linking: native completion viability](../spikes/0002-oauth-identity-linking.md), [Decision 0001](0001-auth-transport.md) (Bearer-primary transport), [Decision 0003](0003-kit-import-policy.md) (kit-import policy), PLAN.md §4 (account linking via `ASWebAuthenticationSession`), `feedback_swiftui_only.md` (SwiftUI-only constraint), [`API-backend-prompts-to-build.md`](../../API-backend-prompts-to-build.md) ask 2.6, [`NEXT-WORK.md`](../../NEXT-WORK.md) NW-5.

## Context

PLAN.md §4 calls for linking GitHub / Mastodon / Bluesky / LinkedIn identities to the InterlinedList account, and names `ASWebAuthenticationSession` as the intended native mechanism. The web app links these via `GET /api/auth/{provider}/authorize?link=true`.

The Wave 7.0 spike ([spike 0002](../spikes/0002-oauth-identity-linking.md)) live-probed the four providers' `/authorize` endpoints (and `GET /api/auth/linkedin/status`) against the live API. The finding is consistent across all four providers: **a native macOS client cannot complete one of these OAuth flows against the API as it exists today.** Three independent blockers:

1. **The registered callback is a web URL on `interlinedlist.com`, not a custom scheme or universal link.** Every provider's `redirect_uri` (and the Bluesky client-metadata `redirect_uris`, whose `application_type` is literally `"web"`) points at `https://interlinedlist.com/api/auth/{provider}/callback`. `ASWebAuthenticationSession` requires a callback the system can match — a custom scheme or an associated-domain universal link the app claims. Neither exists here, and a native client cannot register or intercept the web callback.
2. **The flow is cookie-bound, not bearer-bound.** `/authorize` issues short-lived `HttpOnly` `oauth_state` (and, for Mastodon, `oauth_mastodon_creds`) cookies, and `/callback` requires both those cookies *and* the logged-in `interlinedlist.com` session cookie to associate the new identity with the right account. Our app's primary transport is the bearer token (decision 0001); it does not hold the web session cookie, so even a hidden web view that completed the redirect would link the identity to whatever account the embedded cookie jar happens to be signed into — not deterministically to our bearer-token user.
3. **There is no native-completion contract.** Nothing in the probed surface offers a custom-scheme callback, a deep-link handoff, a code-exchange endpoint, or a bearer-authenticated `…/link` variant. The flow is designed end-to-end for a first-party browser.

The blocker is upstream, not in our Kit.

## Decision

**Defer native OAuth identity-linking UI (story 7.4) and ship a browser-handoff fallback instead.** Concretely:

1. The Kit gains the additive, harmless request builders this wave — `Auth.authorize(provider:link:instance:)`, `Auth.linkedinStatus()`, plus the `OAuthProvider` enum and `LinkedInStatusResponse` DTO. They cost nothing, import no new framework, and let a future feature (or the fallback below) construct the correct URLs.
2. The App ships a **Settings → Linked accounts** pane (`LinkedAccountsView` / `LinkedAccountsViewModel`) that lists the user's linked identities (`UserService.identities()`) and, per provider, offers a **"Link account ↗"** action that opens the web `…/authorize?link=true` flow in the **default browser**, where the user is already (or gets) signed in and completes the link on the web. Mastodon prompts for an instance domain first.
3. The browser is opened via SwiftUI's `@Environment(\.openURL)` — **no AppKit, no `ASWebAuthenticationSession`, no new framework.** A new domain method `UserServicing.identityLinkURL(provider:instance:) throws -> URL` resolves the Kit `Auth.authorize` builder against the configured base URL so the App layer never touches a Kit type (decision 0003 stays intact).
4. There is **no in-app completion**: the app does not intercept the callback, does not send the `…/authorize` URL itself, and does not poll for the result. After the user finishes in the browser, the Linked accounts pane refreshes `identities()` to reflect the new link.

## Rationale

- **The fully viable, zero-upstream-change path is the browser handoff.** Spike 0002 lays out the two upstream changes that would unblock native completion (a custom-scheme/universal-link callback, or a bearer `POST /api/auth/{provider}/link`); both require server work we do not control. The browser fallback ships the user-facing capability now with no server dependency.
- **It deliberately needs NO AppKit / new-framework exception.** Unlike Decision 0005 (which had to carve out one AppKit file for the dock badge because macOS 15 SwiftUI has no dock-badge API), this decision uses only the public SwiftUI `openURL` environment action. The SwiftUI-only memory rule (`feedback_swiftui_only.md`) is satisfied without a pause-and-ask, and the kit-import policy (decision 0003) is satisfied by the `identityLinkURL` domain method. No new decision-level exception is created.
- **The Kit builders are honest about their status.** They make the five M6 OAuth coverage rows *implementable* (the matrix flips their Implemented column this wave) but **not end-to-end consumable by design** — the `…/authorize` URL is browser-opened, not sent by the app, and `linkedin/status` is currently unconsumed. The coverage matrix records this with footnote 12 (Tested stays untested, native completion blocked per spike 0002).
- **Escalate, don't guess.** The maintainer question is filed verbatim (see Consequences) so the upstream direction is a decision the maintainer makes, not one the client assumes.

## Maintainer question (filed)

Filed verbatim in [`API-backend-prompts-to-build.md`](../../API-backend-prompts-to-build.md) as ask **2.6**:

> *Will the API expose a native-callback (custom scheme/universal link) or a bearer-authenticated `POST /api/auth/{provider}/link`, or should macOS link by opening the web `…/authorize?link=true` flow in the default browser with no in-app completion?*

The browser-handoff fallback this decision ships is the third option in that question; if the maintainer chooses either of the first two, native completion is picked up per NW-5.

## Consequences

### What ships in Wave 7

- Kit: `OAuthProvider`, `LinkedInStatusResponse`, `Auth.authorize(provider:link:instance:)`, `Auth.linkedinStatus()` (+13 tests).
- Domain: `UserServicing.identityLinkURL(provider:instance:) throws -> URL`.
- App: `SettingsRootView` (replaces `SettingsPlaceholderView` in the `Settings{}` scene) with a **Linked accounts** pane (`LinkedAccountsView` / `LinkedAccountsViewModel`).

### What does not ship (deferred to NW-5)

- In-app OAuth completion (`ASWebAuthenticationSession`, custom-scheme callback handling, code exchange). The PLAN.md §4 `ASWebAuthenticationSession` mechanism is **not** wired this wave; it lands only if the upstream callback contract changes.

### Trigger to revisit

Either upstream change in spike 0002's recommendation:

- a custom-scheme / universal-link callback the macOS app can register (preferred), **or**
- a bearer-authenticated `POST /api/auth/{provider}/link`.

Tracked in `NEXT-WORK.md` NW-5. When either lands, supersede the browser-handoff fallback with the native flow and re-probe before building (the standard NEXT-WORK rule).

### User-visible limit

The Linked accounts pane sends the user to the browser to complete a link rather than completing it in-app. This is documented in `docs/user/feature-status.md` as a Limits bullet.

### Out of scope of this decision

- Cross-posting itself (the composer's Mastodon / Bluesky / LinkedIn toggles). Those send through `POST /api/messages` cross-post fields and do not use the `/authorize` flow; they are unaffected by this decision.
- The shape of the eventual native flow. That is NW-5's design problem once the upstream contract exists.
