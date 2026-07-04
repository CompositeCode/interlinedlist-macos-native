# Next-work follow-ups (blocked on upstream)

**Audience:** the macOS app maintainers (orchestrator + implementing agents).

Work that is fully designed on the macOS side but cannot ship until an upstream change lands. Each entry pins the trigger (what unblocks it) and where the design already lives so the work can be picked up cold.

When picking an item up:

1. Re-verify the trigger has actually landed (don't trust the entry &mdash; probe the live API).
2. Read the referenced design notes / decision records.
3. Update the entry to `Status: in flight` with a date, and remove it when shipped.
4. If the trigger was solved differently than predicted, capture the deviation in `docs/progress.md` under the consuming wave.

---

## NW-1 &mdash; Watcher invite flow (Phase 4 / M3 Lists)

- **Status:** Blocked on upstream API.
- **What ships in M3 instead:** Role editor for users who are *already* watching a list (rename/promote/demote/remove). No invite-a-new-user UX.
- **Trigger to resume:** `GET /api/users/lookup?handle=…` or `GET /api/users/search?q=…` lands on interlinedlist.com. The ask is filed in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) item 1.5.
- **Design already in place:**
  - `InterlinedDomain.ListsService.setWatcher(listId:userId:role:)` already covers the PUT once a `userId` is known.
  - `WatcherRole.swift` enumerates the role taxonomy with `WatcherRole.other(String)` preserving unknown wire values.
- **Work to do once unblocked:**
  1. Add a `UsersService.lookup(handle:)` or `.search(query:limit:)` method in `InterlinedDomain` (whichever shape lands).
  2. Wrap it in a SwiftUI share-sheet view in `App/Features/Lists/Sharing/`:
     - "Add a user…" text field with debounced autocomplete (if `search`) or Enter-to-resolve (if `lookup`).
     - Role picker drop-down using `WatcherRole`.
     - Confirm button → `ListsService.setWatcher(listId:userId:role:)`.
     - Inline error rendering for "user not found" / "user is private" / "user already watching".
  3. Add BDD-named unit tests against the new service method.
  4. Flip the relevant `docs/api-coverage.md` row.
- **Estimated size:** Small &mdash; one new domain method, one new SwiftUI view, ~6-8 tests. Half-day of focused work once the endpoint exists.

---

## NW-2 &mdash; Cross-post per-platform status sheet (Phase 7 / M6 Subscriber)

- **Status:** Blocked on upstream API.
- **What ships in M6 instead:** Composer cross-post toggles (Mastodon provider-ids / Bluesky / LinkedIn) send the targets on `POST /api/messages`, but there is no post-publish "Posted to Mastodon ✓ — Bluesky failed: rate limited" sheet.
- **Trigger to resume:** `POST /api/messages` returns the per-platform result envelope (`crossPosts: [{ platform, status, externalUrl?, error? }]`). Filed in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) ask **1.4** (P1).
- **Design already in place:** Composer cross-post UI + subscriber gating ship in M6; only the result rendering is missing. The `createPost` path already carries the request fields.
- **Work to do once unblocked:**
  1. Decode the `crossPosts` array into a domain `CrossPostResult` value in `MessagesService.createPost`.
  2. Render a post-publish status sheet in the composer (per-platform row + retry affordance where the error is retryable).
  3. BDD-named tests for the envelope mapping + the sheet view model.
  4. Drop the `docs/user/feature-status.md` "no per-platform result summary" Limits bullet.

---

## NW-3 &mdash; Scheduled-post cancel / reschedule (Phase 7 / M6 Subscriber)

- **Status:** Blocked on upstream API.
- **What ships in M6 instead:** Read-only **Scheduled** sidebar section (`ScheduledPostsRootView` / `ScheduledPostsViewModel`) listing `GET /api/messages/scheduled`. No cancel or reschedule before `scheduledAt` fires.
- **Trigger to resume:** A documented cancel / reschedule path for scheduled posts &mdash; either `DELETE /api/messages/[id]` confirmed to work on a not-yet-published scheduled post, or `PUT /api/messages/[id]` confirmed to move `scheduledAt`. Filed in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) ask **3.3** (P3).
- **Design already in place:** `MessagesService` already wraps `DELETE` / `PUT` for live messages; reuse against scheduled ids once the semantics are confirmed.
- **Work to do once unblocked:**
  1. Probe the live API to confirm which verb cancels / reschedules a scheduled post (do not trust the ask).
  2. Add a `cancelScheduled(id:)` / `reschedule(id:to:)` path in `MessagesService` (or confirm the existing `delete` / `update` cover it).
  3. Add Cancel / Reschedule actions to `ScheduledPostsViewModel` (optimistic row drop / date edit + rollback).
  4. BDD-named tests; drop the "Scheduled posts are read-only" Limits bullet.

---

## NW-4 &mdash; Per-platform cross-post readiness (Phase 7 / M6 Subscriber)

- **Status:** Blocked on upstream API.
- **What ships in M6 instead:** The composer can reflect LinkedIn readiness via `GET /api/auth/linkedin/status`, but cannot detect Bluesky / Mastodon (per-instance) readiness before the user posts &mdash; unconfigured platforms are only discovered on failure.
- **Trigger to resume:** `GET /api/auth/bluesky/status` and `GET /api/auth/mastodon/status?instance=…` returning `{ "configured": boolean }` (the same shape `linkedin/status` already returns). Filed in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) ask **3.6** (P3).
- **Design already in place:** Kit already has `Auth.linkedinStatus()`; a sibling builder per provider mirrors it. The composer toggle already has a disabled / upsell state to reuse.
- **Work to do once unblocked:**
  1. Add the Bluesky / Mastodon status builders to the Kit (mirror `linkedinStatus()`).
  2. Surface readiness through the composer cross-post toggle (disable + hint when unconfigured).
  3. BDD-named tests; drop the "readiness only known for LinkedIn" Limits bullet.

---

## NW-5 &mdash; Native OAuth identity linking (Phase 7 / M6 Subscriber)

- **Status:** Blocked on upstream API. Browser-handoff fallback ships in M6 ([Decision 0006](docs/decisions/0006-oauth-identity-linking-browser-handoff.md)).
- **What ships in M6 instead:** **Settings > Linked accounts** opens `…/authorize?link=true` in the default browser via SwiftUI `@Environment(\.openURL)` (no AppKit, no `ASWebAuthenticationSession`). No in-app completion: the app builds the URL (`UserService.identityLinkURL(provider:instance:)`) and lists existing links (`UserService.identities()`), but the link is completed on the web.
- **Trigger to resume:** Either upstream change from [spike 0002](docs/spikes/0002-oauth-identity-linking.md) &mdash; **(preferred)** a custom-scheme / universal-link callback the macOS app can register (so `ASWebAuthenticationSession` can complete the flow), **or** a bearer-authenticated `POST /api/auth/{provider}/link` taking the provider code/token. The maintainer question is filed verbatim in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) ask **2.6** (P2).
- **Design already in place:** Kit builders `Auth.authorize(provider:link:instance:)` / `Auth.linkedinStatus()`, `OAuthProvider`, `LinkedInStatusResponse` landed in 7.0 (additive, no UI). The blocker analysis and recommended posture are in [spike 0002](docs/spikes/0002-oauth-identity-linking.md).
- **Work to do once unblocked:**
  1. Re-probe the four providers' callback contract to confirm the new mechanism (do not trust the ask).
  2. If custom-scheme / universal-link: register the scheme/associated-domain, complete via `ASWebAuthenticationSession`, exchange the one-time code. If bearer `…/link`: add a `UserService.linkIdentity(provider:code:)` and call it directly.
  3. Replace the Linked accounts "Link account ↗" browser action with the native flow; supersede Decision 0006's browser-handoff posture.
  4. BDD-named tests; flip the five OAuth coverage rows' Tested column (footnote 12); drop the "linking happens in your browser" Limits bullet.

---

## NW-6 &mdash; Org member-add by handle + the two unconsumed org reads (Phase 7 / M6 Subscriber)

- **Status:** Blocked on upstream API (same blocker as NW-1).
- **What ships in M6 instead:** Org member-add is by **raw userId** (`OrgMembersViewModel` → `OrgService.addMember`); role edit / remove work for existing members. No handle search. Separately, two `OrgService` reads stay unconsumed this wave: `GET /api/organizations` (list-all variant &mdash; the UI lists the current user's orgs via `UserService.organizations()` instead) and `GET /api/organizations/[id]/users` (`OrgService.users(of:)` &mdash; the roster renders from `/members`). Both held at ◐⁴ under coverage-matrix footnote 13.
- **Trigger to resume:** Handle&rarr;userId lookup &mdash; `GET /api/users/lookup?handle=…` or `GET /api/users/search?q=…` &mdash; the **same** endpoint NW-1 waits on. Filed in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) ask **1.5** (P1); the org-member need is noted there as a second consumer.
- **Design already in place:** `OrgService.addMember(orgId:userId:role:)` already covers the add once a `userId` is known; `OrgRole` (with `.other(String)`) enumerates the role taxonomy. Reuse whichever lookup shape NW-1 builds (`UsersService.lookup` / `.search`).
- **Work to do once unblocked:**
  1. Reuse the NW-1 `UsersService.lookup` / `.search` method in the org member-add sheet (handle field &rarr; resolve &rarr; role picker &rarr; `addMember`).
  2. Optionally consume `GET /api/organizations` and `GET /api/organizations/[id]/users` through a tested view model and flip their footnote-13 rows.
  3. BDD-named tests; drop the "member-add uses a user id, not a handle" Limits bullet.

---

## How to add an entry

Each entry needs: a unique ID (`NW-N` where `N` increments), the trigger, the deferred-design pointer, and the picked-up steps. Keep entries terse &mdash; this file is a worklist, not documentation.

---

## NW probe — 2026-07-03

Probed all 6 NW items against the live API (https://interlinedlist.com) using the `messenger@interlinedlist.com` test account. Auth shape confirmed: `{ "token": "…", "message": "…" }`.

**No items unblocked.** All 6 remain blocked. Status changes: none.

- **NW-1 / NW-6** — Both `GET /api/users/lookup?handle=test` and `GET /api/users/search?q=test` return HTTP 404. Routes do not exist.
- **NW-2** — `POST /api/messages` succeeds (field is `content` not `body`; `visibility` not a valid field — use `publiclyVisible: Bool`). Response has `crossPostUrls: null` and `scheduledCrossPostConfig: null` but no `crossPosts: [{ platform, status, externalUrl?, error? }]` envelope. Test post created and deleted cleanly.
- **NW-3** — `GET /api/messages/scheduled` returns `{"messages":[]}`. No scheduled posts in test account; cancel/reschedule trigger unverifiable.
- **NW-4** — `GET /api/auth/bluesky/status` and `GET /api/auth/mastodon/status` (with and without `?instance=`) both return HTTP 404. Routes do not exist.
- **NW-5** — `GET /api/auth/github/authorize?link=true` returns HTTP 307. `redirect_uri` is `https://interlinedlist.com/api/auth/github/callback` — web URL, no custom scheme or universal link. Decision 0006 browser-handoff posture unchanged.
