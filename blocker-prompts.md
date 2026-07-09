# InterlinedList — Backend Blocker Prompts

Consolidated from `API-backend-prompts-to-build.md` and `Backend-Handoff-Prompts.md`.
Last probed: 2026-07-07. Updated: 2026-07-08.

**Live API base:** `https://interlinedlist.com`  
**macOS client context:** Consumed by `Packages/InterlinedKit` (request builders + DTOs) and `Packages/InterlinedDomain` (service layer). Wire shapes matter — the macOS client decodes every field by name. Additive changes (new fields) are always safe.

**How to use:** Each open item has a self-contained prompt ready to paste into the InterlinedList backend Claude Code session.

---

## Status Summary

| ID | Item | Status |
|----|------|--------|
| P1-A | `GET /api/users/search` + `/api/users/lookup` | ✅ Resolved — endpoints live, macOS wired (NW-1, NW-6 done) |
| P1-B | `POST /api/messages` cross-post result envelope | ✅ Resolved — `crossPosts[]` in response; macOS wired (NW-2 done) |
| P1-C | `DELETE` + `PUT` on scheduled posts | ✅ Resolved — confirmed live; macOS wired (NW-3 done) |
| P1-D | `GET /api/auth/bluesky/status` + `mastodon/status` | ✅ Resolved — endpoints live; macOS wired (NW-4 done) |
| P1-E | Native OAuth callback contract | ❌ Open — browser-handoff fallback ships in M6 |
| P1-F | Auth decision on `GET /api/messages` (200 unauthenticated) | ❌ Open — decision + docs still pending |
| P2-A | `GET /api/users/[username]` public profile | ✅ Resolved 2026-07-07 — full shape confirmed live |
| P2-B | Follow action returns resulting relationship | 🟡 Partial — `{ follow: { status } }` decoded; `followedBy` still needs 2nd call |
| P2-C | Notification `type` enum + `routePath` field | ❌ Open |
| P2-D | Machine-readable upload limits (`GET /api/limits`) | ❌ Open — hard-coded in macOS as `TODO(backend ask P2.5)` |
| P2-E | Privacy Policy + Support pages | ❌ Open — required for App Store (B6, B7) |
| P3-A | Document `version`/`etag` + `If-Match` on PATCH | ❌ Open |
| P3-B | `folderId` on sync response documents | ❌ Open |
| P3-C | `lastRefreshedAt` + `refreshStatus` on lists + `githubSource` on POST | ❌ Open |
| P3-D | Token revocation + `GET /api/user/sessions` | ❌ Open |
| P3-E | `RateLimit-*` headers universally | 🟡 Partial — on 2 routes only; macOS nil-guards correctly |

---

## Resolved — no further backend action needed

- **P1-A** `GET /api/users/search?q=&limit=` and `GET /api/users/lookup?handle=` — live, Bearer-required, macOS NW-1 and NW-6 complete.
- **P1-B** `POST /api/messages` `crossPosts[]` envelope — live, `CrossPostResultDTO` decoded, NW-2 complete.
- **P1-C** `DELETE /api/messages/[id]` and `PUT /api/messages/[id]` on scheduled posts — confirmed working, NW-3 complete.
- **P1-D** `GET /api/auth/bluesky/status` and `GET /api/auth/mastodon/status?instance=` — live, NW-4 complete.
- **P2-A** `GET /api/users/[username]` — live 2026-07-07, full profile shape confirmed, Decision 0002 workaround removed from macOS.

---

## Open — P1 (blocking)

### P1-E — Native OAuth identity-linking callback

**Unblocks:** NW-5. macOS side is fully designed (spike 0002), `ASWebAuthenticationSession` flow ready to implement. Current fallback: browser-handoff (Decision 0006) ships in M6.

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to implement one of two options to enable native in-app OAuth identity linking for the macOS client. Currently the macOS app opens the browser because the `redirect_uri` is a web URL and the flow is cookie-bound — `ASWebAuthenticationSession` cannot intercept the callback.

**Option A (preferred) — Custom URL scheme callback:**

When the macOS client passes `redirect_uri=interlinedlist%3A%2F%2Foauth%2Fcallback` to `GET /api/auth/{provider}/authorize?link=true`, redirect to:
```
interlinedlist://oauth/callback?code=<one-time-code>&state=<original-state>&provider=<provider>
```

Add a code-exchange endpoint:
```
POST /api/auth/{provider}/link
Authorization: Bearer <token>
{ "code": "<one-time code>", "state": "<original state>" }
```
Response 200: `{ "provider": "github", "providerUserId": "string", "username": "string", "linkedAt": "iso-8601" }`  
Error 409: `{"error": "already_linked"}`  
Error 400: `{"error": "invalid_code"}`

**Option B — Bearer-authenticated link endpoint:**
```
POST /api/auth/{provider}/link
Authorization: Bearer <token>
{ "providerToken": "<access token>", "instance": "mastodon.social" (Mastodon only) }
```

Supported providers: `github`, `mastodon` (with `instance` param), `bluesky`, `linkedin`. Implement your chosen option and document the contract.

---

### P1-F — Auth decision on `GET /api/messages`

**Status:** Re-confirmed 2026-07-07 — still returns 200 without a Bearer token.

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). `GET /api/messages?limit=1` returns HTTP 200 with public message content without an `Authorization` header. This may be intentional or unintended. Please make a documented decision:

**Option A — Public-by-design:** Document that unauthenticated requests return only `publiclyVisible: true` messages. Confirm the filter is applied; if not, add it. Update the API docs.

**Option B — Unintended, lock it down:** Add an auth check. Return 401 `{"error": "unauthorized"}` without a Bearer token.

The macOS client always sends a Bearer token — no client change needed for either option. This is a security/correctness decision that needs documenting.

---

## Open — P2 (strongly desired)

### P2-B — Follow action returns resulting relationship (remaining gap)

**Status:** macOS now decodes `{ "follow": { "status": "active"|"pending" } }` correctly. Gap: `followedBy` still needs a separate `GET /api/follow/[userId]/status` call.

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). Extend `POST /api/follow/[userId]` to include `followedBy` in the action response, eliminating one round-trip per follow action.

Add a `relationship` block to the response:
```json
{
  "follow": { "status": "active" },
  "relationship": { "following": true, "pendingRequest": false, "followedBy": false }
}
```

Apply the same `relationship` block to `DELETE /api/follow/[userId]` (unfollow) and `POST /api/follow/[userId]/approve` / `reject`. This is additive — existing clients ignore unknown fields.

---

### P2-C — Typed notification kinds + `routePath`

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). I need you to document and stabilize the notification `type` field from `GET /api/notifications`, and add a `routePath` field.

1. Document the closed type enum. The macOS client assumes: `dig`, `reply`, `mention`, `follow_request`, `follow_accepted`, `list_shared`, `list_row_added`, `org_invite`. Confirm or correct.

2. Add `routePath` to each notification (path relative to `interlinedlist.com`):
   - `dig`/`reply`/`mention` → `/messages/[messageId]`
   - `follow_request`/`follow_accepted` → `/profile/[actorUsername]`
   - `list_shared`/`list_row_added` → `/lists/[listSlug]`
   - `org_invite` → `/organizations/[orgId]`

Additive field — existing clients unaffected.

---

### P2-D — Machine-readable upload limits

**PROMPT:**

You are working on the InterlinedList API (interlinedlist.com). Add `GET /api/limits` (no auth required):
```json
{
  "media": {
    "image": { "maxBytes": 1468006, "maxPixels": 1200, "acceptedFormats": ["jpeg","png","gif","webp","heic"] },
    "video": { "maxBytes": 3145728, "acceptedFormats": ["mp4","mov"] }
  },
  "message": { "maxContentLength": 5000 }
}
```

Also include limits in 413/400 error bodies: `{ "error": "file_too_large", "limit": { "maxBytes": 1468006, "maxPixels": 1200 } }`.

The macOS `ImagePrep` pipeline has these hard-coded as `TODO(backend ask P2.5)`. Once this endpoint exists those constants are replaced with discovered values.

---

### P2-E — Privacy Policy and Support pages

**PROMPT:**

You are working on the InterlinedList website (interlinedlist.com). Publish two pages required for Mac App Store submission:

**`https://interlinedlist.com/privacy`** — must cover: data collected (email, user-generated content), storage and protection, third-party sharing (cross-posting is user-triggered only), user rights (account deletion in Settings), contact info, effective date.

**`https://interlinedlist.com/support`** — must provide: contact method, links to help docs, how to report bugs or request features.

Both must be publicly accessible without login. Apple checks these URLs during App Store review.

---

## Open — P3 (polish)

### P3-A — Document version / ETag for sync conflict detection

**PROMPT:**

Add `version: int` to the document object returned by all read and sync endpoints. Accept `If-Match: <version>` on `PATCH /api/documents/[id]`; when present and stale, return:
```
409 Conflict
{ "error": "version_conflict", "currentVersion": 42, "serverDocument": { /* current */ } }
```
When absent, use existing server-wins behavior (no breaking change). Increment `version` on every successful `PATCH`.

---

### P3-B — `folderId` on sync response documents

**PROMPT:**

Confirm `GET /api/documents/sync` and `POST /api/documents/sync` include `folderId` on every document entry — including preserved-copy documents created during conflict resolution and deleted documents (include their pre-deletion `folderId`). If missing from any case, add it. Probe and document the field name.

---

### P3-C — GitHub-backed list refresh metadata

**PROMPT:**

Add to List objects with `githubSource`:
```json
{ "lastRefreshedAt": "iso-8601 or null", "refreshStatus": "idle|pending|failed", "refreshError": "string or null" }
```

Also accept `githubSource` on `POST /api/lists` (create): `{ "owner", "repo", "path", "ref" }`. If provided, trigger initial refresh immediately and return `refreshStatus: "pending"`.

---

### P3-D — Bearer token revocation and sessions list

**PROMPT:**

Add `deviceLabel` (optional) to `POST /api/auth/sync-token`. Implement:
- `GET /api/user/sessions` → `{ sessions: [{ id, deviceLabel, createdAt, lastUsedAt, isCurrent }] }`
- `DELETE /api/user/sessions/[id]` → 204 (token immediately invalid); 400 `{"error":"cannot_revoke_current_session"}` if self-revoking.

---

### P3-E — `RateLimit-*` headers universally

**Status:** Currently only on `POST /api/messages` and `POST /api/documents/sync`. macOS client already handles absent headers correctly (treats nil as "no limit on this route"). This ask extends coverage.

**PROMPT:**

Add `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset` to every authenticated response. Add `Retry-After` on 429 responses. These follow RFC 6585 and the draft IETF RateLimit spec.

---

## Change log

| Date | Change |
|------|--------|
| 2026-07-08 | Recreated from `API-backend-prompts-to-build.md` + `Backend-Handoff-Prompts.md` (both deleted). Marked P1-A, P1-B, P1-C, P1-D, P2-A resolved — confirmed via live probe and macOS NW features complete. |
| 2026-07-07 | Live probe: P2-A resolved, P1-A endpoints exist (not 404), P3-E still absent. |
| 2026-07-04 | `Backend-Handoff-Prompts.md` authored with copy-paste prompts. |
| 2026-06-25 | `API-backend-prompts-to-build.md` Wave 7 additions. |
| 2026-06-22 | `API-backend-prompts-to-build.md` initial draft. |
