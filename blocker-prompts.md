# InterlinedList — Backend Blocker Prompts

**Purpose:** Single source of truth for all macOS-client-facing backend gaps. Each open item has a self-contained prompt ready to paste into the InterlinedList backend Claude Code session. Items are ordered by how hard they block the macOS client.

**Live API base:** `https://interlinedlist.com`  
**Last probed:** 2026-07-07  
**macOS client context:** Endpoints are consumed by `Packages/InterlinedKit` (request builders + DTOs) and `Packages/InterlinedDomain` (service layer). Wire shapes matter — the macOS client decodes every field by name.

---

## Status Summary

| ID | Item | Status |
|----|------|--------|
| P1-A | `GET /api/users/search` + `/api/users/lookup` | 🟡 Endpoints exist (401, not 404) — shape unverified |
| P1-B | `POST /api/messages` cross-post result envelope | ❌ Open |
| P1-C | `DELETE` + `PUT` on scheduled posts | ❌ Open |
| P1-D | `GET /api/auth/bluesky/status` + `mastodon/status` | ❌ Open |
| P1-E | OAuth native callback contract | ❌ Open |
| P1-F | Auth decision on `GET /api/messages` | ❌ Open — still 200 unauthenticated |
| P2-A | `GET /api/users/[username]` public profile | ✅ Resolved 2026-07-07 |
| P2-B | Follow action returns resulting relationship | ❌ Open |
| P2-C | Notification `type` enum + `routePath` | ❌ Open |
| P2-D | Machine-readable upload limits | ❌ Open |
| P2-E | Privacy Policy + Support pages | ❌ Open |
| P3-A | Document `version`/`etag` + `If-Match` on PATCH | ❌ Open |
| P3-B | `folderId` on sync response documents | ❌ Open |
| P3-C | GitHub-backed list refresh metadata | ❌ Open |
| P3-D | Token revocation + sessions list | ❌ Open |
| P3-E | `RateLimit-*` headers — re-probed 2026-07-07 | ❌ Still absent |

---

## Resolved

### P2-A — `GET /api/users/[username]` public profile ✅ Resolved 2026-07-07

**Verified live response (adron):**
```json
{"id":"c65092fa-a967-4385-92e6-ef4bc9239a3c","username":"adron","displayName":"Adron Hall",
 "avatar":"https://…","headerImage":null,"bio":"…","joinedAt":"2026-01-05T04:28:13.570Z",
 "isPrivate":false,"followerCount":6,"followingCount":11,"publicMessageCount":152,"publicListCount":9}
```

**Remaining minor gap:** The `links` array (user-defined profile links) from the original proposal is absent. Either add it or confirm it is out of scope.

**macOS impact:** Decision 0002 (project profile from embedded message author) can now be removed. `SocialError.profileUnavailable` for users who have never posted publicly is no longer needed.

---

## P1 — Blocking: features cannot ship without these

---

### P1-A — User handle-to-ID lookup

**Status:** 🟡 Both `/api/users/lookup` and `/api/users/search` matched routes as of 2026-07-07 (returns 401 with auth, not 404). Need a real Bearer token to verify the response shape is correct.

**Unblocks:** NW-1 (watcher invite by handle on Lists) and NW-6 (org member-add by handle). Both features are fully built on the macOS side and waiting only on this endpoint.

**Background:** The watcher `PUT /api/lists/[id]/watchers/[userId]` takes a `userId`, but there is no documented way to resolve a typed `@handle` to that ID. Without lookup, the macOS share-sheet can only edit roles for already-watching users — the invite path is dead.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). Two user-lookup endpoints have been observed at `/api/users/lookup` and `/api/users/search` — both return 401 when probed without auth, confirming they exist. I need you to verify that these endpoints are complete and return the correct response shape, then document any deviations.

**Expected shape for `GET /api/users/search?q=<prefix>&limit=10`:**

Authentication: Bearer token required.

Request parameters:
- `q` (required) — handle prefix or partial display name; case-insensitive
- `limit` (optional, default 10, max 25)

Response (200 OK):
```json
{
  "users": [
    {
      "id": "string",
      "username": "string",
      "displayName": "string",
      "avatar": "url or null",
      "isPrivate": false
    }
  ],
  "total": 12
}
```

**Expected shape for `GET /api/users/lookup?handle=<exact_username>`:**

Authentication: Bearer token required.

Response (200 OK — user found):
```json
{
  "id": "string",
  "username": "string",
  "displayName": "string",
  "avatar": "url or null",
  "isPrivate": false
}
```

Response (404 — no user with that exact handle):
```json
{ "error": "user_not_found" }
```

Error cases to confirm:
- `q` missing on `/search` → 400 `{"error": "missing_query"}`
- `handle` missing on `/lookup` → 400 `{"error": "missing_handle"}`
- Unauthenticated → 401 `{"error": "unauthorized"}`

Implementation requirements:
- Search is case-insensitive prefix match
- Lookup is exact-match, case-insensitive
- Private accounts appear in results with `isPrivate: true`
- No private fields (email, internal tokens) exposed

Probe both endpoints with a valid Bearer token, confirm the response shapes, and fix any deviations from the expected shapes above.

---

### P1-B — Cross-post per-platform result envelope on `POST /api/messages`

**Unblocks:** NW-2 (cross-post status sheet). The macOS composer sends cross-post targets but cannot show which platforms succeeded or failed after publish.

**Background:** `POST /api/messages` accepts `mastodonProviderIds`, `crossPostToBluesky`, `crossPostToLinkedIn` but the response does not indicate per-platform outcome.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to extend the `POST /api/messages` response to include a per-platform cross-post result envelope.

**Current behavior:**
`POST /api/messages` accepts cross-post targets and succeeds or fails as a whole. The response does not indicate which cross-posts succeeded or failed individually.

**Required change:**
Add a `crossPosts` array to the `POST /api/messages` response body:

```json
{
  "id": "string",
  "content": "string",
  "createdAt": "iso-8601",
  "crossPosts": [
    {
      "platform": "mastodon",
      "providerId": "mastodon.social",
      "status": "ok",
      "externalUrl": "https://mastodon.social/@user/123456789"
    },
    {
      "platform": "bluesky",
      "status": "failed",
      "error": "rate_limited"
    },
    {
      "platform": "linkedin",
      "status": "pending"
    }
  ]
}
```

Field definitions:
- `platform`: one of `"mastodon"`, `"bluesky"`, `"linkedin"`, `"twitter"`
- `providerId`: Mastodon instance/provider ID (only for `"mastodon"`)
- `status`: one of `"ok"`, `"failed"`, `"pending"`
- `externalUrl`: URL of the post on the external platform (only when `status = "ok"`)
- `error`: machine-readable code (only when `status = "failed"`). Codes: `"rate_limited"`, `"auth_expired"`, `"account_not_configured"`, `"content_too_long"`, `"network_error"`, `"unknown"`

When no cross-post targets are requested, `crossPosts` must be `[]`, not `null`.

This is an additive field — existing clients that ignore unknown JSON fields are unaffected.

Verify by posting a test message with cross-post targets and confirming the response includes the `crossPosts` array with the correct structure.

---

### P1-C — Scheduled post cancel and reschedule

**Unblocks:** NW-3. The macOS Scheduled sidebar lists scheduled posts but cannot cancel or reschedule one — behavior of `DELETE` and `PUT` on a not-yet-published scheduled post is undocumented.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to confirm (or implement) cancel and reschedule behavior for scheduled posts.

**Context:**
The macOS client posts with a `scheduledAt` ISO-8601 timestamp. These appear in `GET /api/messages/scheduled`. Users need to cancel or reschedule before the post fires.

**Required behavior:**

`DELETE /api/messages/[id]` on a not-yet-published scheduled post:
- 200 or 204 → post removed from `GET /api/messages/scheduled`
- 404 → post does not exist
- 403 → caller does not own the post

`PUT /api/messages/[id]` on a not-yet-published scheduled post with `{"scheduledAt": "iso-8601"}`:
- 200 → returns updated message with new `scheduledAt`
- 400 → `scheduledAt` is in the past or invalid format: `{"error": "invalid_scheduled_at"}`
- 403 → caller does not own the post

Please probe `DELETE` and `PUT` against a scheduled post ID, document the current behavior, and implement the expected behavior if it is not already present.

---

### P1-D — Bluesky and Mastodon cross-post readiness status endpoints

**Unblocks:** NW-4. The macOS composer already checks LinkedIn readiness via `GET /api/auth/linkedin/status`. The equivalent endpoints for Bluesky and Mastodon return 404.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to implement status endpoints for Bluesky and Mastodon that mirror the existing `GET /api/auth/linkedin/status` endpoint.

**Existing endpoint (reference, already works):**
```
GET /api/auth/linkedin/status
Response: { "configured": true, "redirectUri": "https://..." }
```

**Implement:**

```
GET /api/auth/bluesky/status
```
Authentication: Bearer token required.
Response:
```json
{ "configured": true }
```
or
```json
{ "configured": false }
```

```
GET /api/auth/mastodon/status?instance=mastodon.social
```
Authentication: Bearer token required.
Query parameter: `instance` (required) — Mastodon instance hostname.
Response: same `{ "configured": bool }` shape.
Error when `instance` missing: 400 `{"error": "missing_instance"}`.

These are called by the macOS composer when the user enables a cross-post toggle. If `configured: false`, the UI disables the toggle and shows a "not configured" hint rather than surfacing a failure after posting.

Verify both endpoints with a valid Bearer token and confirm the response shape.

---

### P1-E — Native OAuth identity-linking callback contract

**Unblocks:** NW-5. The macOS Settings → Linked Accounts currently opens the browser as a fallback (Decision 0006). Native in-app linking via `ASWebAuthenticationSession` is designed and ready to implement — but requires a backend change.

**Background:** `GET /api/auth/{provider}/authorize?link=true` redirects to a web callback URL. The `redirect_uri` is a web URL (not a custom scheme), and the flow is cookie-bound rather than Bearer-bound. `ASWebAuthenticationSession` cannot intercept the callback — it has nothing to handle.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to implement one of two options to enable native in-app OAuth identity linking for the macOS client.

**Option A (preferred) — Custom URL scheme callback:**

Register `interlinedlist://oauth/callback` as an accepted `redirect_uri`.

When the macOS client passes `redirect_uri=interlinedlist%3A%2F%2Foauth%2Fcallback` to `GET /api/auth/{provider}/authorize?link=true`, redirect to:
```
interlinedlist://oauth/callback?code=<one-time-code>&state=<original-state>&provider=github
```

The macOS app intercepts this via `ASWebAuthenticationSession`, then calls:
```
POST /api/auth/{provider}/link
Authorization: Bearer <token>
Content-Type: application/json
{ "code": "<one-time code>", "state": "<original state>" }
```

Response (200 OK):
```json
{
  "provider": "github",
  "providerUserId": "string",
  "username": "string",
  "linkedAt": "iso-8601"
}
```

**Option B (alternative) — Bearer-authenticated link endpoint:**

```
POST /api/auth/{provider}/link
Authorization: Bearer <token>
Content-Type: application/json
{ "providerToken": "<access token from provider>", "instance": "mastodon.social" (Mastodon only) }
```

The macOS app obtains the provider token via `ASWebAuthenticationSession` directly against the provider and exchanges it here.

**Either option unblocks the macOS implementation.** Option A is preferred (server stays in control of OAuth state). Please implement your chosen option and document:
1. The updated `GET /api/auth/{provider}/authorize?link=true` behavior (Option A) or the new POST shape (Option B)
2. Supported providers: GitHub, Mastodon (with `instance` param), Bluesky, LinkedIn
3. Error responses: `409 Conflict` if identity already linked, `400` for invalid code/token

---

### P1-F — Auth requirement on `GET /api/messages`

**Status:** Re-confirmed 2026-07-07 — still returns 200 unauthenticated.

**Background:** The 2026-06-22 probe first flagged this. Either the API docs are wrong, or there is unintended public exposure. The macOS client always sends a Bearer token, so it is safe either way — but the behavior needs a definitive decision.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to make a documented decision about the authentication requirement on `GET /api/messages`.

**Observed behavior (confirmed 2026-07-07):**
`GET /api/messages?limit=1` returns HTTP 200 with public message content without any `Authorization` header. This contradicts the API reference and our own auth matrix.

**Please choose one of the following and implement it:**

**Option A — Public-by-design:**
Document that `GET /api/messages` returns only `publiclyVisible: true` messages for unauthenticated requests, and returns a personalized timeline (including private content from followed accounts) for authenticated requests.

If this is the intended behavior, add the `publiclyVisible` filter to the unauthenticated path if it is not already applied, confirm it in the API docs, and update the response to make the auth-vs-no-auth distinction explicit in the docs.

**Option B — Unintended exposure, lock it down:**
Add an auth check. Return 401 with `{"error": "unauthorized"}` for requests without a valid Bearer token.

No change is required in the macOS client for either option (the client always sends the Bearer). The ask is purely for a documented, intentional decision.

---

## P2 — Strongly desired: these improve user-facing quality meaningfully

---

### P2-B — Follow action returns resulting relationship

**Improves:** Follow/unfollow UX. The macOS app currently issues two round-trips per follow action: one to `POST /api/follow/[userId]` and one to `GET /api/follow/[userId]/status` to learn whether the result is "now following" or "request pending."

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to extend `POST /api/follow/[userId]` to include the resulting follow relationship so the macOS client does not need a follow-up read.

**Required change:**
Add a `relationship` field to the response:

```json
{
  "relationship": {
    "following": false,
    "pendingRequest": true,
    "followedBy": false
  }
}
```

- `following`: true if the caller now follows the target
- `pendingRequest`: true if the follow request is pending (private account)
- `followedBy`: true if the target follows the caller (unchanged by this action)

Apply the same change to related endpoints:

`DELETE /api/follow/[userId]` (unfollow):
```json
{ "relationship": { "following": false, "pendingRequest": false, "followedBy": false } }
```

`POST /api/follow/[userId]/approve`:
```json
{ "relationship": { "following": true, "pendingRequest": false, "followedBy": true } }
```

This is additive — existing clients that don't read `relationship` are unaffected. The macOS client removes the follow-up `GET /api/follow/[userId]/status` call once this ships.

---

### P2-C — Typed notification kinds + `routePath`

**Improves:** Notification deep-linking. The macOS client can render type-safe notification copy and icon, but deep-linking (system notification tap → navigate to content) requires a stable `routePath` field.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to document and stabilize the notification `type` field from `GET /api/notifications`, and add a `routePath` field for deep-link navigation.

**Current state:**
The per-notification `type` field is undocumented. The macOS client has assumed:
`dig`, `reply`, `mention`, `follow_request`, `follow_accepted`, `list_shared`, `list_row_added`, `org_invite`

**Required changes:**

1. **Document the closed type enum.** Confirm or correct the assumed list above. New types added in the future are handled by the macOS client's `.other(String)` fallback — it will not crash on unknown values.

2. **Add `routePath` to each notification:**

```json
{
  "id": "string",
  "type": "reply",
  "actor": { "id": "...", "username": "...", "displayName": "...", "avatar": "url or null" },
  "createdAt": "iso-8601",
  "read": false,
  "routePath": "/messages/abc123",
  "target": { "messageId": "abc123", "listId": null, "orgId": null }
}
```

`routePath` — a path relative to `interlinedlist.com` for the notification's target:
- `dig` / `reply` / `mention` → `/messages/[messageId]`
- `follow_request` / `follow_accepted` → `/profile/[actorUsername]`
- `list_shared` / `list_row_added` → `/lists/[listSlug]`
- `org_invite` → `/organizations/[orgId]`

This is additive — existing clients that don't read `routePath` are unaffected.

---

### P2-D — Machine-readable upload limits

**Improves:** Media attachment reliability. The macOS client hard-codes image and video upload limits tagged `TODO(backend ask P2.5)`. When limits change server-side, the client breaks silently.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to make media upload limits machine-readable.

**Preferred option — Limits endpoint:**

```
GET /api/limits
```

Authentication: optional (limits are the same for all users).

Response (200 OK):
```json
{
  "media": {
    "image": {
      "maxBytes": 1468006,
      "maxPixels": 1200,
      "acceptedFormats": ["jpeg", "png", "gif", "webp", "heic"]
    },
    "video": {
      "maxBytes": 3145728,
      "acceptedFormats": ["mp4", "mov"]
    }
  },
  "message": {
    "maxContentLength": 5000
  }
}
```

**Alternative — Limits in error responses:**
When upload endpoints return 413 or 400:
```json
{
  "error": "file_too_large",
  "limit": { "maxBytes": 1468006, "maxPixels": 1200 }
}
```

The endpoint is preferred because `ImagePrep` discovers limits at startup and resizes proactively before the upload attempt, rather than only on failure.

---

### P2-E — Privacy Policy and Support pages

**Unblocks:** Mac App Store submission. Apple requires publicly accessible Privacy Policy and Support URLs in App Store Connect before the submission form can be completed.

---

**PROMPT:**

You are working on the InterlinedList website (interlinedlist.com). I need you to publish two pages required for Mac App Store submission.

**Page 1 — Privacy Policy: `https://interlinedlist.com/privacy`**

Must be publicly accessible (no login) and cover:
1. What personal data is collected: email address (authentication), user-generated content (posts, lists, documents stored on InterlinedList servers)
2. How data is stored and protected
3. Third-party data sharing: content is sent to Mastodon, Bluesky, LinkedIn, or Twitter only when the user explicitly cross-posts
4. User rights: users can delete their account from Settings → Account in the macOS or web app, permanently removing their data
5. Contact information for privacy inquiries (an email address)
6. The policy's effective date

**Page 2 — Support: `https://interlinedlist.com/support`**

Must be publicly accessible and provide at minimum:
- A contact method (email address, contact form, or help forum link)
- Links to existing help documentation
- How to report bugs or request features

Apple checks that these URLs are publicly accessible during submission. Simple pages for each are sufficient.

---

## P3 — Polish: these complete partial features and improve robustness

---

### P3-A — Document version / ETag for sync conflict detection

**Improves:** Document sync reliability. `DocumentSyncEngine` uses server-wins because it cannot detect true conflicts (no version field to compare).

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to add versioning to the documents API so the macOS sync engine can detect true conflicts.

**Required changes:**

1. Add `version: int` (or `etag: string`) to the document object returned by all read endpoints (`GET /api/documents`, `GET /api/documents/[id]`, `GET /api/documents/sync`).

2. Accept `If-Match: <etag>` (or `X-Document-Version: <version>`) on `PATCH /api/documents/[id]`. When the header is present and the version does not match:
   ```
   409 Conflict
   { "error": "version_conflict", "currentVersion": 42, "serverDocument": { /* current */ } }
   ```
   When the header is absent, use existing server-wins behavior (no breaking change).

3. Increment `version` on every successful `PATCH`.

The macOS sync engine will send the last-known `version` in `If-Match`, treat 409 as a genuine conflict (triggering local-copy preservation), and treat 200 as a clean write.

---

### P3-B — `folderId` on sync response documents

**Improves:** "Open local copy" UX. The conflict banner's action silently fails when the preserved copy is in a different folder than the one the user has open.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to confirm that `GET /api/documents/sync` and `POST /api/documents/sync` include `folderId` on every document in the sync response.

**Context:**
When `DocumentSyncEngine` resolves a conflict, it preserves the local edit as `<id>-localcopy-<UUID>` and emits a `conflictResolved` event so the macOS UI shows an "Open local copy" banner. The action fails silently when the preserved copy is in a different folder than the user's current view.

**Confirm (or implement):**
`folderId` must be present on every document entry in sync responses, including:
- Unchanged documents
- Modified documents
- Newly-created documents (including preserved-copy documents from conflict resolution)
- Deleted documents (include the `folderId` of the folder the document was in before deletion)

If `folderId` is already present on all sync response documents, confirm this with a curl probe and document the field name. If it is missing from any case, add it.

---

### P3-C — GitHub-backed list refresh metadata

**Improves:** GitHub-backed list toolbar state. The macOS toolbar wants to show "Refreshed 2 min ago" and disable the refresh button while a refresh is in-flight.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need two additions to the list API for the macOS toolbar.

**Addition 1 — Refresh metadata on GitHub-backed lists:**

Add to the List object returned by `GET /api/lists/[id]` and `GET /api/lists` when `githubSource` is present:

```json
{
  "githubSource": {
    "owner": "string",
    "repo": "string",
    "path": "string",
    "ref": "main"
  },
  "lastRefreshedAt": "iso-8601 or null",
  "refreshStatus": "idle",
  "refreshError": "string or null"
}
```

`refreshStatus` values: `"idle"` (no refresh in progress), `"pending"` (waiting for GitHub), `"failed"` (last refresh attempt failed).

**Addition 2 — Accept `githubSource` on `POST /api/lists`:**

The macOS "New List" sheet sends `githubRepository`, `githubPath`, `githubBranch`. Currently `POST /api/lists` ignores these. Add support:

```json
{
  "title": "My GitHub-backed list",
  "isPublic": false,
  "schema": "Name:text, Stars:number",
  "githubSource": {
    "owner": "adron",
    "repo": "my-repo",
    "path": "data/list.csv",
    "ref": "main"
  }
}
```

If `githubSource` is provided, trigger an initial refresh immediately after creation and return `refreshStatus: "pending"` in the create response.

---

### P3-D — Bearer token revocation and active sessions list

**Improves:** Security. The Bearer token from `POST /api/auth/sync-token` never expires. A lost device has permanent access until the user changes their password.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to implement Bearer token revocation and an active sessions list for device management.

**Allow passing a device label on token creation:**
```
POST /api/auth/sync-token
{ "email": "...", "password": "...", "deviceLabel": "MacBook Pro — Adron's Office" }
```
`deviceLabel` is optional but stored alongside the token for display in the sessions list.

**Sessions list:**
```
GET /api/user/sessions
Authorization: Bearer <token>
```
Response:
```json
{
  "sessions": [
    {
      "id": "string",
      "deviceLabel": "MacBook Pro — Adron's Office",
      "createdAt": "iso-8601",
      "lastUsedAt": "iso-8601",
      "isCurrent": true
    }
  ]
}
```

**Session revocation:**
```
DELETE /api/user/sessions/[id]
Authorization: Bearer <token>
```
Response: 204 No Content (token immediately invalid).

A session cannot revoke itself: return 400 `{"error": "cannot_revoke_current_session"}`.

The macOS client will surface this in Settings → Sessions as a list of active devices with a "Revoke access" button per non-current session.

---

### P3-E — `RateLimit-*` headers on API responses

**Status:** Re-confirmed absent 2026-07-07.

**Improves:** Client-side API health. `DocumentSyncEngine` makes sustained calls during background sync. Without rate-limit headers, the client discovers limits only via 429 errors.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to add rate-limit headers to authenticated API responses.

**Add to every authenticated response:**

```
RateLimit-Limit: 100
RateLimit-Remaining: 87
RateLimit-Reset: 42
```

- `RateLimit-Limit`: request limit for the current window
- `RateLimit-Remaining`: requests remaining in the current window
- `RateLimit-Reset`: seconds until the current window resets

**On 429 responses, add:**
```
Retry-After: 30
```

These follow RFC 6585 (`Retry-After`) and the draft IETF RateLimit header fields spec.

**Why this matters:** `DocumentSyncEngine` runs pull-delta → push-change cycles. When many document edits are queued, it issues one `POST /api/documents/sync` per batch. Without `RateLimit-Remaining`, the engine hits 429 reactively — one batch fails and the user sees a sync error. With the headers, the engine pauses proactively when `RateLimit-Remaining` drops below a threshold and resumes after `RateLimit-Reset` seconds.

---

## Change log

| Date | Change |
|------|--------|
| 2026-07-07 | Created this file, consolidating `Backend-Handoff-Prompts.md` and `API-backend-prompts-to-build.md`. Marked P2-A resolved (live probe confirmed `GET /api/users/[username]` live). Updated P1-A (lookup/search endpoints exist, 401 not 404). Confirmed P3-E (no rate-limit headers) and P1-F (auth decision still open) via live probe. Added P1-F as a named item. |
| 2026-07-04 | `Backend-Handoff-Prompts.md` authored from macOS client review. |
| 2026-06-25 | `API-backend-prompts-to-build.md` — Wave 7 additions (OAuth native linking, media limits TODOs). |
| 2026-06-24 | `API-backend-prompts-to-build.md` — follow-relationship round-trip and domain-typed follow status. |
| 2026-06-22 | `API-backend-prompts-to-build.md` — initial draft from auth spike and unauthenticated probe. |
