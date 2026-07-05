# Backend Handoff Prompts — macOS Native Client Blockers

**How to use this file:** Each section below is a self-contained prompt. Copy the text under "PROMPT" and paste it directly into the InterlinedList backend Claude Code session. Each prompt is written to stand alone — the backend agent does not need to have read this file or any macOS client documentation to execute it.

Items are ordered by how hard they block the macOS client. The first five (P1-A through P1-E) directly prevent shipping features users can see. The remaining items (P2 and P3) improve quality and completeness.

**Live API base:** `https://interlinedlist.com`  
**Verified-still-blocked date:** 2026-07-04  
**macOS client repo context:** these endpoints are consumed by `Packages/InterlinedKit` (request builders + DTOs) and `Packages/InterlinedDomain` (service layer). Exact wire shapes matter — the macOS client decodes every field by name.

---

## P1 — Blocking: features cannot ship without these

---

### P1-A: User handle-to-ID lookup endpoint

**Unblocks:** NW-1 (watcher invite by handle on Lists) and NW-6 (org member-add by handle). Both features are fully built on the macOS side and waiting only on this endpoint.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to implement a user lookup endpoint that allows resolving a typed `@handle` (username) to a user record. This endpoint is needed by the macOS native client to power two features: inviting a user to watch a list by typing their handle, and adding an organization member by typing their handle.

**Build the following endpoint:**

```
GET /api/users/search?q=<prefix>&limit=10
```

Authentication: Bearer token required (the searching user must be signed in).

Request parameters:
- `q` (required) — a handle prefix or partial display name (e.g. `adro` should match `adron`, `adriana`)
- `limit` (optional, default 10, max 25) — number of results to return

Response shape (200 OK):
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

Also implement the single-hit variant for when the caller knows the exact handle:

```
GET /api/users/lookup?handle=<exact_username>
```

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

Error cases to handle:
- `q` is empty string or missing on `/search` → 400 `{"error": "missing_query"}`
- `handle` is missing on `/lookup` → 400 `{"error": "missing_handle"}`
- Unauthenticated → 401 `{"error": "unauthorized"}`

Implementation notes:
- Search should be case-insensitive
- Lookup should be exact-match, case-insensitive
- Do not expose private account email addresses or internal IDs beyond the `id` field
- For private accounts (`isPrivate: true`), still include them in results — the macOS client uses `isPrivate` to explain to the user that following requires approval

Once implemented, please verify against the live API with a curl probe and confirm both endpoints return the expected shapes.

---

### P1-B: Cross-post per-platform result envelope on POST /api/messages

**Unblocks:** NW-2 (cross-post status sheet). The macOS composer already sends cross-post targets (Mastodon provider IDs, Bluesky, LinkedIn) but cannot show the user which platforms succeeded or failed after publish.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to extend the `POST /api/messages` response to include a per-platform cross-post result envelope.

**Current behavior:**
`POST /api/messages` accepts `mastodonProviderIds: [String]`, `crossPostToBluesky: Bool`, `crossPostToLinkedIn: Bool` and succeeds/fails as a whole. The response does not indicate which cross-posts succeeded or failed individually.

**Required change:**
Add a `crossPosts` array to the `POST /api/messages` response body:

```json
{
  "id": "string",
  "content": "string",
  "createdAt": "iso-8601",
  ... (all existing message fields unchanged) ...,

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
- `platform`: one of `"mastodon"`, `"bluesky"`, `"linkedin"`
- `providerId`: the Mastodon instance/provider ID (only present for `"mastodon"`)
- `status`: one of `"ok"`, `"failed"`, `"pending"` — `"pending"` means the cross-post is enqueued but not yet confirmed
- `externalUrl`: the URL of the cross-posted content on the external platform (only present when `status = "ok"`)
- `error`: a machine-readable error code (only present when `status = "failed"`). Suggested codes: `"rate_limited"`, `"auth_expired"`, `"account_not_configured"`, `"content_too_long"`, `"network_error"`, `"unknown"`

When no cross-post targets are requested, `crossPosts` should be an empty array `[]`, not `null`.

Backward compatibility: this is an additive field. Existing clients that ignore unknown fields will be unaffected.

Please verify the change by posting a test message with cross-post targets enabled and confirming the response includes the `crossPosts` array with the correct structure.

---

### P1-C: Scheduled post cancel and reschedule

**Unblocks:** NW-3. The macOS Scheduled sidebar section lists scheduled posts but cannot cancel or reschedule one because the behavior of `DELETE` and `PUT` on a scheduled (not-yet-published) post is undocumented.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to document and confirm (or implement) cancel and reschedule behavior for scheduled posts.

**Context:**
The macOS client posts messages with a `scheduledAt` ISO-8601 timestamp. These appear in `GET /api/messages/scheduled`. The client needs to be able to:
1. Cancel a scheduled post before it publishes (delete it)
2. Change the `scheduledAt` time on a scheduled post (reschedule it)

**Question 1 — Cancel:**
Does `DELETE /api/messages/[id]` work on a scheduled post that has not yet published?

Please probe `DELETE /api/messages/[id]` against a scheduled post ID and confirm:
- Does it return 200/204 and remove the post from `GET /api/messages/scheduled`?
- Or does it return a different status code?

If `DELETE` does not work for scheduled posts, implement the behavior: allow `DELETE /api/messages/[id]` to cancel (delete) a not-yet-published scheduled post.

**Question 2 — Reschedule:**
Does `PUT /api/messages/[id]` or `PATCH /api/messages/[id]` accept an updated `scheduledAt` timestamp on a not-yet-published scheduled post?

Please probe `PUT /api/messages/[id]` with `{"scheduledAt": "<new iso-8601 timestamp>"}` against a scheduled post and confirm:
- Does it update the scheduled time and return the updated message?
- Or does it return a different status code?

If `PUT`/`PATCH` does not support rescheduling, implement the behavior: allow updating `scheduledAt` on a not-yet-published scheduled post.

**Expected final state after your changes:**

`DELETE /api/messages/[id]` on a scheduled post:
- 200 or 204 → post is removed from `GET /api/messages/scheduled`
- 404 → post does not exist
- 403 → caller does not own the post

`PUT /api/messages/[id]` on a scheduled post with `{"scheduledAt": "iso-8601"}`:
- 200 → returns the updated message with the new `scheduledAt`
- 400 → `scheduledAt` is in the past or invalid format
- 403 → caller does not own the post

Please document the confirmed behavior and verify with curl probes.

---

### P1-D: Bluesky and Mastodon cross-post readiness status endpoints

**Unblocks:** NW-4. The macOS composer can already check LinkedIn readiness via `GET /api/auth/linkedin/status`, but the equivalent endpoints for Bluesky and Mastodon return 404.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to implement status endpoints for Bluesky and Mastodon that mirror the existing `GET /api/auth/linkedin/status` endpoint.

**Existing endpoint (already works):**
```
GET /api/auth/linkedin/status
Response: { "configured": true, "redirectUri": "https://..." }
```

**Implement the following two endpoints:**

```
GET /api/auth/bluesky/status
```

Authentication: Bearer token required (checks whether the authenticated user has a Bluesky account configured).

Response (200 OK):
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

Query parameter:
- `instance` (required) — the Mastodon instance hostname to check against (e.g. `mastodon.social`, `fosstodon.org`)

Response (200 OK):
```json
{ "configured": true }
```
or
```json
{ "configured": false }
```

Response when `instance` is missing:
- 400 `{"error": "missing_instance"}`

These endpoints are called by the macOS composer when the user enables a cross-post toggle. If `configured: false`, the macOS UI disables the toggle and shows a "not configured" hint rather than letting the user discover the failure after posting.

Please verify both endpoints work by probing them with a valid Bearer token and confirming the response shape.

---

### P1-E: Native OAuth identity-linking — callback contract decision

**Unblocks:** NW-5. The macOS Settings → Linked Accounts pane currently opens the browser for OAuth (fallback Decision 0006). Native in-app linking via `ASWebAuthenticationSession` is designed and ready to implement — but requires a backend change to the callback contract.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to implement one of two options to enable native in-app OAuth identity linking for the macOS client. Currently, the macOS app opens the browser to complete OAuth account linking because the backend does not provide a native-compatible callback path.

**The problem:**
`GET /api/auth/{provider}/authorize?link=true` returns a 307 redirect to a web callback URL on `interlinedlist.com`. The `redirect_uri` is a web URL, not a custom scheme or universal link. The flow is cookie-bound (uses the web session, not the Bearer token). This means `ASWebAuthenticationSession` (the macOS native OAuth completion mechanism) cannot intercept the callback and exchange the code — it has nothing to handle.

**Choose one of the following options and implement it:**

**Option A (preferred) — Custom URL scheme callback:**

Register a custom URL scheme for the InterlinedList macOS app: `interlinedlist://oauth/callback`.

Change `GET /api/auth/{provider}/authorize?link=true` to accept an optional `redirect_uri` query parameter. When the macOS client passes `redirect_uri=interlinedlist%3A%2F%2Foauth%2Fcallback`, the server redirects to that URI after authorization with the one-time `code` and `state` parameters appended:

```
interlinedlist://oauth/callback?code=<one-time-code>&state=<original-state>&provider=github
```

The macOS app registers this scheme in its `Info.plist`, intercepts the redirect via `ASWebAuthenticationSession`, extracts `code` + `provider`, and calls a new endpoint:

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

Implement:
```
POST /api/auth/{provider}/link
Authorization: Bearer <token>
Content-Type: application/json
{ "providerToken": "<access token from provider>", "instance": "mastodon.social" (Mastodon only) }
```

The macOS app obtains the provider access token via `ASWebAuthenticationSession` directly against the provider (GitHub, Bluesky, LinkedIn, Mastodon) and exchanges it here. The server ties the provider identity to the Bearer-token user.

Response (200 OK): same shape as Option A.

**Either option unblocks the macOS implementation.** Option A is preferred because it keeps the auth flow server-controlled (the server still manages the OAuth state); Option B requires the macOS app to implement the provider OAuth dance independently.

Please implement your chosen option and document:
1. The updated `GET /api/auth/{provider}/authorize?link=true` behavior (Option A) or the new `POST /api/auth/{provider}/link` shape (Option B)
2. Which providers are supported: GitHub, Mastodon (with `instance` param), Bluesky, LinkedIn
3. Error responses: `409 Conflict` if the identity is already linked, `400` for invalid code/token

---

## P2 — Strongly desired: these improve user-facing quality meaningfully

---

### P2-A: Public profile endpoint

**Unblocks:** Proper user profile pages. Currently, the macOS client builds a profile from the embedded author of the user's most recent public message — users who have never posted publicly cannot be shown at all.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to implement a public user profile read endpoint.

**Problem:**
There is currently no `GET /api/users/[username]` endpoint. The macOS client works around this by reading the embedded author from `GET /api/user/[username]/messages`, which means users who have never posted publicly cannot have a profile displayed.

**Implement:**
```
GET /api/users/[username]
```

Authentication: optional — public profiles are visible without auth; private profile metadata (bio, links) may be partially hidden without auth.

Response (200 OK):
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
  "publicListCount": 0
}
```

Response (404):
```json
{ "error": "user_not_found" }
```

For private accounts (`isPrivate: true`): still return the endpoint with counts and display name, but omit `bio` and any personal links for unauthenticated callers. Authenticated callers who follow the private account see the full profile.

This endpoint supersedes the macOS client's current workaround (Decision 0002 in the macOS repo). Once it exists, the client will stop depending on message-embedded author data for profile display and will be able to show profiles for all users, including those who haven't posted publicly.

---

### P2-B: Follow action should return the resulting relationship

**Improves:** Follow/unfollow UX. Currently, the macOS app makes two network calls for every follow action: one to `POST /api/follow/[userId]` and a second to `GET /api/follow/[userId]/status` to learn whether the result is "now following" or "request pending." This round-trip is wasted latency.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to extend the `POST /api/follow/[userId]` response to include the resulting follow relationship so the macOS client does not need a follow-up read to determine the outcome.

**Current behavior:**
`POST /api/follow/[userId]` returns a small `{ success, message }` or similar envelope that does not distinguish between:
- "You are now following this user" (public account → immediate follow)
- "Your follow request has been sent" (private account → pending approval)

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

Field definitions (same shape as `GET /api/follow/[userId]/status`):
- `following`: true if the caller now follows the target user
- `pendingRequest`: true if the follow request is pending approval (private account)
- `followedBy`: true if the target user follows the caller (unchanged by this action, but useful context)

Apply the same change to `DELETE /api/follow/[userId]` (unfollow) and `POST /api/follow/[userId]/approve` / `reject`:

`DELETE /api/follow/[userId]`:
```json
{ "relationship": { "following": false, "pendingRequest": false, "followedBy": false } }
```

`POST /api/follow/[userId]/approve`:
```json
{ "relationship": { "following": true, "pendingRequest": false, "followedBy": true } }
```

This is a purely additive change — existing clients that don't read `relationship` are unaffected. The macOS client will stop issuing the follow-up `GET /api/follow/[userId]/status` call once this ships.

---

### P2-C: Typed notification kinds and route path

**Improves:** Notification deep-linking. The macOS client can type-safe render per-notification copy and icon, but deep-linking (tapping a system notification → navigating to the relevant content) requires a stable `routePath` field.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to document and stabilize the notification `type` field returned by `GET /api/notifications`, and add a `routePath` field that the macOS client can use for deep-link navigation.

**Current state:**
`GET /api/notifications` returns a tray envelope. The per-notification `type` field exists but is undocumented. The macOS client has assumed the following type values based on observed data:
`dig`, `reply`, `mention`, `follow_request`, `follow_accepted`, `list_shared`, `list_row_added`, `org_invite`

**Required changes:**

1. **Document the closed type enum.** Confirm or correct the assumed list above. If new types are added in the future, the macOS client uses an `.other(String)` fallback to handle them without crashing.

2. **Add a `routePath` field to each notification object:**

```json
{
  "id": "string",
  "type": "reply",
  "actor": { "id": "...", "username": "...", "displayName": "...", "avatar": "url or null" },
  "createdAt": "iso-8601",
  "read": false,
  "routePath": "/messages/abc123",
  "target": {
    "messageId": "abc123",
    "listId": null,
    "orgId": null
  }
}
```

`routePath` should be a path relative to `interlinedlist.com` that navigates to the content referenced by the notification. Examples:
- `dig` or `reply` on a message → `/messages/[messageId]`
- `follow_request` → `/profile/[actorUsername]`
- `follow_accepted` → `/profile/[actorUsername]`
- `list_shared` → `/lists/[listSlug]`
- `org_invite` → `/organizations/[orgId]`

The macOS client translates `routePath` to the appropriate in-app navigation target (message detail, profile, list detail, org detail) so the user lands in the right place when tapping a system notification banner.

This is an additive field — existing clients that don't read `routePath` are unaffected.

---

### P2-D: Machine-readable upload limits

**Improves:** Media attachment reliability. The macOS client currently hard-codes image and video upload limits. When the backend changes its limits, the client breaks silently.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to make the media upload limits machine-readable so the macOS client can discover them rather than hard-coding them.

**Current state:**
The macOS client hard-codes:
- Image upload limit: 1.4 MB / 1200 px max dimension
- Video upload limit: 3 MB

These constants are tagged `TODO(backend ask P2.5)` in the macOS source and will be replaced once this endpoint exists.

**Option A (preferred) — Limits endpoint:**

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

**Option B (alternative) — Include limits in error responses:**

When `POST /api/messages/images/upload` or `POST /api/messages/videos/upload` returns 413 (too large) or 400 (invalid format), include the limit in the error body:

```json
{
  "error": "file_too_large",
  "limit": { "maxBytes": 1468006, "maxPixels": 1200 }
}
```

Option A is preferred because it lets the macOS `ImagePrep` pipeline discover limits at startup and resize proactively before the upload attempt rather than only on failure.

---

### P2-E: Website pages for Privacy Policy and Support URL

**Unblocks:** Mac App Store submission. Apple requires a publicly accessible Privacy Policy URL and Support URL before the App Store Connect submission form can be completed. These are website requirements, not API requirements, but they block the macOS App Store release.

---

**PROMPT:**

You are working on the InterlinedList website (interlinedlist.com). I need you to publish two pages that are required before the macOS app can be submitted to the Mac App Store.

**Page 1 — Privacy Policy:**

URL: `https://interlinedlist.com/privacy`

The page must be publicly accessible (no login required) and address the following points for App Store compliance:

1. What personal data is collected: email address (used for authentication), user-generated content (posts, lists, documents stored on InterlinedList servers)
2. How data is stored and protected
3. Whether data is shared with third parties: content is sent to Mastodon, Bluesky, or LinkedIn only when the user explicitly triggers a cross-post
4. User rights: users can delete their account from Settings → Account within the macOS app (or the web app), which permanently removes their data
5. Contact information for privacy inquiries (an email address)
6. The policy's effective date

**Page 2 — Support:**

URL: `https://interlinedlist.com/support`

The page must be publicly accessible and provide at minimum:
- A way to contact support (email address, contact form, or link to a help forum)
- Links to any existing help documentation
- Information about how to report bugs or request features

Both URLs are entered directly into App Store Connect during the macOS app submission. Apple checks that these pages are publicly accessible. They do not need to be elaborate — a simple page for each is sufficient to satisfy App Store requirements.

---

## P3 — Polish: these complete partial features and improve robustness

---

### P3-A: Document version / ETag for sync conflict detection

**Improves:** Document sync reliability. Currently `DocumentSyncEngine` uses server-wins conflict resolution because it cannot detect true conflicts (no version field to compare).

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to add versioning support to the documents API so the macOS sync engine can detect true conflicts rather than blindly applying server-wins resolution.

**Current state:**
`PATCH /api/documents/[id]` accepts a document update but does not support conditional updates. The macOS `DocumentSyncEngine` cannot tell whether a rejected update was a conflict (both sides edited) or a normal write. It defaults to server-wins + local copy preservation on every disagreement, which means the user sees false conflicts.

**Required changes:**

1. Add `version: int` (or `etag: string`) to the document object returned by all read endpoints (`GET /api/documents`, `GET /api/documents/[id]`, `GET /api/documents/sync`).

2. Accept `If-Match: <etag>` (or `X-Document-Version: <version>`) on `PATCH /api/documents/[id]`. When the header is present and the version does not match the current server version, return:
   ```
   409 Conflict
   { "error": "version_conflict", "currentVersion": 42, "serverDocument": { /* current server document */ } }
   ```
   When the header is absent, proceed with the existing server-wins behavior (no breaking change for clients that don't send the header).

3. Increment `version` on every successful `PATCH`.

The macOS sync engine will use this to implement optimistic concurrency: send the last-known `version` in `If-Match`, treat 409 as a genuine conflict that warrants the local-copy preservation, and treat 200 as a clean write (no conflict).

---

### P3-B: Sync conflict event should include folderId of the preserved copy

**Improves:** "Open local copy" UX after a document sync conflict. Currently the conflict banner's action silently fails when the preserved copy is in a different folder than the one the user has open.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to confirm that the document sync API (`GET /api/documents/sync` and `POST /api/documents/sync`) includes `folderId` on every document in the sync response, including on newly-created preserved-copy documents.

**Context:**
When the macOS `DocumentSyncEngine` detects a conflict, it preserves the local edit as a new document named `<original-id>-localcopy-<UUID>`. The sync engine emits a `conflictResolved` event so the macOS UI can show a banner: "This document was updated on another device. Your local changes were preserved." The banner has an "Open local copy" button.

The problem: the sync response does not reliably include `folderId` for the newly-preserved copy document. When the preserved copy lands in a different folder than the original (because the server version moved the document), the "Open local copy" action calls a folder refresh on the currently-open folder and finds nothing — the banner click silently fails.

**Please confirm (or implement) the following:**

`GET /api/documents/sync` and `POST /api/documents/sync` must include `folderId` on every document entry in the response, including:
- Existing unchanged documents
- Modified documents
- Newly-created documents (including preserved-copy documents created during conflict resolution)
- Deleted documents (include `folderId` of the folder the document was in before deletion)

If `folderId` is already present on all sync response documents, please confirm this in a curl probe against the live endpoint and document the field name. If it is missing from any case, please add it.

---

### P3-C: Scheduled post list and GitHub-backed list refresh metadata

**Improves:** GitHub-backed list toolbar state and scheduled post list header.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need two additions to the list API to improve the macOS toolbar and header display.

**Addition 1 — Last-refreshed metadata on GitHub-backed lists:**

Add the following fields to the List object returned by `GET /api/lists/[id]` and `GET /api/lists` when the list has a `githubSource`:

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

`refreshStatus` values: `"idle"` (no refresh in progress), `"pending"` (refresh triggered, waiting for GitHub), `"failed"` (last refresh attempt failed).

The macOS toolbar uses `refreshStatus` to disable the Refresh button while a refresh is in-flight, and shows `lastRefreshedAt` as "Refreshed 2 min ago" text below the list title.

**Addition 2 — Accept `githubSource` on `POST /api/lists` (create):**

The macOS "New List" sheet surfaces fields for GitHub repository, path, and branch. Currently `POST /api/lists` ignores these if passed. Add support for creating a GitHub-backed list in one call:

```json
{
  "title": "My GitHub-backed list",
  "description": "optional",
  "schema": "Name:text, Stars:number",
  "isPublic": false,
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

### P3-D: Bearer token revocation and active sessions list

**Improves:** Security. The Bearer token returned by `POST /api/auth/sync-token` never expires. If a device is lost, there is no way to revoke just that device's token.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to implement Bearer token revocation and an active sessions list so users can manage which devices have access to their account.

**The problem:**
`POST /api/auth/sync-token` returns a Bearer token that never expires. There is no documented way to revoke a specific device's token. A lost or compromised device has permanent access until the user changes their password.

**Implement the following:**

**Allow passing a device label on token creation:**
```
POST /api/auth/sync-token
{ "email": "...", "password": "...", "deviceLabel": "MacBook Pro — Adron's Office" }
```

The `deviceLabel` is optional but stored alongside the token for display in the sessions list.

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

Response: 204 No Content (the session is revoked; its token becomes invalid immediately).

A session cannot revoke itself (the current session's own ID): return 400 `{"error": "cannot_revoke_current_session"}` — the user must use "Sign out" instead.

The macOS client will surface this in Settings → Sessions as a list of active devices with a "Revoke access" button on each non-current session.

---

### P3-E: Rate-limit headers on API responses

**Improves:** Client-side API health. The macOS `DocumentSyncEngine` makes sustained API calls during background sync. Without rate-limit headers, the client learns its limits only by hitting 429 errors.

---

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to add rate-limit headers to authenticated API responses so the macOS client can pace its requests proactively.

**Add the following headers to every authenticated response:**

```
RateLimit-Limit: 100
RateLimit-Remaining: 87
RateLimit-Reset: 42
```

- `RateLimit-Limit`: the request limit for the current window
- `RateLimit-Remaining`: requests remaining in the current window
- `RateLimit-Reset`: seconds until the current window resets

On 429 responses, add:
```
Retry-After: 30
```

- `Retry-After`: seconds the client should wait before retrying

These follow RFC 6585 (`Retry-After`) and the draft IETF RateLimit header fields spec.

**Why this matters for the macOS client:**

The `DocumentSyncEngine` runs pull-delta → push-change cycles. When the user has many document edits queued in the outbox, it issues one `POST /api/documents/sync` per batch. Without `RateLimit-Remaining`, the sync engine has no way to slow down before hitting a 429 — it discovers the limit reactively, which means one batch fails and the user sees a sync error. With the headers, the engine can pause proactively when `RateLimit-Remaining` drops below a threshold and resume after `RateLimit-Reset` seconds.

---

## Summary table

| ID | What to build | Unblocks | Priority |
|----|--------------|---------|----------|
| P1-A | `GET /api/users/search` + `GET /api/users/lookup?handle=` | NW-1 watcher invite, NW-6 org member add | **P1** |
| P1-B | `POST /api/messages` cross-post result envelope | NW-2 cross-post status sheet | **P1** |
| P1-C | Confirm/implement `DELETE` + `PUT` on scheduled posts | NW-3 scheduled post cancel/reschedule | **P1** |
| P1-D | `GET /api/auth/bluesky/status` + `GET /api/auth/mastodon/status` | NW-4 cross-post readiness | **P1** |
| P1-E | OAuth native callback (custom scheme or bearer link) | NW-5 native in-app account linking | **P1** |
| P2-A | `GET /api/users/[username]` public profile | Full user profiles | P2 |
| P2-B | Follow action response includes resulting relationship | Eliminates follow-then-status round-trip | P2 |
| P2-C | Notification `type` enum + `routePath` field | Notification deep-linking | P2 |
| P2-D | `GET /api/limits` or limits in error responses | Media upload reliability | P2 |
| P2-E | Publish `interlinedlist.com/privacy` + `/support` | Mac App Store submission | P2 |
| P3-A | `version`/`etag` on documents + `If-Match` on PATCH | True conflict detection in sync | P3 |
| P3-B | `folderId` on sync response documents | "Open local copy" cross-folder navigation | P3 |
| P3-C | `lastRefreshedAt` + `refreshStatus` on lists + create with `githubSource` | GitHub list toolbar state | P3 |
| P3-D | Token revocation + `GET /api/user/sessions` + `DELETE /api/user/sessions/[id]` | Security: device management | P3 |
| P3-E | `RateLimit-*` headers on authenticated responses | Sync engine proactive pacing | P3 |
