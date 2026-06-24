# API backend prompts to build

**Audience:** the InterlinedList backend team (and anyone scoping API changes that the macOS client depends on).

This file lists concrete capabilities the macOS native client needs from the [InterlinedList API](https://interlinedlist.com/help/api) so the macOS experience is smooth, seamless, and native. Each entry has a **problem** (what hurts today), a **proposal** (what we'd build against), an **impact** (what part of the app it unblocks), and a **priority** band. Status quo is tracked in [docs/spikes/](docs/spikes/) and [docs/decisions/](docs/decisions/); this file collects the *asks*.

The list is grouped by priority. Within a band, entries are ordered by the milestone they unblock (see [PLAN.md §6](PLAN.md)).

---

## Priority 1 — blocking or near-blocking native UX

### 1.1 — Public profile read endpoint `GET /api/users/[username]`

- **Problem.** No such endpoint exists. The 2026-06-21 spike confirmed every reasonable variation (`/api/users/[username]`, `/api/user/[username]`, `/api/users/[username]/profile`, `/api/profile/[username]`, `/api/u/[username]`, `/api/public/users/[username]`) returns 404. [Decision 0002](docs/decisions/0002-public-profile-fallback.md) records the workaround: project a partial profile from the embedded author of `GET /api/user/[username]/messages`. Users who have never posted publicly cannot be shown at all — they surface as `SocialError.profileUnavailable`.
- **Proposal.** `GET /api/users/[username]` (no auth required) returning:
  ```json
  {
    "id": "string",
    "username": "string",
    "displayName": "string",
    "avatar": "url or null",
    "headerImage": "url or null",
    "bio": "string or null",
    "joinedAt": "iso-8601",
    "isPrivate": false,
    "followerCount": 0,
    "followingCount": 0,
    "publicMessageCount": 0,
    "publicListCount": 0,
    "links": [{"label": "string", "url": "url"}]
  }
  ```
- **Impact.** Removes decision 0002. Profile sidebar item, follower/following counts, "no public messages yet" empty state. Unblocks the M5 Social UI getting a real header.
- **Priority.** P1.

### 1.2 — Document a watcher role enumeration on `PUT /api/lists/[id]/watchers/[userId]`

- **Problem.** The watcher PUT accepts a role, but the role taxonomy is undocumented. The macOS share-sheet UI needs a closed set to render a role picker.
- **Proposal.** Document the role enum (likely `owner | editor | viewer`?) and what each role can do (read rows / edit rows / edit schema / manage watchers / delete the list). Return `403` with `{"error":"insufficient_role"}` when a watcher attempts an action above their role.
- **Impact.** Phase 4 (M3) Lists watchers panel. We can build the picker against the assumed `owner | editor | viewer` set in the meantime, but a documented taxonomy stops UX from rotting if the set changes.
- **Priority.** P1 — blocks the M3 share-sheet design.

### 1.3 — Decide the auth requirement for `GET /api/messages` and document it definitively

- **Problem.** The 2026-06-22 unauthenticated probe showed `GET /api/messages?limit=1` returning **200** without any credentials, contradicting the API reference and our own auth matrix. Either the docs are wrong, or there is an unintended public exposure of private timeline content.
- **Proposal.** Confirm intended behavior. If public-by-design: document that `GET /api/messages` returns only public (visibility=public) messages without auth, and only personalized content with auth. If unintended: lock down and return 401.
- **Impact.** The macOS timeline currently *requires* a Bearer token. If `GET /api/messages` is genuinely public for public posts, we can offer a "browse without signing in" mode pre-onboarding — a real UX win. If unintended exposure, our code is already safe (we always send the Bearer).
- **Priority.** P1 — security/correctness clarification.

### 1.4 — Per-platform result envelope on `POST /api/messages` cross-post

- **Problem.** When a post cross-posts to Mastodon / Bluesky / LinkedIn, the create response should tell the client which platforms succeeded and which failed (with a per-platform reason). Today the docs do not specify the response envelope for `crossPostToBluesky`, `crossPostToLinkedIn`, or `mastodonProviderIds`.
- **Proposal.** Extend the `POST /api/messages` response with:
  ```json
  {
    "message": { /* the created Message */ },
    "crossPosts": [
      { "platform": "mastodon", "providerId": "...", "status": "ok", "externalUrl": "..." },
      { "platform": "bluesky", "status": "failed", "error": "rate_limited" },
      { "platform": "linkedin", "status": "pending" }
    ]
  }
  ```
- **Impact.** M6 cross-post UI. Required to render the post-publish status sheet ("Posted to Mastodon ✓ — Bluesky failed: rate limited").
- **Priority.** P1 — feature is dead-on-arrival without it.

### 1.5 — User lookup by handle for list-watcher invites

- **Problem.** The watcher PUT endpoint takes a `userId` (`PUT /api/lists/[id]/watchers/[userId]`), but there is no documented way to resolve a typed handle (e.g. `@adron`) to that user id. The native share-sheet flow needs to render "Add a user…" → type handle → autocomplete → confirm role → PUT. Without a lookup, we can only edit roles for *already-watching* users; the invite path is dead.
- **Proposal.** Either:
  - **(a)** `GET /api/users/lookup?handle=<username>` (no auth required for public profiles; require auth for private) returning `{ "id": "...", "username": "...", "displayName": "...", "avatar": "url or null", "isPrivate": bool }` &mdash; minimal projection, single-hit lookup.
  - **(b)** `GET /api/users/search?q=<prefix>&limit=10` (auth required) returning a paginated array of the same minimal projection &mdash; supports type-ahead autocomplete in the share sheet.
  Strongly prefer **(b)** for native UX; if only (a) ships, the macOS UI degrades to "type the exact handle, hit Enter to resolve."
- **Impact.** Unblocks the M3 share-sheet invite flow. Without this, the macOS client ships M3 with **role editing for existing watchers only** &mdash; new invites are deferred to a follow-up wave (tracked in `/NEXT-WORK.md`).
- **Priority.** P1 &mdash; the invite UX is core to "share a list with someone" and shipping M3 without it leaves a visible gap.

### 1.6 — Rate-limit headers on every authenticated response

- **Problem.** The 2026-06-22 probe confirmed **no** `X-RateLimit-*`, `RateLimit-*` (RFC), or `Retry-After` headers in API responses. PLAN.md §8 flagged this as a risk. The client cannot pace itself; we'll learn limits by getting 429'd in production.
- **Proposal.** Standard headers on every authenticated response:
  - `RateLimit-Limit: 100`
  - `RateLimit-Remaining: 87`
  - `RateLimit-Reset: 42` (seconds until window reset)
  - `Retry-After: 30` on 429 responses (seconds).
- **Impact.** Centralized backoff in `APIClient`. Foreground requests can degrade gracefully (timeline pagination pauses near the limit); background sync (M4 document sync) can pause proactively.
- **Priority.** P1 — required before M4 ships, because the document sync engine will be the first feature to make sustained API calls.

---

## Priority 2 — strongly desired before M4–M6 ship

### 2.1 — Confirm follower / following / mutual list envelope shape

- **Problem.** `GET /api/follow/[userId]/followers`, `…/following`, `…/mutual` — our [`FollowEndpoint`](Packages/InterlinedKit/Sources/InterlinedKit/Endpoints/FollowEndpoint.swift) currently types these as bare `[FollowUserDTO]`. Wave 1 deviation 5 records this is an assumption; the live shape is unconfirmed.
- **Proposal.** Document the envelope. Strongly prefer `{ "data": [...], "pagination": { ... } }` matching the public-messages shape (confirmed: `{ total, limit, offset, hasMore }`) so paging is uniform. Either way: document.
- **Impact.** M5 follower/following UIs. Without paging, follower lists for popular accounts break.
- **Priority.** P2.

### 2.2 — Document schema DSL field types and validation rules

- **Problem.** PLAN.md and existing endpoint docs show the schema DSL by example (`"Title:text, Year:number"`) but never enumerate the type set or per-type validation.
- **Proposal.** Document the closed set of types — for each, the JSON value shape, whether it is nullable, and what validation the server runs:
  - `text` — string, optional max length?
  - `number` — JSON number, integer or decimal?
  - `boolean` — `true | false`
  - `date` — iso-8601 string, date-only or datetime?
  - `url` — string, server-validated?
  - `email` — string, server-validated?
  - `enum(...)` — does the DSL support enumerated values?
  - `link(listSlug)` — for cross-list references; does this exist?
- **Impact.** M3 schema editor. We need to render a per-type input control (date picker for `date`, stepper for `number`, etc.) and validate before POSTing.
- **Priority.** P2 — blocks the M3 schema editor's input controls.

### 2.3a — Public list cloning endpoint

- **Problem.** The macOS "Save to my lists" hook on a public-list detail page currently degrades to *metadata-only*: it creates an empty owned list with the source's title, description, and schema string. There is no documented endpoint to clone a public list's rows into the caller's owned-lists collection in one shot, so the user has to copy rows by hand.
- **Proposal.** `POST /api/lists/clone` accepting `{ "sourceUsername": "...", "sourceSlug": "...", "asTitle": "...", "asSlug": "..." (optional), "isPublic": false }` and returning the newly created `OwnedList`. Server copies schema + every row (or returns a job id for async).
- **Impact.** Phase 4 (M3) "Save to my lists" goes from metadata-only to full row clone. Without it, the macOS UI shows an inline note explaining the limit; with it, the feature ships as users expect.
- **Priority.** P2.

### 2.3 — `lastRefreshedAt` + `refreshStatus` on GitHub-backed lists

- **Problem.** A GitHub-backed list refresh is async (`POST /api/lists/[id]/refresh`), but the list metadata returned by `GET /api/lists/[id]` doesn't expose when the last refresh happened or whether one is in progress. The macOS toolbar wants to show "Refreshed 2 min ago" and disable the button while in-flight.
- **Proposal.** Add to the List object:
  ```json
  {
    "githubSource": { "owner": "...", "repo": "...", "path": "...", "ref": "main" },
    "lastRefreshedAt": "iso-8601 or null",
    "refreshStatus": "idle | pending | failed",
    "refreshError": "string or null"
  }
  ```
- **Impact.** M3 GitHub refresh UI. Currently manual-only per the user's plan answer, but the button needs to know enough to render its own state.
- **Priority.** P2.

**Companion ask &mdash; write side.** `POST /api/lists` currently does not accept a `gitHubSource` block on create. The macOS "New List" sheet surfaces `gitHubRepository / gitHubPath / gitHubBranch` fields but cannot pass them through. To ship the create-as-GitHub-backed flow, the create endpoint needs to accept the same `gitHubSource` shape proposed above for the read side. Without it, users have to create a plain list and then configure GitHub source separately (assuming a separate endpoint exists, which is also undocumented).

### 2.4 — Typed notification kinds + payload shape

- **Problem.** `GET /api/notifications` returns a tray envelope but the per-notification `type` enum isn't documented. Native macOS notifications (UNNotificationContent) need to render type-specific copy and route to the right window on activation.
- **Proposal.** Document the closed type enum — e.g. `dig | reply | mention | follow_request | follow_accepted | list_shared | list_row_added | org_invite` — and the per-type payload shape (`targetMessageId`, `actorUserId`, etc.). Include a stable `routePath` field on each notification so the client can deep-link without parsing the type.
- **Impact.** M5 notifications tray + system notifications + deep-link routing.
- **Priority.** P2.

### 2.5 — Machine-readable upload limits

- **Problem.** PLAN.md cites 1.4 MB / 1200 px image and 3 MB video limits. These should be discoverable, not hard-coded in the client (we'll drift when limits change).
- **Proposal.** Either a `GET /api/limits` endpoint returning a single JSON object, or include the limits in the 413 / 400 error body:
  ```json
  { "error": "file_too_large", "limit": { "bytes": 1468006, "maxImagePixels": 1200 } }
  ```
- **Impact.** M6 media attachments. Pre-upload client-side resize uses the limit; post-upload error UX uses the limit in messaging.
- **Priority.** P2.

---

## Priority 3 — nice-to-have, improves polish

### 3.1 — Document version / etag on documents for conflict resolution

- **Problem.** `DocumentSyncEngine` (M4) uses a server-wins policy with local-copy preservation. To detect a conflict (rather than blind overwrite), the client needs a version or etag the server can compare against on `PATCH /api/documents/[id]`.
- **Proposal.** Add `version: int` or `etag: string` to the document object; accept `If-Match: <etag>` on PATCH and return `409 Conflict` with the current server copy when stale.
- **Impact.** M4 sync engine reliability.
- **Priority.** P3 (server-wins still works without it, just blindly).

### 3.2 — Long-lived token revocation + active-sessions list

- **Problem.** The bearer token returned by `POST /api/auth/sync-token` never expires (PLAN.md §8). If a device is lost, there is no documented way to revoke just that token.
- **Proposal.** `GET /api/user/sessions` returning active tokens with `{ id, label, createdAt, lastUsedAt, lastUsedFrom }`, and `DELETE /api/user/sessions/[id]` to revoke a specific one. Allow the client to pass a label (e.g. "MacBook Pro — Adron's Office") on sync-token request.
- **Impact.** M7 Settings → Sessions panel. Real security win for a never-expiring token model.
- **Priority.** P3.

### 3.3 — Delete/reschedule for scheduled posts before publish

- **Problem.** `GET /api/messages/scheduled` lists scheduled posts, but the docs do not show an endpoint to cancel one before its `scheduledAt` fires.
- **Proposal.** `DELETE /api/messages/[id]` already works for scheduled posts? If so, document it. `PUT /api/messages/[id]` to reschedule (move the `scheduledAt`)? If supported, document.
- **Impact.** M6 scheduled-posts UI ("Scheduled" sidebar section). Cancellation is the obvious user need.
- **Priority.** P3.

### 3.4 — Export progress / streaming for large CSVs

- **Problem.** `GET /api/exports/*` returns a CSV body. For accounts with large list-data tables, the request may take a long time and there's no progress visibility.
- **Proposal.** Either chunked transfer encoding with a documented row-count header, or a two-step async export (`POST /api/exports/lists` returning a job id; `GET /api/exports/jobs/[id]` polling status).
- **Impact.** M7 exports UX. For now, the macOS NSSavePanel-fronted export will block on the request and may visibly hang for large datasets.
- **Priority.** P3.

### 3.5 — Standardize error envelope across all 4xx

- **Problem.** The 2026-06-22 spike confirmed `{"error": "..."}` flat envelope on 404. PLAN.md and our existing code already assume this. Worth pinning so it doesn't drift.
- **Proposal.** Document: every 4xx returns `application/json` with the body `{ "error": string, "code": string? }`. 5xx may differ but should also be JSON when possible.
- **Impact.** `APIError.from(_:)` mapping stability across the project.
- **Priority.** P3 — defensive documentation.

### 3.6 — Discoverable LinkedIn cross-post readiness

- **Problem.** Spike confirmed `GET /api/auth/linkedin/status` returns `{ "configured": true, "redirectUri": "..." }` unauthenticated, which is great. We'd like an equivalent for Bluesky and Mastodon (per-instance) so the composer can disable cross-post checkboxes for unconfigured platforms before the user discovers it via failure.
- **Proposal.** `GET /api/auth/bluesky/status`, `GET /api/auth/mastodon/status?instance=mastodon.social` returning the same `{ "configured": boolean }` shape.
- **Impact.** M6 composer cross-post checkbox states.
- **Priority.** P3.

### 3.7 — Sync conflict event needs folderId

- **Problem.** `DocumentSyncEngine.events` emits `conflictResolved(original:, preservedAs:)` when the server-wins policy preserves a local copy as `<id>-localcopy-<UUID>`, but the engine does not know which folder the preserved-as document landed in. The macOS conflict-banner **"Open local copy"** action calls a refresh on the *currently loaded folder*, which silently fails when the preserved copy is in a different folder than the document the user has open. The user sees the banner action click, but nothing navigates.
- **Proposal.** Have the sync delta API (`GET /api/documents/sync` and `POST /api/documents/sync`) return `folderId` on every document — or at minimum on the preserved-copy creation events. The read side (`GET /api/documents/[id]`) already exposes `folderId`; this ask is to confirm the sync response shape includes it for both unchanged and newly-preserved documents so the engine can route the banner action across folders without a second round-trip.
- **Impact.** M4 "Open local copy" UX completes successfully across folder boundaries; the engine can either pre-load the destination folder or surface a one-click "Reveal in <Folder Name>" affordance.
- **Priority.** P3 — degrades gracefully today; the user can switch folders manually and the preserved copy is reachable from the destination folder's list.

---

## Out of scope (deliberate)

- **OpenAPI / Swagger schema endpoint.** The 2026-06-22 probe confirmed none of `/api/openapi.json`, `/api/swagger.json`, `/api/schema`, `/api/docs` exist. The macOS client doesn't *need* it — we own [api-coverage.md](docs/api-coverage.md) as our drift alarm via contract tests. Worth mentioning as a "nice but not asked for."
- **WebSocket / SSE realtime.** Not currently part of the macOS plan. Stale-while-revalidate + pull-to-refresh is sufficient for the v1.

---

## Update history

- **2026-06-22** — Initial draft. Compiled from the Wave 0.3a auth spike, the Wave 2 public-profile spike (decision 0002), the 2026-06-22 unauthenticated probe, and PLAN.md §1 / §6 / §8.
