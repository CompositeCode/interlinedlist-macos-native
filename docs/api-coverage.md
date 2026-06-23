# API Endpoint Coverage Matrix

**Audience:** engineering (maintainers and implementing agents).

This matrix exists so that full coverage of the [InterlinedList API](https://interlinedlist.com/help/api) is **verified, not assumed** (PLAN.md §7). It maps every documented endpoint to the service planned to implement it (PLAN.md §3) and the milestone that ships it (PLAN.md §6), with check-off columns for implementation and tests.

**Maintenance rule:** the documentation engineer updates this matrix at the end of each wave, after the wave gate passes. A row's **Implemented** box is checked only when the endpoint's request builder, DTOs, and service call path are merged; **Tested** is checked only when BDD-named unit tests against `APIClient` stubs cover that endpoint (happy path, invalid input, API failure, empty/boundary — PLAN.md §7). No box is checked speculatively.

- Source of truth for the endpoint inventory: https://interlinedlist.com/help/api (verified 2026-06-11), cross-checked against PLAN.md §1.
- ☐ = not done, ☑ = done, ◐ = **partial** (builder + DTO + service path merged and at least one behavior test exists, but not all four of happy/invalid/failure/empty are present yet — see footnote 4). All rows start unchecked.
- **Auth** column reproduces the API reference's annotation. Groups marked *Session* are subject to the M0 Bearer-vs-Session spike (`docs/spikes/auth-bearer-vs-session.md`, decision in `docs/decisions/0001-auth-transport.md`).
- The three `GET /api/users/[username]/lists*` endpoints appear in the API reference under both **Lists** and **Public**; they are listed once here, under **Lists**, with no-auth noted.

| Endpoint (method + path) | Group | Auth | Planned service | Milestone | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `POST /api/auth/login` | Auth | Public → session cookie | AuthService (InterlinedKit/Auth) | M0 | ☐⁵ | ☐ |
| `POST /api/auth/logout` | Auth | Session | AuthService (InterlinedKit/Auth) | M0 | ☑ | ◐⁴ |
| `POST /api/auth/register` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☑ | ☐⁶ |
| `POST /api/auth/sync-token` | Auth | Public → Bearer token | AuthService (InterlinedKit/Auth) | M0 | ☑ | ◐⁴ |
| `POST /api/auth/forgot-password` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☑ | ◐⁴ |
| `POST /api/auth/reset-password` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☑ | ◐⁴ |
| `POST /api/auth/send-verification-email` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☑ | ◐⁴ |
| `POST /api/auth/verify-email` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☑ | ◐⁴ |
| `GET /api/auth/github/authorize` | Auth (OAuth) | Public | AuthService (OAuth flows) | M6 | ☐ | ☐ |
| `GET /api/auth/mastodon/authorize` | Auth (OAuth) | Public | AuthService (OAuth flows) | M6 | ☐ | ☐ |
| `GET /api/auth/bluesky/authorize` | Auth (OAuth) | Public | AuthService (OAuth flows) | M6 | ☐ | ☐ |
| `GET /api/auth/linkedin/authorize` | Auth (OAuth) | Public | AuthService (OAuth flows) | M6 | ☐ | ☐ |
| `GET /api/user` | User | Session or Bearer | UserService¹ (+ EntitlementsService reads `customerStatus`) | M0 | ☑ | ☑ |
| `POST /api/user/update` | User | Session | UserService¹ | M7 | ☑ | ☑ |
| `POST /api/user/avatar/upload` | User | Session | UserService¹ | M7 | ☑ | ◐⁴ |
| `POST /api/user/avatar/from-url` | User | Session | UserService¹ | M7 | ☑ | ◐⁴ |
| `GET /api/user/identities` | User | Session | UserService¹ | M6 | ☑ | ◐⁴ |
| `GET /api/user/organizations` | User | Session | UserService¹ ⁷ | M6 | ☑ | ◐⁴ |
| `POST /api/user/change-email/request` | User | Session | UserService¹ | M7 | ☑ | ◐⁴ |
| `POST /api/user/delete` | User | Session | UserService¹ | M7 | ☑ | ◐⁴ |
| `GET /api/messages` | Messages | Session or Bearer | MessagesService | M1 | ☑ | ☑ |
| `POST /api/messages` | Messages | Session or Bearer | MessagesService | M2² | ☑ | ☑ |
| `GET /api/messages/[id]` | Messages | Session or Bearer | MessagesService | M1 | ☑ | ☑ |
| `PUT /api/messages/[id]` | Messages | Session or Bearer | MessagesService | M2 | ☑ | ☑ |
| `DELETE /api/messages/[id]` | Messages | Session or Bearer | MessagesService | M2 | ☑ | ☑ |
| `GET /api/messages/scheduled` | Messages | Session or Bearer | MessagesService | M6 | ☑ | ☑ |
| `GET /api/messages/[id]/replies` | Messages | Session | MessagesService | M1 | ☑ | ☑ |
| `POST /api/messages/[id]/dig` | Messages | Session | MessagesService | M2 | ☑ | ☑ |
| `DELETE /api/messages/[id]/dig` | Messages | Session | MessagesService | M2 | ☑ | ☑ |
| `POST /api/messages/images/upload` | Messages | Session or Bearer | MessagesService | M6 | ☑ | ◐⁴ |
| `POST /api/messages/videos/upload` | Messages | Session or Bearer | MessagesService | M6 | ☑ | ◐⁴ |
| `GET /api/lists` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `POST /api/lists` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `GET /api/lists/[id]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `PUT /api/lists/[id]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `DELETE /api/lists/[id]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `GET /api/lists/[id]/schema` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `PUT /api/lists/[id]/schema` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `POST /api/lists/[id]/refresh` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `GET /api/lists/[id]/data` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `POST /api/lists/[id]/data` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `GET /api/lists/[id]/data/[rowId]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `PATCH /api/lists/[id]/data/[rowId]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `DELETE /api/lists/[id]/data/[rowId]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `GET /api/lists/[id]/watchers` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `GET /api/lists/[id]/watchers/me` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `GET /api/lists/[id]/watchers/users` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `PUT /api/lists/[id]/watchers/[userId]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `DELETE /api/lists/[id]/watchers/[userId]` | Lists | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `GET /api/users/[username]/lists` | Lists (public) | None | ListsService | M1 | ☑ | ☑ |
| `GET /api/users/[username]/lists/[id]` | Lists (public) | None | ListsService | M1 | ☑ | ☑ |
| `GET /api/users/[username]/lists/[id]/data` | Lists (public) | None | ListsService | M1 | ☑ | ☑ |
| `GET /api/lists/connections` | List Connections | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `POST /api/lists/connections` | List Connections | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `DELETE /api/lists/connections/[id]` | List Connections | Session or Bearer | ListsService | M3 | ☑ | ◐⁴ |
| `GET /api/documents/sync` | Documents & Sync | Session or Bearer | DocumentSyncEngine (InterlinedPersistence) | M4 | ☑ | ◐⁴ |
| `POST /api/documents/sync` | Documents & Sync | Session or Bearer | DocumentSyncEngine (InterlinedPersistence) | M4 | ☑ | ◐⁴ |
| `GET /api/documents` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴ |
| `POST /api/documents` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴ |
| `GET /api/documents/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴ |
| `PATCH /api/documents/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴ |
| `DELETE /api/documents/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴ |
| `POST /api/documents/[id]/images/upload` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴ |
| `GET /api/documents/folders` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴ |
| `POST /api/documents/folders` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴ |
| `GET /api/documents/folders/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴ |
| `PATCH /api/documents/folders/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴ |
| `DELETE /api/documents/folders/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴ |
| `GET /api/documents/folders/[id]/documents` | Documents & Sync | Session | DocumentsService | M4 | ☑ | ◐⁴ |
| `POST /api/follow/[userId]` | Follow | Session | SocialService | M5 | ☑ | ◐⁴ |
| `DELETE /api/follow/[userId]` | Follow | Session | SocialService | M5 | ☑ | ◐⁴ |
| `GET /api/follow/[userId]/status` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `GET /api/follow/[userId]/followers` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `GET /api/follow/[userId]/following` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `GET /api/follow/[userId]/counts` | Follow | Session | SocialService | M5 | ☑ | ☑ |
| `GET /api/follow/[userId]/mutual` | Follow | Session | SocialService | M5 | ☑ | ◐⁴ |
| `POST /api/follow/[userId]/approve` | Follow | Session | SocialService | M5 | ☑ | ◐⁴ |
| `POST /api/follow/[userId]/reject` | Follow | Session | SocialService | M5 | ☑ | ◐⁴ |
| `POST /api/follow/[userId]/remove` | Follow | Session | SocialService | M5 | ☑ | ◐⁴ |
| `GET /api/follow/requests` | Follow | Session | SocialService | M5 | ☑ | ◐⁴ |
| `GET /api/organizations` | Organizations | Session | OrgService | M6 | ☑ | ◐⁴ |
| `POST /api/organizations` | Organizations | Session | OrgService | M6 | ☑ | ◐⁴ |
| `GET /api/organizations/[id]` | Organizations | Session | OrgService | M6 | ☑ | ◐⁴ |
| `PATCH /api/organizations/[id]` | Organizations | Session | OrgService | M6 | ☑ | ◐⁴ |
| `GET /api/organizations/[id]/members` | Organizations | Session | OrgService | M6 | ☑ | ◐⁴ |
| `POST /api/organizations/[id]/members` | Organizations | Session | OrgService | M6 | ☑ | ◐⁴ |
| `PUT /api/organizations/[id]/members/[userId]` | Organizations | Session | OrgService | M6 | ☑ | ◐⁴ |
| `DELETE /api/organizations/[id]/members/[userId]` | Organizations | Session | OrgService | M6 | ☑ | ◐⁴ |
| `GET /api/organizations/[id]/users` | Organizations | Session | OrgService | M6 | ☑ | ◐⁴ |
| `GET /api/exports/messages` | Exports | Session | ExportsService¹ | M7 | ☑ | ◐⁴ |
| `GET /api/exports/lists` | Exports | Session | ExportsService¹ | M7 | ☑ | ◐⁴ |
| `GET /api/exports/list-data-rows` | Exports | Session | ExportsService¹ | M7 | ☑ | ◐⁴ |
| `GET /api/exports/follows` | Exports | Session | ExportsService¹ | M7 | ☑ | ◐⁴ |
| `GET /api/notifications` | Notifications | Session | NotificationsService | M5 | ☑ | ☑ |
| `PATCH /api/notifications/[id]/read` | Notifications | Session | NotificationsService | M5 | ☑ | ◐⁴ |
| `POST /api/notifications/mark-all-read` | Notifications | Session | NotificationsService | M5 | ☑ | ◐⁴ |
| `GET /api/user/[username]/messages` | Public | None | MessagesService⁸ | M1 | ☑ | ☑ |
| `GET /api/auth/linkedin/status` | Public | None | AuthService (OAuth flows) | M6 | ☐ | ☐ |

**Totals:** 98 endpoints — Auth 12 · User 8 · Messages 11 · Lists 21 (incl. 3 public) · List Connections 3 · Documents & Sync 14 · Follow 11 · Organizations 9 · Exports 4 · Notifications 3 · Public-only 2.

## Footnotes and assumptions

1. **UserService / ExportsService** were not explicitly named in PLAN.md §3 (its service list ends with an ellipsis: "MessagesService, ListsService, DocumentsService, SocialService, OrgService, NotificationsService…"). Wave 1 confirmed the convention: the User endpoint group ships as `InterlinedKit.User` (see `Packages/InterlinedKit/Sources/InterlinedKit/Endpoints/UserEndpoint.swift`) and the Exports group as `InterlinedKit.Exports` (`ExportsEndpoint.swift`); domain-side `UserService` / `ExportsService` wrappers are deferred to the milestone in which the consuming UI lands (M6/M7).
2. `POST /api/messages` ships in M2 for plain posting; its scheduled-post (`scheduledAt`) and cross-posting (`mastodonProviderIds`, `crossPostToBluesky`, `crossPostToLinkedIn`) request fields land in M6. The row is checked Implemented at M2; the M6 wave update must confirm the extended fields are covered before the row counts toward M6. Wave 1 note: `MessagesEndpointTests.test_givenCrossPostAndScheduled_whenCreateBuilt_thenEncodesAllSetFields` already exercises encoding for the M6 fields against the builder.
3. Repost (`pushedMessageId`), visibility, and tag filters are request/response fields on existing rows above, not separate endpoints — they carry no row of their own.
4. **Partial test coverage (◐).** The row's request builder, DTOs, and `APIClient.send` path are merged and at least one behavior test exists (typically builder-shape assertion plus one or two of happy/invalid/failure/empty), but the full happy + invalid + failure + empty/boundary quartet required by PLAN.md §7 is not yet present for that specific endpoint. APIClient-level failure decoding is exercised exhaustively in `APIClientTests` / `APIErrorTests`, so per-endpoint failure paths inherit correct error mapping; the gap is dedicated per-endpoint behavior tests. To be backfilled in the milestone in which the row's domain service lands, before the row counts toward that milestone's gate.
5. `POST /api/auth/login` (cookie-session credential exchange) is intentionally not implemented in Wave 1. Decision 0001 makes the Bearer token the primary transport; cookie-session login is needed only for the small session-only allowlist (`/api/user/identities`, `/api/user/organizations`, `/api/exports/*`, `/api/auth/logout`), and is currently stubbed via `NullSessionEstablisher`. A working `SessionEstablisher` calling `POST /api/auth/login` will land alongside the first feature that consumes a session-only endpoint (the Exports menu in M7 or earlier if a feature requires it sooner).
6. `POST /api/auth/register` ships as `AuthService.register` and is exercised by the live `ContractTests` when `INTERLINEDLIST_EMAIL` / `INTERLINEDLIST_PASSWORD` are present, but has no stubbed unit-test cases yet (only `signIn` has dedicated unit tests in `AuthServiceTests`). Tested ☐ until at least happy + invalid + failure + empty/boundary unit tests are added (likely in the onboarding-feature wave).
7. `GET /api/user/organizations` lives in `InterlinedKit.User.organizations()` (not `Organizations.*`) because the live API path is `/api/user/organizations`, not `/api/organizations`. Planned-service column corrected from `OrgService` to `UserService¹` in Wave 1 to match the actual implementation.
8. **No public profile read endpoint exists on the live API.** PLAN.md §1 (Profile row) and §6 M1 ("user profiles") imply a `GET /api/users/[username]` route, but the 2026-06-21 kit-gap spike confirmed every reasonable variation (`/api/users/[username]`, `/api/user/[username]`, `/api/users/[username]/{profile,public}`, `/api/profile/[username]`, `/api/u/[username]`, `/api/public/users/[username]`, `/api/users/[username]/{followers,following}`) returns 404, while the username pattern is otherwise valid (`/api/users/[username]/lists` and `/api/user/[username]/messages` return 200 for the same handle). No such row appears in this matrix because the endpoint is not in the live reference. Decision [`0002-public-profile-fallback`](decisions/0002-public-profile-fallback.md) records the M1 fallback: `SocialService.profile(username:)` reduces to the embedded `{ id, username, displayName, avatar }` author object on the first message returned by `GET /api/user/[username]/messages`. When the upstream endpoint lands, add the row here and check it off against the direct implementation.

## Cross-check against PLAN.md §1 (2026-06-11)

- Every API surface named in PLAN.md §1 maps to at least one row above. No PLAN.md endpoint is missing from the live reference.
- Present in the live reference but not explicitly named in PLAN.md §1: `POST /api/auth/logout` (implied by the auth feature), `GET /api/auth/linkedin/status` (supports the LinkedIn cross-post/OAuth feature, M6), and `GET /api/user/[username]/messages` (public user messages; nearest §1 feature is user profiles, M1 — and after the 2026-06-21 spike, this row carries the M1 profile fallback per decision 0002 and footnote 8).
- **PLAN.md §1 surface with no live endpoint:** the Profile-row's natural backing call `GET /api/users/[username]` does not exist on the live API (2026-06-21 spike). Captured in footnote 8 and decision [`0002-public-profile-fallback`](decisions/0002-public-profile-fallback.md); no row added to the matrix above until the upstream endpoint ships.
- PLAN.md §4's "Session-only" list (replies, digs, follow, organizations, notifications, document CRUD) matches the live annotations. The live reference additionally marks the User group's write endpoints and Exports as Session — the M0 spike should probe these groups too.

## Update history

- **2026-06-22 — Wave 3 update (M2 posting consumed end-to-end).** Decision [`0003-kit-import-policy`](decisions/0003-kit-import-policy.md) recorded; `InterlinedDomain.MessagesService` gained the M2 write surface (`create`, `reply`, `repost`, `update(messageId:…)`, `delete(messageId:)`, `dig(messageId:)`, `undig(messageId:)`) per commit `c07ac8a`; App-layer Composer / inline-reply / optimistic-dig / repost / edit / delete UI landed in the follow-on commit (`InterlinedListTests` 44/44 passing). Per the Wave 1 protocol in footnote 4, every M2-consumed row that was partial (◐⁴) after Wave 2 is now fully tested (☑) end-to-end (Kit builder → Domain service → App view-model). Four rows flipped ◐⁴ → ☑: `PUT /api/messages/[id]`, `DELETE /api/messages/[id]`, `POST /api/messages/[id]/dig`, `DELETE /api/messages/[id]/dig`. `POST /api/messages` was already ☑ from Wave 1 (cross-post-fields builder coverage) and is re-exercised this wave by all three App-layer entry points (`create`, `reply`, `repost`) — row state unchanged. `GET /api/user` was already ☑ from Wave 2 and is additionally consumed this wave by the App-layer `CurrentUserStore` for ownership gating — row state unchanged. The cross-post / scheduled / media request fields on `POST /api/messages` remain M6 per footnote 2. **Implemented: 92 of 98 (unchanged). Tested: 20 of 98 fully (☑), 71 of 98 partial (◐⁴), 6 untested ☐ plus 1 untested-with-context ☐⁶.** No new footnotes added.
- **2026-06-21 — Wave 2 update (M1 read-only core consumed).** Domain (`InterlinedDomain`) services + Persistence (`InterlinedPersistence`) SwiftData cache + App-layer Timeline / Lists / Profile UI landed for PLAN.md §6 M1. Per the Wave 1 protocol in footnote 4, every M1-consumed row was promoted from partial (◐⁴) to full (☑) at the domain-service layer. Ten rows flipped: `GET /api/messages`, `GET /api/messages/[id]/replies`, `GET /api/users/[username]/lists`, `GET /api/users/[username]/lists/[id]`, `GET /api/users/[username]/lists/[id]/data`, `GET /api/follow/[userId]/status`, `GET /api/follow/[userId]/followers`, `GET /api/follow/[userId]/following`, `GET /api/follow/[userId]/counts`, and `GET /api/user/[username]/messages`. (`GET /api/messages/[id]` was already ☑ from Wave 1 and is not in the flip count.) **Implemented: 92 of 98 (unchanged). Tested: 16 of 98 fully (☑), 75 of 98 partial (◐⁴), 6 untested ☐ plus 1 untested-with-context ☐⁶.** No new footnotes added.
- **2026-06-21 — Public profile gap recorded.** 2026-06-21 kit-gap spike confirmed `GET /api/users/[username]` (and every reasonable variation) does not exist on the live API. Footnote 8 added; `GET /api/user/[username]/messages` row annotated with footnote 8 to mark its role as the M1 profile fallback carrier per decision [`0002-public-profile-fallback`](decisions/0002-public-profile-fallback.md). No row added to the matrix; no Implemented / Tested counts change.
- **2026-06-18 — Wave 1 update.** InterlinedKit endpoint groups (Auth additive, User, Messages, Lists, Documents & Sync, Follow, Organizations, Notifications, Exports) merged in commits `86eea76`, `a1e6d1c`, `6ed194a`. **Implemented: 92 of 98** (the 6 unimplemented rows are `POST /api/auth/login` ⁵, the four OAuth `authorize` endpoints, and `GET /api/auth/linkedin/status` — all M6/M7). **Tested: 6 of 98 fully (☑), 85 of 98 partial (◐⁴), 6 untested ☐ plus 1 untested-with-context ☐⁶.** Footnote 1 resolved (planned-service column matches code). Footnote 7 added: `GET /api/user/organizations` belongs to the `User` namespace, not `Organizations`. Footnotes 5 (login deferred) and 6 (register lacks dedicated stubbed unit tests) added.
