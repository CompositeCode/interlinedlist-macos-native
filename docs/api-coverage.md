# API Endpoint Coverage Matrix

> **Re-baselined 2026-07-31 against the live `openapi.json` (~150 endpoints).** The **original 98 rows** below cover the 2026-06-11 API surface and keep their real ☑/◐/☐ implementation-and-test state unchanged. The live API has since grown to **~150 endpoints** across whole new feature areas the app has not yet implemented; those are captured in the new **[New endpoints (2026-07-31 re-baseline)](#new-endpoints-2026-07-31-re-baseline--not-yet-implemented)** section, each starting ☐/☐ and mapped to its gap ID (G1–G14) in **[`the-gaps.md`](../the-gaps.md) §1**. This file remains the home for the per-endpoint ☑/◐ **test** matrix; the maintenance rule below still governs when a new row may flip.

**Audience:** engineering (maintainers and implementing agents).

This matrix exists so that full coverage of the [InterlinedList API](https://interlinedlist.com/help/api) is **verified, not assumed** (PLAN.md §7). It maps every documented endpoint to the service planned to implement it (PLAN.md §3) and the milestone that ships it (PLAN.md §6), with check-off columns for implementation and tests.

**Maintenance rule:** the documentation engineer updates this matrix at the end of each wave, after the wave gate passes. A row's **Implemented** box is checked only when the endpoint's request builder, DTOs, and service call path are merged; **Tested** is checked only when BDD-named unit tests against `APIClient` stubs cover that endpoint (happy path, invalid input, API failure, empty/boundary — PLAN.md §7). No box is checked speculatively.

- Source of truth for the endpoint inventory: https://interlinedlist.com/help/api (verified 2026-06-11), cross-checked against PLAN.md §1.
- ☐ = not done, ☑ = done, ◐ = **partial** (builder + DTO + service path merged and at least one behavior test exists, but not all four of happy/invalid/failure/empty are present yet — see footnote 4). All rows start unchecked.
- **Auth** column reproduces the API reference's annotation. Groups marked *Session* are subject to the M0 Bearer-vs-Session spike (`docs/spikes/auth-bearer-vs-session.md`, decision in `docs/decisions/0001-auth-transport.md`).
- The three `GET /api/users/[username]/lists*` endpoints appear in the API reference under both **Lists** and **Public**; they are listed once here, under **Lists**, with no-auth noted.

| Endpoint (method + path) | Group | Auth | Planned service | Milestone | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `POST /api/auth/login` | Auth | Public → session cookie | LiveSessionEstablisher (InterlinedKit/Auth) | M7 | ☑ | ☑ |
| `POST /api/auth/logout` | Auth | Session | AuthService (InterlinedKit/Auth) | M0 | ☑ | ◐⁴ |
| `POST /api/auth/register` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☑ | ☐⁶ |
| `POST /api/auth/sync-token` | Auth | Public → Bearer token | AuthService (InterlinedKit/Auth) | M0 | ☑ | ◐⁴ |
| `POST /api/auth/forgot-password` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☑ | ◐⁴ |
| `POST /api/auth/reset-password` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☑ | ◐⁴ |
| `POST /api/auth/send-verification-email` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☑ | ◐⁴ |
| `POST /api/auth/verify-email` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☑ | ◐⁴ |
| `GET /api/auth/github/authorize` | Auth (OAuth) | Public | AuthService (OAuth flows) | M6 | ☑ | ☐¹² |
| `GET /api/auth/mastodon/authorize` | Auth (OAuth) | Public | AuthService (OAuth flows) | M6 | ☑ | ☐¹² |
| `GET /api/auth/bluesky/authorize` | Auth (OAuth) | Public | AuthService (OAuth flows) | M6 | ☑ | ☐¹² |
| `GET /api/auth/linkedin/authorize` | Auth (OAuth) | Public | AuthService (OAuth flows) | M6 | ☑ | ☐¹² |
| `GET /api/user` | User | Session or Bearer | UserService¹ (+ EntitlementsService reads `customerStatus`) | M0 | ☑ | ☑ |
| `POST /api/user/update` | User | Session | UserService¹ | M7 | ☑ | ☑ |
| `POST /api/user/avatar/upload` | User | Session | UserService¹ | M7 | ☑ | ☑ |
| `POST /api/user/avatar/from-url` | User | Session | UserService¹ | M7 | ☑ | ◐⁴ |
| `GET /api/user/identities` | User | Session | UserService¹ | M6 | ☑ | ☑ |
| `GET /api/user/organizations` | User | Session | UserService¹ ⁷ | M6 | ☑ | ☑ |
| `POST /api/user/change-email/request` | User | Session | UserService¹ | M7 | ☑ | ☑ |
| `POST /api/user/delete` | User | Session | UserService¹ | M7 | ☑ | ☑ |
| `GET /api/messages` | Messages | Session or Bearer | MessagesService | M1 | ☑ | ☑ |
| `POST /api/messages` | Messages | Session or Bearer | MessagesService | M2² | ☑ | ☑ |
| `GET /api/messages/[id]` | Messages | Session or Bearer | MessagesService | M1 | ☑ | ☑ |
| `PUT /api/messages/[id]` | Messages | Session or Bearer | MessagesService | M2 | ☑ | ☑ |
| `DELETE /api/messages/[id]` | Messages | Session or Bearer | MessagesService | M2 | ☑ | ☑ |
| `GET /api/messages/scheduled` | Messages | Session or Bearer | MessagesService | M6 | ☑ | ☑ |
| `GET /api/messages/[id]/replies` | Messages | Session | MessagesService | M1 | ☑ | ☑ |
| `POST /api/messages/[id]/dig` | Messages | Session | MessagesService | M2 | ☑ | ☑ |
| `DELETE /api/messages/[id]/dig` | Messages | Session | MessagesService | M2 | ☑ | ☑ |
| `POST /api/messages/images/upload` | Messages | Session or Bearer | MessagesService | M6 | ☑ | ☑ |
| `POST /api/messages/videos/upload` | Messages | Session or Bearer | MessagesService | M6 | ☑ | ☑ |
| `GET /api/lists` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `POST /api/lists` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `GET /api/lists/[id]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴⁹ |
| `PUT /api/lists/[id]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴⁹ |
| `DELETE /api/lists/[id]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `GET /api/lists/[id]/schema` | Lists | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `PUT /api/lists/[id]/schema` | Lists | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `POST /api/lists/[id]/refresh` | Lists | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `GET /api/lists/[id]/data` | Lists | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `POST /api/lists/[id]/data` | Lists | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `GET /api/lists/[id]/data/[rowId]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴⁹ |
| `PATCH /api/lists/[id]/data/[rowId]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `DELETE /api/lists/[id]/data/[rowId]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `GET /api/lists/[id]/watchers` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴⁹ |
| `GET /api/lists/[id]/watchers/me` | Lists | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `GET /api/lists/[id]/watchers/users` | Lists | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `PUT /api/lists/[id]/watchers/[userId]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `DELETE /api/lists/[id]/watchers/[userId]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `GET /api/users/[username]/lists` | Lists (public) | None | ListsService | M1 | ☑ | ☑ |
| `GET /api/users/[username]/lists/[id]` | Lists (public) | None | ListsService | M1 | ☑ | ☑ |
| `GET /api/users/[username]/lists/[id]/data` | Lists (public) | None | ListsService | M1 | ☑ | ☑ |
| `GET /api/lists/connections` | List Connections | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `POST /api/lists/connections` | List Connections | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `DELETE /api/lists/connections/[id]` | List Connections | Session or Bearer | ListsService | M3 | ☑ | ☑ |
| `GET /api/documents/sync` | Documents & Sync | Session or Bearer | DocumentSyncEngine (InterlinedPersistence) | M4 | ☑ | ☑ |
| `POST /api/documents/sync` | Documents & Sync | Session or Bearer | DocumentSyncEngine (InterlinedPersistence) | M4 | ☑ | ☑ |
| `GET /api/documents` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ☑ |
| `POST /api/documents` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ☑ |
| `GET /api/documents/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴¹⁰ |
| `PATCH /api/documents/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ☑ |
| `DELETE /api/documents/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ☑ |
| `POST /api/documents/[id]/images/upload` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ☑ |
| `GET /api/documents/folders` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ☑ |
| `POST /api/documents/folders` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ☑ |
| `GET /api/documents/folders/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴¹⁰ |
| `PATCH /api/documents/folders/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ☑ |
| `DELETE /api/documents/folders/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ☑ |
| `GET /api/documents/folders/[id]/documents` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ☑ |
| `POST /api/follow/[userId]` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `DELETE /api/follow/[userId]` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `GET /api/follow/[userId]/status` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `GET /api/follow/[userId]/followers` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `GET /api/follow/[userId]/following` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `GET /api/follow/[userId]/counts` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `GET /api/follow/[userId]/mutual` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `POST /api/follow/[userId]/approve` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `POST /api/follow/[userId]/reject` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `POST /api/follow/[userId]/remove` | Follow | Session | SocialService | M5 | ☑ | ◐⁴¹¹ |
| `GET /api/follow/requests` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `GET /api/organizations` | Organizations | Session | OrgService | M6 | ☑ | ◐⁴¹³ |
| `POST /api/organizations` | Organizations | Session | OrgService | M6 | ☑ | ☑ |
| `GET /api/organizations/[id]` | Organizations | Session | OrgService | M6 | ☑ | ☑ |
| `PATCH /api/organizations/[id]` | Organizations | Session | OrgService | M6 | ☑ | ☑ |
| `GET /api/organizations/[id]/members` | Organizations | Session | OrgService | M6 | ☑ | ☑ |
| `POST /api/organizations/[id]/members` | Organizations | Session | OrgService | M6 | ☑ | ☑ |
| `PUT /api/organizations/[id]/members/[userId]` | Organizations | Session | OrgService | M6 | ☑ | ☑ |
| `DELETE /api/organizations/[id]/members/[userId]` | Organizations | Session | OrgService | M6 | ☑ | ☑ |
| `GET /api/organizations/[id]/users` | Organizations | Session | OrgService | M6 | ☑ | ◐⁴¹³ |
| `GET /api/exports/messages` | Exports | Session | ExportsService¹ | M7 | ☑ | ☑ |
| `GET /api/exports/lists` | Exports | Session | ExportsService¹ | M7 | ☑ | ☑ |
| `GET /api/exports/list-data-rows` | Exports | Session | ExportsService¹ | M7 | ☑ | ☑ |
| `GET /api/exports/follows` | Exports | Session | ExportsService¹ | M7 | ☑ | ☑ |
| `GET /api/notifications` | Notifications | Session | NotificationsService | M5 | ☑ | ☑ |
| `PATCH /api/notifications/[id]/read` | Notifications | Session | NotificationsService | M5 | ☑ | ☑ |
| `POST /api/notifications/mark-all-read` | Notifications | Session | NotificationsService | M5 | ☑ | ☑ |
| `GET /api/user/[username]/messages` | Public | None | MessagesService⁸ | M1 | ☑ | ☑ |
| `GET /api/auth/linkedin/status` | Public | None | AuthService (OAuth flows) | M6 | ☑ | ☐¹² |

**Original-surface totals:** 98 endpoints — Auth 12 · User 8 · Messages 11 · Lists 21 (incl. 3 public) · List Connections 3 · Documents & Sync 14 · Follow 11 · Organizations 9 · Exports 4 · Notifications 3 · Public-only 2.

## New endpoints (2026-07-31 re-baseline) — not yet implemented

The 2026-07-31 authenticated live probe ([`the-gaps.md`](../the-gaps.md) §2 + appendix) plus `GET /api/openapi.json` show the surface has grown to ~150 endpoints across new feature areas the app has never implemented. Every endpoint below is **absent** from the original 98-row matrix; each starts **Implemented ☐ / Tested ☐** and maps to the gap ID (G1–G14) in [`the-gaps.md`](../the-gaps.md) §1. **Backend** column: ✅ = confirmed live & Bearer-reachable in the 2026-07-31 probe; ⚠️ = live but constrained; *per OpenAPI, unverified* = present in the spec / named in the gap plan but **not** individually hit in the read-only probe (writes were deliberately not exercised). Rows flip ◐→☑ only under the same maintenance rule (a tested App-layer view model drives them end-to-end).

### Direct Messages (G1) — 11

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `GET /api/dm` | Direct Messages | ✅ | G1 | List DMs by folder (inbox/sent/deleted), cursor-paginated | ☐ | ☐ |
| `POST /api/dm` | Direct Messages | ✅ | G1 | Send a DM to a mutual follower (≤8 image attachments) | ☐ | ☐ |
| `POST /api/dm/images/upload` | Direct Messages | ✅ | G1 | Upload an image for a DM | ☐ | ☐ |
| `GET /api/dm/recipients` | Direct Messages | ✅ | G1 | List eligible DM recipients (mutual followers) | ☐ | ☐ |
| `GET /api/dm/thread/{username}` | Direct Messages | ✅ | G1 | Fetch the conversation thread with a user | ☐ | ☐ |
| `GET /api/dm/thread/{username}/updates` | Direct Messages | ✅ | G1 | Poll for new messages in a thread since a marker | ☐ | ☐ |
| `GET /api/dm/unread-count` | Direct Messages | ✅ | G1 | Unread-DM count for the badge | ☐ | ☐ |
| `GET /api/dm/{id}` | Direct Messages | ✅ | G1 | Fetch a single DM | ☐ | ☐ |
| `POST /api/dm/{id}/read` | Direct Messages | ✅ | G1 | Mark a DM read | ☐ | ☐ |
| `POST /api/dm/{id}/restore` | Direct Messages | ✅ | G1 | Restore a trashed DM (per-side) | ☐ | ☐ |
| `POST /api/dm/{id}/trash` | Direct Messages | ✅ | G1 | Soft-delete a DM (per-side) | ☐ | ☐ |

### Moderation (G2) — 10

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `GET /api/user/blocks` | Moderation | ✅ | G2 | List blocked users (paginated) | ☐ | ☐ |
| `POST /api/user/blocks` | Moderation | per OpenAPI, unverified | G2 | Block a user | ☐ | ☐ |
| `DELETE /api/user/blocks/{username}` | Moderation | per OpenAPI, unverified | G2 | Unblock a user | ☐ | ☐ |
| `GET /api/user/blocks/{username}` | Moderation | per OpenAPI, unverified | G2 | Is-blocking status for a user | ☐ | ☐ |
| `GET /api/user/mutes` | Moderation | ✅ | G2 | List muted users (paginated) | ☐ | ☐ |
| `POST /api/user/mutes` | Moderation | per OpenAPI, unverified | G2 | Mute a user | ☐ | ☐ |
| `DELETE /api/user/mutes/{username}` | Moderation | per OpenAPI, unverified | G2 | Unmute a user | ☐ | ☐ |
| `GET /api/user/mutes/{username}` | Moderation | per OpenAPI, unverified | G2 | Is-muting status for a user | ☐ | ☐ |
| `POST /api/reports/user` | Moderation | per OpenAPI, unverified | G2 | Report a user (reason + detail) | ☐ | ☐ |
| `POST /api/reports/message` | Moderation | per OpenAPI, unverified | G2 | Report a message (reason + detail) | ☐ | ☐ |

### Share Links & Collaborators (G3) — 17

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `GET /api/lists/{id}/share-links` | Share Links & Collaborators | ✅ | G3 | List a list's tokenized share links | ☐ | ☐ |
| `POST /api/lists/{id}/share-links` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Create a share link (role + expiry, subscriber-gated) | ☐ | ☐ |
| `DELETE /api/lists/{id}/share-links/{token}` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Revoke a list share link | ☐ | ☐ |
| `GET /api/lists/shared/{token}` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Resolve a shared list by token (read-only viewer) | ☐ | ☐ |
| `POST /api/lists/shared/{token}` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Claim a shared list link | ☐ | ☐ |
| `GET /api/lists/shared/{token}/data` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Read shared-list row data by token | ☐ | ☐ |
| `GET /api/lists/watching` | Share Links & Collaborators | ✅ | G3 | "Shared-with-me" lists the user is watching | ☐ | ☐ |
| `GET /api/documents/{id}/share-links` | Share Links & Collaborators | ✅ | G3 | List a document's share links | ☐ | ☐ |
| `POST /api/documents/{id}/share-links` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Create a document share link (subscriber-gated) | ☐ | ☐ |
| `DELETE /api/documents/{id}/share-links/{token}` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Revoke a document share link | ☐ | ☐ |
| `GET /api/documents/shared/{token}` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Resolve a shared document by token | ☐ | ☐ |
| `POST /api/documents/shared/{token}` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Claim a shared document link | ☐ | ☐ |
| `GET /api/documents/{id}/collaborators` | Share Links & Collaborators | ✅ | G3 | List per-person document collaborators (paginated) | ☐ | ☐ |
| `POST /api/documents/{id}/collaborators` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Add a document collaborator (by @handle + role) | ☐ | ☐ |
| `GET /api/documents/{id}/collaborators/users` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Search users for collaborator invite | ☐ | ☐ |
| `PUT /api/documents/{id}/collaborators/{userId}` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Set a collaborator's role | ☐ | ☐ |
| `DELETE /api/documents/{id}/collaborators/{userId}` | Share Links & Collaborators | per OpenAPI, unverified | G3 | Remove a document collaborator | ☐ | ☐ |

### List Folders (G6) — 4

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `GET /api/folders` | List Folders | ✅ | G6 | List hierarchical list-folders (flat array + `parentId`) | ☐ | ☐ |
| `POST /api/folders` | List Folders | per OpenAPI, unverified | G6 | Create a list-folder (subscriber-gated) | ☐ | ☐ |
| `PUT /api/folders/{id}` | List Folders | per OpenAPI, unverified | G6 | Rename / move a list-folder (cycle-safe) | ☐ | ☐ |
| `DELETE /api/folders/{id}` | List Folders | per OpenAPI, unverified | G6 | Delete a list-folder (detaches lists to root) | ☐ | ☐ |

### Search (G5) — 3

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `GET /api/messages/search` | Search | ✅ | G5 | Server-side message search (`?q=`; POST → 405, search is GET) | ☐ | ☐ |
| `GET /api/lists/search` | Search | ✅ | G5 | Server-side list search | ☐ | ☐ |
| `GET /api/documents/search` | Search | ✅ | G5 | Server-side document search | ☐ | ☐ |

### GitHub (G4) — 8

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `GET /api/github/repos` | GitHub | ⚠️ | G4 | List linked-account repos (400 "not linked" until OAuth link) | ☐ | ☐ |
| `GET /api/github/issues` | GitHub | per OpenAPI, unverified | G4 | List issues for a repo | ☐ | ☐ |
| `POST /api/github/issues` | GitHub | per OpenAPI, unverified | G4 | Create an issue | ☐ | ☐ |
| `PATCH /api/github/issues/{owner}/{repo}/{number}` | GitHub | per OpenAPI, unverified | G4 | Edit an issue (labels / assignees / state) | ☐ | ☐ |
| `POST /api/github/issues/{owner}/{repo}/{number}/comments` | GitHub | per OpenAPI, unverified | G4 | Comment on an issue | ☐ | ☐ |
| `GET /api/github/repos/{owner}/{repo}/assignees` | GitHub | per OpenAPI, unverified | G4 | List assignable users for a repo | ☐ | ☐ |
| `GET /api/github/repos/{owner}/{repo}/labels` | GitHub | per OpenAPI, unverified | G4 | List labels for a repo | ☐ | ☐ |
| `GET /api/github/repos/{owner}/{repo}/next-issue-number` | GitHub | per OpenAPI, unverified | G4 | Next issue number for a repo | ☐ | ☐ |

### Push (G9) — 2

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `POST /api/push/register` | Push | ✅ | G9 | Register an APNs device token (400 "token is required" when empty → route live) | ☐ | ☐ |
| `DELETE /api/push/unregister` | Push | ⚠️ | G9 | Unregister a device token (POST → 405; verb likely DELETE — confirm) | ☐ | ☐ |

### Stripe / Billing (G8) — 2

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `POST /api/stripe/checkout-session` | Stripe / Billing | **404 not deployed** | ~~G8~~ **OUT OF SCOPE** | Billing managed in the online app (owner decision 2026-07-31); route also 404s live | — | — |
| `GET /api/stripe/customer-portal-session` | Stripe / Billing | **404 not deployed** | ~~G8~~ **OUT OF SCOPE** | Billing managed in the online app; route also 404s live | — | — |

### LinkedIn targets (G11a) — 4

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `GET /api/linkedin/targets` | LinkedIn targets | ✅ | G11a | List LinkedIn posting targets (personal target present) | ☐ | ☐ |
| `GET /api/linkedin/posting-targets` | LinkedIn targets | ✅ | G11a | Read enabled posting targets (`enabled:true`, `orgScopeMissing:true`) | ☐ | ☐ |
| `PUT /api/linkedin/posting-targets` | LinkedIn targets | per OpenAPI, unverified | G11a | Set enabled posting targets | ☐ | ☐ |
| `POST /api/linkedin/sync-pages` | LinkedIn targets | per OpenAPI, unverified | G11a | Refresh available LinkedIn pages | ☐ | ☐ |

### Twitter / X auth (G7) — 3

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `GET /api/auth/twitter/authorize` | Twitter / X auth | per OpenAPI, unverified | G7 | Begin X/Twitter OAuth authorization | ☐ | ☐ |
| `GET /api/auth/twitter/callback` | Twitter / X auth | per OpenAPI, unverified | G7 | X/Twitter OAuth callback | ☐ | ☐ |
| `GET /api/auth/twitter/status` | Twitter / X auth | ✅ | G7 | X/Twitter link status (`configured:true`) | ☐ | ☐ |

### Document templates & tree (G12) — 6

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `GET /api/documents/templates` | Document templates & tree | ✅ | G12 | List server-side document templates (seeded + `_templates` folder) | ☐ | ☐ |
| `POST /api/documents/templates/seed-defaults` | Document templates & tree | per OpenAPI, unverified | G12 | Seed the default template set | ☐ | ☐ |
| `GET /api/documents/from-template` | Document templates & tree | per OpenAPI, unverified | G12 | Preview a new document from a template | ☐ | ☐ |
| `POST /api/documents/from-template` | Document templates & tree | per OpenAPI, unverified | G12 | Create a document from a template | ☐ | ☐ |
| `GET /api/documents/tree` | Document templates & tree | ✅ | G12 | One-call folders + documents sidebar payload | ☐ | ☐ |
| `POST /api/documents/folders/{id}/documents` | Document templates & tree | per OpenAPI, unverified | G12 | Create a document directly inside a folder | ☐ | ☐ |

### Document presence (G13) — 2

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `POST /api/documents/{id}/presence` | Document presence | per OpenAPI, unverified | G13 | Send a live co-editing presence heartbeat | ☐ | ☐ |
| `DELETE /api/documents/{id}/presence` | Document presence | per OpenAPI, unverified | G13 | Clear presence on leaving a document | ☐ | ☐ |

### Utility / limits (G14) — 2

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `GET /api/limits` | Utility / limits | ✅ | G14 | Quota / media limits (drives composer validation + plan card) | ☐ | ☐ |
| `GET /api/images/proxy` | Utility / limits | per OpenAPI, unverified | G14 | Image-proxy helper (rich previews / avatars) | ☐ | ☐ |

### Multi-account (G10) — 3

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `GET /api/auth/accounts` | Multi-account | ⚠️ | G10 | List switchable accounts (**401 under Bearer — session-cookie-only**; spike S4) | ☐ | ☐ |
| `POST /api/auth/switch` | Multi-account | ⚠️ | G10 | Switch the active account (session-bound) | ☐ | ☐ |
| `POST /api/auth/remove-account` | Multi-account | per OpenAPI, unverified | G10 | Remove a linked account | ☐ | ☐ |

### Public profile & multi-account (migrations D2 / OAuth-link) — 2

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `GET /api/users/{username}` | Public profile | ✅ | D2 (fn 8) | Direct public-profile read (now live — replaces the decision-0002 fallback) | ☐ | ☐ |
| `POST /api/auth/{provider}/link` | Auth (OAuth) | ✅ | fn 12 | Bearer native OAuth identity-link completion (endpoint live; native flow built on this branch) | ☐ | ☐ |

### Messages & auth drift additions (D1 / D3 / new methods on existing paths) — 4

New HTTP methods / paths on already-listed resource families, surfaced by the re-baseline (see [`the-gaps.md`](../the-gaps.md) §6):

| Endpoint (method + path) | Group | Backend | Gap | Purpose | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `POST /api/messages/scheduled` | Messages | per OpenAPI, unverified | D1 | Explicit schedule-create (app uses `scheduledAt`-on-create — verify preferred) | ☐ | ☐ |
| `POST /api/messages/{id}/replies` | Messages | per OpenAPI, unverified | D3 | Post a reply via POST (app currently reads replies via GET — align verbs) | ☐ | ☐ |
| `POST /api/lists/{id}/watchers` | Lists | per OpenAPI, unverified | — | Invite a watcher via POST (matrix has `PUT …/watchers/{userId}`) | ☐ | ☐ |
| `POST /api/auth/verify-email-change` | Auth | per OpenAPI, unverified | — | Confirm a pending email-change (pairs with existing `change-email/request`) | ☐ | ☐ |

**New-endpoints subtotal:** 53 rows — Direct Messages 11 · Moderation 10 · Share Links & Collaborators 17 · List Folders 4 · Search 3 · GitHub 8 · Push 2 · Stripe/Billing 2 · LinkedIn targets 4 · Twitter/X auth 3 · Document templates & tree 6 · Document presence 2 · Utility/limits 2 · Multi-account 3 · Public profile & OAuth-link (D2 / fn 12) 2 · Messages & auth drift additions 4.

**Re-baseline grand total:** **98 original + 53 new = 151 endpoints** (~150 as reported in [`the-gaps.md`](../the-gaps.md) §1). Original 98 keep their real implementation/test state (98 implemented; 74 ☑ / 18 ◐ / 6 ☐ tested as of Wave 8); all 53 new rows start ☐ Implemented / ☐ Tested.

## Footnotes and assumptions

1. **UserService / ExportsService** were not explicitly named in PLAN.md §3 (its service list ends with an ellipsis: "MessagesService, ListsService, DocumentsService, SocialService, OrgService, NotificationsService…"). Wave 1 confirmed the convention: the User endpoint group ships as `InterlinedKit.User` (see `Packages/InterlinedKit/Sources/InterlinedKit/Endpoints/UserEndpoint.swift`) and the Exports group as `InterlinedKit.Exports` (`ExportsEndpoint.swift`); domain-side `UserService` / `ExportsService` wrappers are deferred to the milestone in which the consuming UI lands (M6/M7).
2. `POST /api/messages` ships in M2 for plain posting; its scheduled-post (`scheduledAt`) and cross-posting (`mastodonProviderIds`, `crossPostToBluesky`, `crossPostToLinkedIn`) request fields land in M6. The row is checked Implemented at M2; the M6 wave update must confirm the extended fields are covered before the row counts toward M6. Wave 1 note: `MessagesEndpointTests.test_givenCrossPostAndScheduled_whenCreateBuilt_thenEncodesAllSetFields` already exercises encoding for the M6 fields against the builder. **Resolved Wave 7 (2026-06-25):** the M6 extended fields are now consumed end-to-end — `MessagesService.createPost` carries `scheduledAt` + cross-post flags + uploaded-media references, driven by the M6 composer extensions (`ComposerViewModel`) through a tested App-layer path. The row was already ☑ from Wave 1's plain-posting builder coverage and stays ☑; this footnote now records that the M6 field carriage is closed rather than pending.
3. Repost (`pushedMessageId`), visibility, and tag filters are request/response fields on existing rows above, not separate endpoints — they carry no row of their own.
4. **Partial test coverage (◐).** The row's request builder, DTOs, and `APIClient.send` path are merged and at least one behavior test exists (typically builder-shape assertion plus one or two of happy/invalid/failure/empty), but the full happy + invalid + failure + empty/boundary quartet required by PLAN.md §7 is not yet present for that specific endpoint. APIClient-level failure decoding is exercised exhaustively in `APIClientTests` / `APIErrorTests`, so per-endpoint failure paths inherit correct error mapping; the gap is dedicated per-endpoint behavior tests. To be backfilled in the milestone in which the row's domain service lands, before the row counts toward that milestone's gate.
5. `POST /api/auth/login` (cookie-session credential exchange) was deferred through Waves 1–7 (`NullSessionEstablisher` stub). **Resolved Wave 8.1 (2026-07-03):** `LiveSessionEstablisher` + `CredentialStore` + `KeychainCredentialStore` now implement the lazy `POST /api/auth/login` path; `AuthService.signIn` persists credentials to `KeychainCredentialStore` so the establisher can re-authenticate on the next `.session` call. `LiveSessionEstablisherTests` covers the full quartet (happy 200/204, no-credentials, server 401, server 500, transport failure). Row flipped to ☑/☑; this footnote is resolved.
6. `POST /api/auth/register` ships as `AuthService.register` and is exercised by the live `ContractTests` when `INTERLINEDLIST_EMAIL` / `INTERLINEDLIST_PASSWORD` are present, but has no stubbed unit-test cases yet (only `signIn` has dedicated unit tests in `AuthServiceTests`). Tested ☐ until at least happy + invalid + failure + empty/boundary unit tests are added (likely in the onboarding-feature wave).
7. `GET /api/user/organizations` lives in `InterlinedKit.User.organizations()` (not `Organizations.*`) because the live API path is `/api/user/organizations`, not `/api/organizations`. Planned-service column corrected from `OrgService` to `UserService¹` in Wave 1 to match the actual implementation.
8. **~~No public profile read endpoint exists on the live API.~~ RESOLVED 2026-07-31 — the endpoint now exists.** *(Historical:* the 2026-06-21 kit-gap spike found every variation of `GET /api/users/[username]` returned 404, so `SocialService.profile(username:)` fell back — per decision [`0002-public-profile-fallback`](decisions/0002-public-profile-fallback.md) — to the embedded `{ id, username, displayName, avatar }` author object on the first message from `GET /api/user/[username]/messages`.*)* The 2026-07-31 live probe ([`the-gaps.md`](../the-gaps.md) §2/§6, appendix) confirms `GET /api/users/{username}` now returns a **real public profile** (`/api/users/messenger` → 200). The direct-read row is added in the [New endpoints re-baseline](#new-endpoints-2026-07-31-re-baseline--not-yet-implemented) section under **Public profile & multi-account (migration D2)** at ☐/☐; migration **D2** ([`the-gaps.md`](../the-gaps.md) §6) tracks replacing the decision-0002 fallback with the direct call (keep the fallback only for pre-migration servers). When that row is implemented and view-model-tested it flips per the maintenance rule.
9. **M3 reachable but not exercised by a tested App-layer view model this wave.** Per Wave 1 footnote 4, a row only flips ◐⁴ → ☑ when an App-layer consumer drives it end-to-end under test. Four Lists rows are wired through `ListsService` and reachable from the running app but their consuming UX was held back to a polish slice this wave: `GET /api/lists/[id]` and `PUT /api/lists/[id]` (the detail-rename / single-list-refresh paths — rename UX deferred), `GET /api/lists/[id]/data/[rowId]` (single-row hydration — `RowInspectorView` reads from the already-paginated `ListRowsViewModel.rows` array), and `GET /api/lists/[id]/watchers` (the watcher pagination envelope — `WatchersView` consumes `/users` only this wave). These rows stay ◐⁴ until the next M3 polish wave consumes them through a tested view model. The Wave 1 footnote-4 backfill rule still applies.
10. **M4 detail-read rows reachable but not view-model-tested this wave.** Same pattern as footnote 9, applied to Documents. `GET /api/documents/[id]` and `GET /api/documents/folders/[id]` are wired through `DocumentsService.document(id:)` / `DocumentsService.folder(id:)` and reachable from the running app, but the Wave 5.3 App-layer view models (`DocumentsListViewModel`, `DocumentEditorViewModel`, `FolderTreeViewModel`) consume documents and folders from the **list** payload (`GET /api/documents`, `GET /api/documents/folders[/[id]/documents]`) and the **sync delta** payload rather than re-reading by id. The detail-read endpoints stay ◐⁴ until a polish slice consumes them through a tested view-model path (a likely candidate: a single-document deep-link / quick-look refresh, or a focused folder-rename inspector that re-hydrates from `folder(id:)`). The Wave 1 footnote-4 backfill rule still applies.
11. **M5 follower-removal reachable but not view-model-tested this wave.** Same pattern as footnotes 9 and 10, applied to Follow. `POST /api/follow/[userId]/remove` (the "remove a user from **my** followers" action — distinct from `DELETE /api/follow/[userId]`, which unfollows someone I follow) is wired through `SocialService.removeFollower(userId:)` and reachable from the running app, but no Wave 6.3 view model exercises it through a tested path: the Followers tab in `SocialRosterRootView` displays the roster and approves/rejects pending requests, but does not yet surface a "remove this follower" action against an already-accepted follower. The row stays ◐⁴ until a polish slice (most likely a `SocialRosterRowViewModel.removeFollower` action behind a context menu on the Followers tab) consumes it. The Wave 1 footnote-4 backfill rule still applies.
12. **OAuth `authorize` builders Implemented (Wave 7).** The five M6 OAuth rows (`GET /api/auth/{github,mastodon,bluesky,linkedin}/authorize` and `GET /api/auth/linkedin/status`) gained Kit request builders in Wave 7 (`Auth.authorize(provider:link:instance:)`, `Auth.linkedinStatus()`, the `OAuthProvider` enum, and the `LinkedInStatusResponse` DTO, with 13 builder tests), so their **Implemented** column is ☑. **UPDATE 2026-07-31 — native OAuth identity linking is now BUILT on `feature/web-parity-batch-2026-07`, so the "blocked upstream" note is resolved** ([`the-gaps.md`](../the-gaps.md) §3): `Auth.linkIdentity` → `POST /api/auth/{provider}/link`, `UserService.linkIdentityNative`, a registered `interlinedlist://oauth/callback` custom scheme, and `ASWebAuthenticationSession` now let the app complete the flow natively rather than only handing `…/authorize?link=true` to the browser. The bearer `POST /api/auth/{provider}/link` completion endpoint that footnote 12 said "does not exist" is live and consumed; the new `POST /api/auth/{provider}/link` row is added in the [New endpoints re-baseline](#new-endpoints-2026-07-31-re-baseline--not-yet-implemented) section under **Public profile & multi-account**. The five original `authorize`/`status` rows keep their historical Tested ☐ state here (their per-endpoint completion tests are backfilled with the native-linking work); flips follow the maintenance rule once a view-model test drives them end-to-end.
13. **M6 organization-read rows reachable but not view-model-tested this wave.** Same pattern as footnotes 9, 10, and 11, applied to Organizations. Two OrgService read rows are wired and reachable but not driven by a tested App-layer view model this wave: `GET /api/organizations` (the *list-all-orgs* variant) — the Wave 7.3 Organizations UI lists the current user's orgs through `UserService.organizations()` (`GET /api/user/organizations`) instead, so the `OrgService` list-all path stays unconsumed; and `GET /api/organizations/[id]/users` (`OrgService.users(of:)`) — the member roster is rendered from `GET /api/organizations/[id]/members` (`OrgMembersViewModel`), leaving the `/users` projection unconsumed. Both rows stay ◐⁴ until a polish slice consumes them through a tested view model. The Wave 1 footnote-4 backfill rule still applies.

## Cross-check against PLAN.md §1 (2026-06-11)

- Every API surface named in PLAN.md §1 maps to at least one row above. No PLAN.md endpoint is missing from the live reference.
- Present in the live reference but not explicitly named in PLAN.md §1: `POST /api/auth/logout` (implied by the auth feature), `GET /api/auth/linkedin/status` (supports the LinkedIn cross-post/OAuth feature, M6), and `GET /api/user/[username]/messages` (public user messages; nearest §1 feature is user profiles, M1 — and after the 2026-06-21 spike, this row carries the M1 profile fallback per decision 0002 and footnote 8).
- **PLAN.md §1 surface with no live endpoint:** the Profile-row's natural backing call `GET /api/users/[username]` does not exist on the live API (2026-06-21 spike). Captured in footnote 8 and decision [`0002-public-profile-fallback`](decisions/0002-public-profile-fallback.md); no row added to the matrix above until the upstream endpoint ships.
- PLAN.md §4's "Session-only" list (replies, digs, follow, organizations, notifications, document CRUD) matches the live annotations. The live reference additionally marks the User group's write endpoints and Exports as Session — the M0 spike should probe these groups too.

## Update history

- **2026-07-31 — Re-baseline against live `openapi.json` (~150 endpoints).** The matrix was stale at 98 endpoints (2026-06-11 surface); the live API has grown to ~150 across new feature areas. Re-baselined per [`the-gaps.md`](../the-gaps.md) §8: (1) the intro banner now states the ~150-endpoint re-baseline; (2) all **98 original rows keep their real ☑/◐/☐ implementation-and-test state unchanged** (98 implemented; 74 ☑ / 18 ◐ / 6 ☐ tested); (3) a new **"New endpoints (2026-07-31 re-baseline)"** section adds **53 rows** — all ☐ Implemented / ☐ Tested — grouped by feature area and mapped to gap IDs G1–G14: Direct Messages (G1) 11, Moderation (G2) 10, Share Links & Collaborators (G3) 17, List Folders (G6) 4, Search (G5) 3, GitHub (G4) 8, Push (G9) 2, Stripe/Billing (G8) 2, LinkedIn targets (G11a) 4, Twitter/X auth (G7) 3, Document templates & tree (G12) 6, Document presence (G13) 2, Utility/limits (G14) 2, Multi-account (G10) 3, Public profile & OAuth-link (D2 / fn 12) 2, and Messages & auth drift additions (D1/D3) 4. Each new row carries a **Backend** marker: ✅ confirmed live in the 2026-07-31 authenticated probe, ⚠️ live-but-constrained, or *per OpenAPI, unverified* (spec-listed / gap-planned but not individually hit read-only). **Footnote 8 RESOLVED** — `GET /api/users/{username}` public profile now exists (verified live, migration D2); the direct-read row is added and the decision-0002 fallback is slated for replacement. **Footnote 12 RESOLVED** — native OAuth identity linking (`POST /api/auth/{provider}/link` via `Auth.linkIdentity` + `ASWebAuthenticationSession` + `interlinedlist://oauth/callback`) is BUILT on `feature/web-parity-batch-2026-07`; the "blocked upstream" note no longer applies and the `…/link` row is added. **Grand total: 98 original + 53 new = 151 endpoints (~150).** No original row's ☑/◐/☐ mark was changed; new rows flip only under the existing maintenance rule (a tested App-layer view model drives them end-to-end).

- **2026-07-03 — Wave 8 update (M7 Ship: LiveSessionEstablisher, Exports E2E, Settings/Account E2E).** Wave 8.1 landed `LiveSessionEstablisher` (`CredentialStore` protocol + `KeychainCredentialStore` production + `InMemoryCredentialStore` tests) — the real `POST /api/auth/login` cookie-session fallback that was stubbed via `NullSessionEstablisher` since Wave 1. `AuthService.signIn` now persists credentials to Keychain so the establisher can re-authenticate lazily; `AppEnvironment.live()` wired with a dedicated ephemeral `URLSession` (isolated cookie jar). `LiveSessionEstablisherTests` covers the full quartet (6 new Kit tests; InterlinedKit suite 190 → 196). Wave 8.2 added `ExportViewModelTests` (8 tests) + `StubExportsService` to the App test suite, exercising all four export paths end-to-end through the view model. Wave 8.3 confirmed `AccountViewModelTests` (11 tests) already in the suite, covering avatar upload, email-change, account deletion, and sign-out quartet. Wave 8.0 (NW probe) confirmed all 6 NW-blocked items remain upstream-blocked; `NEXT-WORK.md` probe log appended. **Rows flipped ◐⁴ → ☑ this wave (7 total):** `GET /api/exports/messages`, `GET /api/exports/lists`, `GET /api/exports/list-data-rows`, `GET /api/exports/follows` (via `ExportViewModel` → `ExportsServicing` end-to-end with `ExportViewModelTests`), `POST /api/user/avatar/upload`, `POST /api/user/change-email/request`, `POST /api/user/delete` (via `AccountViewModel` → `UserServicing` end-to-end with `AccountViewModelTests`). **Row flipped ☐ → ☑ (Implemented + Tested): `POST /api/auth/login`** (`LiveSessionEstablisher` + `LiveSessionEstablisherTests` full quartet). **Math: Implemented 97 → 98 of 98 (all endpoints now implemented); Tested fully 66 → 74 of 98 (+8); Tested partial 25 → 18 of 98 (−7 from ◐⁴→☑, plus the ☐→☑ POST /api/auth/login removes 1 from untested not partial); Untested ☐ 7 → 6 of 98 (POST /api/auth/login now fully tested).** App test suite: 278 → 305 tests; InterlinedKit: 190 → 196; grand total across all targets: 976 → 1017. Footnote 5 resolved.

- **2026-06-25 — Wave 7 update (M6 Subscriber + orgs consumed end-to-end; native OAuth blocked upstream).** `InterlinedDomain` M6 slice (`OrgService` over the Organizations endpoints with `Organization` / `OrgMember` / `OrgUser` / `OrgRole` / `OrgsPage` / `OrgMembersPage` / `OrgMappers`; `UserService` `identities()` / `organizations()` + `LinkedIdentity` / `IdentityProvider` and the new `identityLinkURL(provider:instance:)`; `MessagesService` M6 write surface — `createPost` with media / scheduled / cross-post, `scheduledPosts()`, `uploadImage` / `uploadVideo` via `ImagePrep`, all subscriber-gated via `EntitlementsService` with a live `entitlementsProvider` backstop) plus the `InterlinedPersistence` `SwiftDataOrgStore` / `SwiftDataLinkedIdentityStore`. App-layer M6 UI: Organizations (`OrganizationsRootView` + `OrganizationsListViewModel` / `OrganizationDetailViewModel` / `OrgMembersViewModel`, `.organizations` route flipped), the M6 composer extensions + read-only `ScheduledPostsRootView` (`ScheduledPostsViewModel`, `.scheduled` route flipped), and the browser-handoff `SettingsRootView` → Linked accounts pane (`LinkedAccountsView` / `LinkedAccountsViewModel`). Kit gained the additive OAuth builders (`Auth.authorize(provider:link:instance:)`, `Auth.linkedinStatus()`, `OAuthProvider`, `LinkedInStatusResponse`) from the 7.0 spike ([spike 0002](spikes/0002-oauth-identity-linking.md)). Per the Wave 1 footnote-4 rule, every M6-consumed row exercised by a tested App-layer view model this wave flips ◐⁴ → ☑. **11 rows flipped ◐⁴ → ☑**: `GET /api/user/organizations` (`UserService.organizations` → `OrganizationsListViewModel`), `POST /api/organizations` (`OrgService.create` → `OrganizationsListViewModel`), `GET /api/organizations/[id]` (`OrgService.organization(id:)` → `OrganizationDetailViewModel`), `PATCH /api/organizations/[id]` (`OrgService.update` → `OrganizationDetailViewModel`), `GET /api/organizations/[id]/members` (`OrgService.members(of:)` → `OrgMembersViewModel`), `POST /api/organizations/[id]/members` (`OrgService.addMember` → `OrgMembersViewModel`), `PUT /api/organizations/[id]/members/[userId]` (`OrgService.setMemberRole` → `OrgMembersViewModel`), `DELETE /api/organizations/[id]/members/[userId]` (`OrgService.removeMember` → `OrgMembersViewModel`), `GET /api/user/identities` (`UserService.identities` → `LinkedAccountsViewModel`), `POST /api/messages/images/upload` (`MessagesService.uploadImage` → `ComposerViewModel`; `ImagePrep` exercised), `POST /api/messages/videos/upload` (`MessagesService.uploadVideo` → `ComposerViewModel`). **Five OAuth rows flipped Implemented ☐ → ☑ but stay Tested ☐¹² — by design** (new footnote 12): `GET /api/auth/{github,mastodon,bluesky,linkedin}/authorize` and `GET /api/auth/linkedin/status` gained Kit builders (+13 tests) but native completion is **blocked upstream** ([decision 0006](decisions/0006-oauth-identity-linking-browser-handoff.md)) — the app opens `…/authorize?link=true` in the browser (reached indirectly via `UserService.identityLinkURL`), it does not send these requests, and `linkedin/status` is unconsumed. **Two org-read rows stay ◐⁴ — held back** (new footnote 13): `GET /api/organizations` (list-all variant — UI uses `UserService.organizations()` instead) and `GET /api/organizations/[id]/users` (`OrgService.users(of:)` unconsumed — roster renders from `/members`). **Re-consumed but unchanged (☑ already)**: `POST /api/messages` (already ☑ from Wave 1's M6-field builder coverage; its scheduled / cross-post / media fields are now consumed end-to-end via `ComposerViewModel` — footnote 2 resolved), `GET /api/messages/scheduled` (already ☑ from Wave 1; re-consumed read-only by `ScheduledPostsViewModel`). **Math: Implemented 92 → 97 of 98 (+5 OAuth builders; only `POST /api/auth/login`⁵ remains unimplemented); Tested fully 55 → 66 of 98 (+11); Tested partial 36 → 25 of 98 (−11); Untested 7 of 98 (unchanged — the 5 OAuth rows are now Implemented-but-Tested-☐¹², plus `POST /api/auth/login`⁵ and `POST /api/auth/register`⁶).** Footnotes 12 and 13 added; footnote 2 marked resolved. No other footnotes touched.
- **2026-06-24 — Wave 6 update (M5 Social + Notifications consumed end-to-end).** `InterlinedDomain` Follow / Notifications slice (`FollowMappers`, `FollowRelationship` + `FollowAction`, `FollowRequest`, `MutualCounts`, `Notification`, `NotificationKind` + `NotificationTarget`, `NotificationMappers`, `SocialService` write surface, `NotificationsService`) shipped across commits `cae57cc` (Wave 1 deviation 5 closure — Follow envelopes pinned to live API), `da13846` (domain models + services + tests), `159f71a` (namespace-alias workaround), `085b91f` (Wave 6.1 closure: `InterlinedDomain` → `InterlinedDomain_Module` marker rename + `SwiftDataNotificationStore` / `SwiftDataFollowCountsStore` persistence tests + Follow action backend ask 2.3b). App-layer Social + Notifications UI shipped in commit `9a66154` (`FollowButton` + `FollowButtonViewModel`, `SocialRosterRootView` + `SocialRosterViewModel` for Followers / Following / Requests tabs, `FollowRequestRowViewModel` shared between tray and roster, `NotificationsRootView` + `NotificationsListViewModel` + `NotificationRowView` + `NotificationRowCopy`, `NotificationsPermissionCoordinator`, `NotificationsUnreadBadgeCoordinator` + `NotificationsEventBus`, `ProfileHeaderView` + `ProfileViewModel`, `NotificationsMenuCommands` + `SocialMenuCommands`, sidebar `.connections` entry, Decision-0005 `App/Composition/AppDelegate.swift` for dock badge + UN delegate, and `App/Composition/FollowRelationshipReader.swift` composition-root adapter). Per the Wave 1 deviation-6 rule, every M5-consumed row exercised by a tested App-layer view model this wave is now fully tested (☑) end-to-end (Kit builder → Domain service → App view-model). **8 rows flipped ◐⁴ → ☑**: `POST /api/follow/[userId]` (`SocialService.follow` → `FollowButtonViewModel.performFollow`), `DELETE /api/follow/[userId]` (`SocialService.unfollow` → `FollowButtonViewModel.performUnfollow`), `GET /api/follow/[userId]/mutual` (`SocialService.mutual` → `ProfileViewModel.loadProfile`), `POST /api/follow/[userId]/approve` (`SocialService.approve` → `SocialRosterViewModel.approve` / `FollowRequestRowViewModel.approve`), `POST /api/follow/[userId]/reject` (`SocialService.reject` → `SocialRosterViewModel.reject` / `FollowRequestRowViewModel.reject`), `GET /api/follow/requests` (`SocialService.requests` → `SocialRosterViewModel.loadRequests`), `PATCH /api/notifications/[id]/read` (`NotificationsService.markRead` → `NotificationsListViewModel.markRead`), `POST /api/notifications/mark-all-read` (`NotificationsService.markAllRead` → `NotificationsListViewModel.markAllRead`). **One Follow row stays ◐⁴ — held back** as documented in new footnote 11: `POST /api/follow/[userId]/remove` (the "remove from my followers" action — distinct from unfollow) is reachable via `SocialService.removeFollower` but no Wave 6.3 view model surfaces it; flips when a polish slice consumes it. **Re-consumed but unchanged (☑ already)**: `GET /api/follow/[userId]/status` (already ☑ from Wave 2; re-consumed via `FollowRelationshipReader` → `FollowButtonViewModel`), `GET /api/follow/[userId]/followers` / `GET /api/follow/[userId]/following` / `GET /api/follow/[userId]/counts` (already ☑ from Wave 2; re-consumed by `SocialRosterViewModel` / `ProfileViewModel`), `GET /api/notifications?scope=tray` (already ☑ from Wave 1; re-consumed by `NotificationsListViewModel.load`). **Math: Implemented 92 of 98 (unchanged); Tested fully 47 → 55 of 98 (+8); Tested partial 44 → 36 of 98 (−8); Untested 7 of 98 (unchanged).** Footnote 11 added. No other footnotes touched.
- **2026-06-23 — Wave 5 update (M4 Documents consumed end-to-end).** `InterlinedDomain` Documents slice (`Document`, `FolderNode`, `DocumentSyncEvent`, `DocumentChange`, `DocumentMappers`, `ImagePrep`, `DocumentsService`, `DocumentSyncTransport`) and `InterlinedPersistence` (`DocumentRecord`, `FolderRecord`, `OutboxEntryRecord`, `SyncStateRecord`, `SwiftDataDocumentStore`, `DocumentSyncEngine`) shipped in commit `daf1eef`; App-layer Documents UI (`DocumentsRootView`, `DocumentsSidebarView` + `FolderTreeViewModel`, `DocumentsListView` + `DocumentsListViewModel`, `DocumentEditorView` + `DocumentEditorViewModel`, `ConflictBannerView`, `SyncStatusView` + `SyncStatusViewModel`, `DocumentsMenuCommands`, `KitDocumentSyncTransport` wiring) shipped in commit `babb6d2`. Per the Wave 1 protocol in footnote 4, every M4-consumed Documents & Sync row exercised by a tested App-layer view model this wave is now fully tested (☑) end-to-end (Kit builder → Domain service → App view-model). **12 rows flipped ◐⁴ → ☑**: `GET /api/documents/sync` (`KitDocumentSyncTransport.pullDelta` via `DocumentSyncEngine.syncNow` via `SyncStatusViewModel.syncNow`), `POST /api/documents/sync` (`KitDocumentSyncTransport.pushChange` via `DocumentSyncEngine.syncNow` outbox push), `GET /api/documents` (`DocumentsService.documents(in:limit:offset:)` when folder is nil → `DocumentsListViewModel.reload`), `POST /api/documents` (`DocumentsService.create` → `DocumentsListViewModel.createDocument`), `PATCH /api/documents/[id]` (`DocumentsService.update` → `DocumentEditorViewModel.saveNow`), `DELETE /api/documents/[id]` (`DocumentsService.delete` → `DocumentsListViewModel.deleteDocument`), `POST /api/documents/[id]/images/upload` (`DocumentsService.uploadImage` → `DocumentEditorViewModel.uploadImage`; `ImagePrep` is exercised in the upload path), `GET /api/documents/folders` (`DocumentsService.folders` → `FolderTreeViewModel.initialLoad`), `POST /api/documents/folders` (`DocumentsService.createFolder` → `FolderTreeViewModel.createFolder`), `PATCH /api/documents/folders/[id]` (`DocumentsService.renameFolder` → `FolderTreeViewModel.renameFolder`), `DELETE /api/documents/folders/[id]` (`DocumentsService.deleteFolder` → `FolderTreeViewModel.deleteFolder`), `GET /api/documents/folders/[id]/documents` (`DocumentsService.documents(in:limit:offset:)` when folderID != nil → `DocumentsListViewModel.reload`). **Two Documents & Sync rows stay ◐⁴ — held back** as documented in new footnote 10: `GET /api/documents/[id]` and `GET /api/documents/folders/[id]` are reachable via `DocumentsService.document(id:)` / `folder(id:)` but the Wave 5.3 view models open documents and folders from the list payload (and from the sync delta) rather than re-reading by id. **Math: Implemented 92 of 98 (unchanged); Tested fully 35 → 47 of 98 (+12); Tested partial 56 → 44 of 98 (−12); Untested 7 of 98 (unchanged).** Footnote 10 added. No other footnotes touched.
- **2026-06-23 — Wave 4 update (M3 Lists consumed end-to-end).** `InterlinedDomain` Lists write surface + schema DSL + `InterlinedPersistence` SwiftData lists cache shipped in commit `415c5c2`; App-layer Lists UI (owned-lists root, schema editor, rows table, row inspector, watchers, connections graph) shipped in commits `461e7df` + `155c955` (view models) + `099d8d9` (views, sidebar router, menu commands). Per the Wave 1 protocol in footnote 4, every M3-consumed row that was partial (◐⁴) and is exercised by a tested App-layer view model this wave is now fully tested (☑) end-to-end (Kit builder → Domain service → App view-model). **15 rows flipped ◐⁴ → ☑**: `DELETE /api/lists/[id]`, `GET /api/lists/[id]/schema`, `PUT /api/lists/[id]/schema`, `POST /api/lists/[id]/refresh`, `GET /api/lists/[id]/data`, `POST /api/lists/[id]/data`, `PATCH /api/lists/[id]/data/[rowId]`, `DELETE /api/lists/[id]/data/[rowId]`, `GET /api/lists/[id]/watchers/me`, `GET /api/lists/[id]/watchers/users`, `PUT /api/lists/[id]/watchers/[userId]`, `DELETE /api/lists/[id]/watchers/[userId]`, `GET /api/lists/connections`, `POST /api/lists/connections`, `DELETE /api/lists/connections/[id]`. **Four Lists rows stay ◐⁴ — held back** as documented in new footnote 9: `GET /api/lists/[id]`, `PUT /api/lists/[id]`, `GET /api/lists/[id]/data/[rowId]`, `GET /api/lists/[id]/watchers` (reachable via `ListsService` but not exercised by a tested view model this wave). `GET /api/lists` and `POST /api/lists` likewise stay ◐⁴ for this wave — their App-layer consumers (`OwnedListsViewModel.initialLoad` / `loadMore`, `NewListViewModel.submit` + `ListDetailViewModel.saveToMyLists`) exercise the request path but the M3 polish slice will pin the full happy + invalid + failure + empty/boundary quartets at the view-model layer before they flip. The three public-Lists rows (`GET /api/users/[username]/lists*`) were already ☑ from Wave 2. **Math: Implemented 92 of 98 (unchanged); Tested fully 20 → 35 of 98 (+15); Tested partial 71 → 56 of 98 (−15); Untested 7 of 98 (unchanged).** Footnote 9 added. No other footnotes touched.
- **2026-06-22 — Wave 3 update (M2 posting consumed end-to-end).** Decision [`0003-kit-import-policy`](decisions/0003-kit-import-policy.md) recorded; `InterlinedDomain.MessagesService` gained the M2 write surface (`create`, `reply`, `repost`, `update(messageId:…)`, `delete(messageId:)`, `dig(messageId:)`, `undig(messageId:)`) per commit `c07ac8a`; App-layer Composer / inline-reply / optimistic-dig / repost / edit / delete UI landed in the follow-on commit (`InterlinedListTests` 44/44 passing). Per the Wave 1 protocol in footnote 4, every M2-consumed row that was partial (◐⁴) after Wave 2 is now fully tested (☑) end-to-end (Kit builder → Domain service → App view-model). Four rows flipped ◐⁴ → ☑: `PUT /api/messages/[id]`, `DELETE /api/messages/[id]`, `POST /api/messages/[id]/dig`, `DELETE /api/messages/[id]/dig`. `POST /api/messages` was already ☑ from Wave 1 (cross-post-fields builder coverage) and is re-exercised this wave by all three App-layer entry points (`create`, `reply`, `repost`) — row state unchanged. `GET /api/user` was already ☑ from Wave 2 and is additionally consumed this wave by the App-layer `CurrentUserStore` for ownership gating — row state unchanged. The cross-post / scheduled / media request fields on `POST /api/messages` remain M6 per footnote 2. **Implemented: 92 of 98 (unchanged). Tested: 20 of 98 fully (☑), 71 of 98 partial (◐⁴), 6 untested ☐ plus 1 untested-with-context ☐⁶.** No new footnotes added.
- **2026-06-21 — Wave 2 update (M1 read-only core consumed).** Domain (`InterlinedDomain`) services + Persistence (`InterlinedPersistence`) SwiftData cache + App-layer Timeline / Lists / Profile UI landed for PLAN.md §6 M1. Per the Wave 1 protocol in footnote 4, every M1-consumed row was promoted from partial (◐⁴) to full (☑) at the domain-service layer. Ten rows flipped: `GET /api/messages`, `GET /api/messages/[id]/replies`, `GET /api/users/[username]/lists`, `GET /api/users/[username]/lists/[id]`, `GET /api/users/[username]/lists/[id]/data`, `GET /api/follow/[userId]/status`, `GET /api/follow/[userId]/followers`, `GET /api/follow/[userId]/following`, `GET /api/follow/[userId]/counts`, and `GET /api/user/[username]/messages`. (`GET /api/messages/[id]` was already ☑ from Wave 1 and is not in the flip count.) **Implemented: 92 of 98 (unchanged). Tested: 16 of 98 fully (☑), 75 of 98 partial (◐⁴), 6 untested ☐ plus 1 untested-with-context ☐⁶.** No new footnotes added.
- **2026-06-21 — Public profile gap recorded.** 2026-06-21 kit-gap spike confirmed `GET /api/users/[username]` (and every reasonable variation) does not exist on the live API. Footnote 8 added; `GET /api/user/[username]/messages` row annotated with footnote 8 to mark its role as the M1 profile fallback carrier per decision [`0002-public-profile-fallback`](decisions/0002-public-profile-fallback.md). No row added to the matrix; no Implemented / Tested counts change.
- **2026-06-18 — Wave 1 update.** InterlinedKit endpoint groups (Auth additive, User, Messages, Lists, Documents & Sync, Follow, Organizations, Notifications, Exports) merged in commits `86eea76`, `a1e6d1c`, `6ed194a`. **Implemented: 92 of 98** (the 6 unimplemented rows are `POST /api/auth/login` ⁵, the four OAuth `authorize` endpoints, and `GET /api/auth/linkedin/status` — all M6/M7). **Tested: 6 of 98 fully (☑), 85 of 98 partial (◐⁴), 6 untested ☐ plus 1 untested-with-context ☐⁶.** Footnote 1 resolved (planned-service column matches code). Footnote 7 added: `GET /api/user/organizations` belongs to the `User` namespace, not `Organizations`. Footnotes 5 (login deferred) and 6 (register lacks dedicated stubbed unit tests) added.
