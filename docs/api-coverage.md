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
9. **M3 reachable but not exercised by a tested App-layer view model this wave.** Per Wave 1 footnote 4, a row only flips ◐⁴ → ☑ when an App-layer consumer drives it end-to-end under test. Four Lists rows are wired through `ListsService` and reachable from the running app but their consuming UX was held back to a polish slice this wave: `GET /api/lists/[id]` and `PUT /api/lists/[id]` (the detail-rename / single-list-refresh paths — rename UX deferred), `GET /api/lists/[id]/data/[rowId]` (single-row hydration — `RowInspectorView` reads from the already-paginated `ListRowsViewModel.rows` array), and `GET /api/lists/[id]/watchers` (the watcher pagination envelope — `WatchersView` consumes `/users` only this wave). These rows stay ◐⁴ until the next M3 polish wave consumes them through a tested view model. The Wave 1 footnote-4 backfill rule still applies.
10. **M4 detail-read rows reachable but not view-model-tested this wave.** Same pattern as footnote 9, applied to Documents. `GET /api/documents/[id]` and `GET /api/documents/folders/[id]` are wired through `DocumentsService.document(id:)` / `DocumentsService.folder(id:)` and reachable from the running app, but the Wave 5.3 App-layer view models (`DocumentsListViewModel`, `DocumentEditorViewModel`, `FolderTreeViewModel`) consume documents and folders from the **list** payload (`GET /api/documents`, `GET /api/documents/folders[/[id]/documents]`) and the **sync delta** payload rather than re-reading by id. The detail-read endpoints stay ◐⁴ until a polish slice consumes them through a tested view-model path (a likely candidate: a single-document deep-link / quick-look refresh, or a focused folder-rename inspector that re-hydrates from `folder(id:)`). The Wave 1 footnote-4 backfill rule still applies.

## Cross-check against PLAN.md §1 (2026-06-11)

- Every API surface named in PLAN.md §1 maps to at least one row above. No PLAN.md endpoint is missing from the live reference.
- Present in the live reference but not explicitly named in PLAN.md §1: `POST /api/auth/logout` (implied by the auth feature), `GET /api/auth/linkedin/status` (supports the LinkedIn cross-post/OAuth feature, M6), and `GET /api/user/[username]/messages` (public user messages; nearest §1 feature is user profiles, M1 — and after the 2026-06-21 spike, this row carries the M1 profile fallback per decision 0002 and footnote 8).
- **PLAN.md §1 surface with no live endpoint:** the Profile-row's natural backing call `GET /api/users/[username]` does not exist on the live API (2026-06-21 spike). Captured in footnote 8 and decision [`0002-public-profile-fallback`](decisions/0002-public-profile-fallback.md); no row added to the matrix above until the upstream endpoint ships.
- PLAN.md §4's "Session-only" list (replies, digs, follow, organizations, notifications, document CRUD) matches the live annotations. The live reference additionally marks the User group's write endpoints and Exports as Session — the M0 spike should probe these groups too.

## Update history

- **2026-06-23 — Wave 5 update (M4 Documents consumed end-to-end).** `InterlinedDomain` Documents slice (`Document`, `FolderNode`, `DocumentSyncEvent`, `DocumentChange`, `DocumentMappers`, `ImagePrep`, `DocumentsService`, `DocumentSyncTransport`) and `InterlinedPersistence` (`DocumentRecord`, `FolderRecord`, `OutboxEntryRecord`, `SyncStateRecord`, `SwiftDataDocumentStore`, `DocumentSyncEngine`) shipped in commit `daf1eef`; App-layer Documents UI (`DocumentsRootView`, `DocumentsSidebarView` + `FolderTreeViewModel`, `DocumentsListView` + `DocumentsListViewModel`, `DocumentEditorView` + `DocumentEditorViewModel`, `ConflictBannerView`, `SyncStatusView` + `SyncStatusViewModel`, `DocumentsMenuCommands`, `KitDocumentSyncTransport` wiring) shipped in commit `babb6d2`. Per the Wave 1 protocol in footnote 4, every M4-consumed Documents & Sync row exercised by a tested App-layer view model this wave is now fully tested (☑) end-to-end (Kit builder → Domain service → App view-model). **12 rows flipped ◐⁴ → ☑**: `GET /api/documents/sync` (`KitDocumentSyncTransport.pullDelta` via `DocumentSyncEngine.syncNow` via `SyncStatusViewModel.syncNow`), `POST /api/documents/sync` (`KitDocumentSyncTransport.pushChange` via `DocumentSyncEngine.syncNow` outbox push), `GET /api/documents` (`DocumentsService.documents(in:limit:offset:)` when folder is nil → `DocumentsListViewModel.reload`), `POST /api/documents` (`DocumentsService.create` → `DocumentsListViewModel.createDocument`), `PATCH /api/documents/[id]` (`DocumentsService.update` → `DocumentEditorViewModel.saveNow`), `DELETE /api/documents/[id]` (`DocumentsService.delete` → `DocumentsListViewModel.deleteDocument`), `POST /api/documents/[id]/images/upload` (`DocumentsService.uploadImage` → `DocumentEditorViewModel.uploadImage`; `ImagePrep` is exercised in the upload path), `GET /api/documents/folders` (`DocumentsService.folders` → `FolderTreeViewModel.initialLoad`), `POST /api/documents/folders` (`DocumentsService.createFolder` → `FolderTreeViewModel.createFolder`), `PATCH /api/documents/folders/[id]` (`DocumentsService.renameFolder` → `FolderTreeViewModel.renameFolder`), `DELETE /api/documents/folders/[id]` (`DocumentsService.deleteFolder` → `FolderTreeViewModel.deleteFolder`), `GET /api/documents/folders/[id]/documents` (`DocumentsService.documents(in:limit:offset:)` when folderID != nil → `DocumentsListViewModel.reload`). **Two Documents & Sync rows stay ◐⁴ — held back** as documented in new footnote 10: `GET /api/documents/[id]` and `GET /api/documents/folders/[id]` are reachable via `DocumentsService.document(id:)` / `folder(id:)` but the Wave 5.3 view models open documents and folders from the list payload (and from the sync delta) rather than re-reading by id. **Math: Implemented 92 of 98 (unchanged); Tested fully 35 → 47 of 98 (+12); Tested partial 56 → 44 of 98 (−12); Untested 7 of 98 (unchanged).** Footnote 10 added. No other footnotes touched.
- **2026-06-23 — Wave 4 update (M3 Lists consumed end-to-end).** `InterlinedDomain` Lists write surface + schema DSL + `InterlinedPersistence` SwiftData lists cache shipped in commit `415c5c2`; App-layer Lists UI (owned-lists root, schema editor, rows table, row inspector, watchers, connections graph) shipped in commits `461e7df` + `155c955` (view models) + `099d8d9` (views, sidebar router, menu commands). Per the Wave 1 protocol in footnote 4, every M3-consumed row that was partial (◐⁴) and is exercised by a tested App-layer view model this wave is now fully tested (☑) end-to-end (Kit builder → Domain service → App view-model). **15 rows flipped ◐⁴ → ☑**: `DELETE /api/lists/[id]`, `GET /api/lists/[id]/schema`, `PUT /api/lists/[id]/schema`, `POST /api/lists/[id]/refresh`, `GET /api/lists/[id]/data`, `POST /api/lists/[id]/data`, `PATCH /api/lists/[id]/data/[rowId]`, `DELETE /api/lists/[id]/data/[rowId]`, `GET /api/lists/[id]/watchers/me`, `GET /api/lists/[id]/watchers/users`, `PUT /api/lists/[id]/watchers/[userId]`, `DELETE /api/lists/[id]/watchers/[userId]`, `GET /api/lists/connections`, `POST /api/lists/connections`, `DELETE /api/lists/connections/[id]`. **Four Lists rows stay ◐⁴ — held back** as documented in new footnote 9: `GET /api/lists/[id]`, `PUT /api/lists/[id]`, `GET /api/lists/[id]/data/[rowId]`, `GET /api/lists/[id]/watchers` (reachable via `ListsService` but not exercised by a tested view model this wave). `GET /api/lists` and `POST /api/lists` likewise stay ◐⁴ for this wave — their App-layer consumers (`OwnedListsViewModel.initialLoad` / `loadMore`, `NewListViewModel.submit` + `ListDetailViewModel.saveToMyLists`) exercise the request path but the M3 polish slice will pin the full happy + invalid + failure + empty/boundary quartets at the view-model layer before they flip. The three public-Lists rows (`GET /api/users/[username]/lists*`) were already ☑ from Wave 2. **Math: Implemented 92 of 98 (unchanged); Tested fully 20 → 35 of 98 (+15); Tested partial 71 → 56 of 98 (−15); Untested 7 of 98 (unchanged).** Footnote 9 added. No other footnotes touched.
- **2026-06-22 — Wave 3 update (M2 posting consumed end-to-end).** Decision [`0003-kit-import-policy`](decisions/0003-kit-import-policy.md) recorded; `InterlinedDomain.MessagesService` gained the M2 write surface (`create`, `reply`, `repost`, `update(messageId:…)`, `delete(messageId:)`, `dig(messageId:)`, `undig(messageId:)`) per commit `c07ac8a`; App-layer Composer / inline-reply / optimistic-dig / repost / edit / delete UI landed in the follow-on commit (`InterlinedListTests` 44/44 passing). Per the Wave 1 protocol in footnote 4, every M2-consumed row that was partial (◐⁴) after Wave 2 is now fully tested (☑) end-to-end (Kit builder → Domain service → App view-model). Four rows flipped ◐⁴ → ☑: `PUT /api/messages/[id]`, `DELETE /api/messages/[id]`, `POST /api/messages/[id]/dig`, `DELETE /api/messages/[id]/dig`. `POST /api/messages` was already ☑ from Wave 1 (cross-post-fields builder coverage) and is re-exercised this wave by all three App-layer entry points (`create`, `reply`, `repost`) — row state unchanged. `GET /api/user` was already ☑ from Wave 2 and is additionally consumed this wave by the App-layer `CurrentUserStore` for ownership gating — row state unchanged. The cross-post / scheduled / media request fields on `POST /api/messages` remain M6 per footnote 2. **Implemented: 92 of 98 (unchanged). Tested: 20 of 98 fully (☑), 71 of 98 partial (◐⁴), 6 untested ☐ plus 1 untested-with-context ☐⁶.** No new footnotes added.
- **2026-06-21 — Wave 2 update (M1 read-only core consumed).** Domain (`InterlinedDomain`) services + Persistence (`InterlinedPersistence`) SwiftData cache + App-layer Timeline / Lists / Profile UI landed for PLAN.md §6 M1. Per the Wave 1 protocol in footnote 4, every M1-consumed row was promoted from partial (◐⁴) to full (☑) at the domain-service layer. Ten rows flipped: `GET /api/messages`, `GET /api/messages/[id]/replies`, `GET /api/users/[username]/lists`, `GET /api/users/[username]/lists/[id]`, `GET /api/users/[username]/lists/[id]/data`, `GET /api/follow/[userId]/status`, `GET /api/follow/[userId]/followers`, `GET /api/follow/[userId]/following`, `GET /api/follow/[userId]/counts`, and `GET /api/user/[username]/messages`. (`GET /api/messages/[id]` was already ☑ from Wave 1 and is not in the flip count.) **Implemented: 92 of 98 (unchanged). Tested: 16 of 98 fully (☑), 75 of 98 partial (◐⁴), 6 untested ☐ plus 1 untested-with-context ☐⁶.** No new footnotes added.
- **2026-06-21 — Public profile gap recorded.** 2026-06-21 kit-gap spike confirmed `GET /api/users/[username]` (and every reasonable variation) does not exist on the live API. Footnote 8 added; `GET /api/user/[username]/messages` row annotated with footnote 8 to mark its role as the M1 profile fallback carrier per decision [`0002-public-profile-fallback`](decisions/0002-public-profile-fallback.md). No row added to the matrix; no Implemented / Tested counts change.
- **2026-06-18 — Wave 1 update.** InterlinedKit endpoint groups (Auth additive, User, Messages, Lists, Documents & Sync, Follow, Organizations, Notifications, Exports) merged in commits `86eea76`, `a1e6d1c`, `6ed194a`. **Implemented: 92 of 98** (the 6 unimplemented rows are `POST /api/auth/login` ⁵, the four OAuth `authorize` endpoints, and `GET /api/auth/linkedin/status` — all M6/M7). **Tested: 6 of 98 fully (☑), 85 of 98 partial (◐⁴), 6 untested ☐ plus 1 untested-with-context ☐⁶.** Footnote 1 resolved (planned-service column matches code). Footnote 7 added: `GET /api/user/organizations` belongs to the `User` namespace, not `Organizations`. Footnotes 5 (login deferred) and 6 (register lacks dedicated stubbed unit tests) added.
