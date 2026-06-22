# Orchestration Progress Log

**Audience:** engineering (orchestrator, implementing agents, maintainers).

This is the running progress log required by [ORCHESTRATION.md](../ORCHESTRATION.md). [PLAN.md](../PLAN.md) and ORCHESTRATION.md are **read-only** for everyone, including the orchestrator — all progress, wave gates, and deviations are recorded here and in git commits, never by editing the plan. Waves map 1:1 to PLAN.md §6 milestones. Append entries per wave; do not rewrite history in this file — correct earlier entries with a dated note.

Companion documents: endpoint status lives in [api-coverage.md](api-coverage.md) (updated at the end of each wave); recorded decisions live in `docs/decisions/`; spike findings live in `docs/spikes/`.

---

## Wave 0 — Foundation (PLAN.md §6 M0)

### 0.1 — Repository initialization — DONE
- `git init`, Swift/Xcode `.gitignore`, initial commit of plan, orchestration prompt, Claude agents and skills.
- Commit: `cc0c8f1`.

### 0.2 — Project scaffold — DONE
- Xcode 16 project using filesystem-synchronized (buildable) folder groups, so adding source files does not touch `project.pbxproj` (the serialization-point mitigation from ORCHESTRATION.md).
- App target: macOS 14 minimum, Swift 6 toolchain.
- Three SPM packages per PLAN.md §3: `InterlinedKit`, `InterlinedDomain`, `InterlinedPersistence`, each with a test target.
- 9 BDD-named tests passing across the packages; everything builds.
- Commit: `059606f`.

### 0.3 — Parallel foundation tasks — IN FLIGHT
Launched in parallel per ORCHESTRATION.md Wave 0 step 3 (non-overlapping path ownership):

| Task | Owner paths | Deliverable | Status |
| --- | --- | --- | --- |
| 0.3a — Auth spike (PLAN.md §4): probe Session-only endpoint groups with a Bearer token against the live API | `docs/spikes/` | `docs/spikes/auth-bearer-vs-session.md` | **BLOCKED** — invalid credentials (see below); no deliverable written (refused to fabricate) |
| 0.3b — Branding (PLAN.md §9): brand kit download, 1024px icon from SVG, AppIcon set, Color Sets | `App/Resources/**`, `Brand/` | Asset catalogs per §9 tables | DONE — build-verified; 4 deviations flagged below |
| 0.3c — CI: GitHub Actions build + test on macOS runner | `.github/workflows/**` | `.github/workflows/ci.yml` | DONE — YAML validated by orchestrator (`python3 -c yaml.safe_load` → valid); first real run pending push |
| 0.3d — Docs scaffolding | `docs/**` | `docs/api-coverage.md` (98-endpoint matrix, all unchecked) + `docs/progress.md` | DONE (2026-06-11) |

**0.3b branding deviations** (from PLAN.md §9, full detail in agent report): (1) the `interlinedlist-logo-only.png` named on the branding page is absent from the kit zip and 404s on the site — the site favicon `logo-icon.png` (321×321) was curated into `Brand/icon/` as the mark; PLAN.md §9's "canonical icon mark" line should be amended. (2) Solid-bg icon variants ship only at 64–512; missing sizes (16, 32, 1024) rasterized from the official SVG onto white via CoreGraphics (no PNG upscaled). (3) `ATSApplicationFontsPath` set to `.` not `Fonts` because the synchronized folder group flattens `Fonts/` into `Contents/Resources/`. (4) `SurfaceNested` light analog chosen as `#F5F5F5` (spec defines dark only).

### Wave 0 gate — PASSED (2026-06-15)

- App build: `xcodebuild … -scheme InterlinedList -destination 'platform=macOS' build` → **BUILD SUCCEEDED** (brand asset catalog validates via actool).
- Package tests: InterlinedKit 4/4, InterlinedDomain 3/3, InterlinedPersistence 2/2 — **9/9 passing**.
- Path-ownership check: untracked top-level paths limited to `.github`, `App`, `Brand`, `docs` — no overlaps; conflict rules held.
- Commit: `<recorded in this commit>`.
- Coverage matrix delta: baseline created (98 endpoints, 0 implemented, 0 tested).

### Auth transport decision — RECORDED & spike RESOLVED (2026-06-15)
See [decisions/0001-auth-transport.md](decisions/0001-auth-transport.md) and [spikes/auth-bearer-vs-session.md](spikes/auth-bearer-vs-session.md).

- **Spike resolved:** user supplied working credentials; read-only probe ran in full. **Bearer works on nearly the whole surface** (incl. Notifications, Follow, Organizations, Documents, document folders, message replies — all 200). Bearer is rejected (401) on only **~6 endpoints**: `GET /api/user/identities`, `GET /api/user/organizations`, and the four `GET /api/exports/*` CSV endpoints.
- **Decision:** `AuthTransport` seam — **Bearer default for everything**, **lazy cookie-session fallback** scoped to that ~6-endpoint allowlist; runtime 401-retry safety net for drift. Simpler than the conservative fallback the docs implied.
- **Wave 1 carry-in:** every Wave 1 task prompt must cite decision 0001 — Bearer primary, lazy session fallback for the allowlist only.

---

_Wave 1 (InterlinedKit core) and later entries are appended below this line as waves complete._

---

## Wave 1 — InterlinedKit core (PLAN.md §6 M0 closure → InterlinedKit slice of every milestone)

Wave 1 builds the request-builder + DTO layer for every documented endpoint group inside `Packages/InterlinedKit`, leaving service-layer composition (per PLAN.md §3) for the milestone in which each domain service first lands. Path ownership stayed inside `Packages/InterlinedKit/Sources/InterlinedKit/{Endpoints,DTOs,Auth,APIClient,Errors,Pagination}/**` and `Packages/InterlinedKit/Tests/InterlinedKitTests/**`; no app, persistence, or docs paths were touched outside this update.

### 1.1 — APIClient + Auth/TokenStore + error mapping + pagination — DONE
- `APIClient` (`Packages/InterlinedKit/Sources/InterlinedKit/APIClient/`) — protocol + `URLSession`-backed implementation with `send`, `sendVoid`, and `sendRaw` (CSV exports), plus the 401 safety-net that retries through the cookie-session transport when a Bearer request is rejected (decision 0001).
- `TokenStore` (Keychain-backed) and `InMemoryTokenStore` test double.
- `AuthTransport` seam (`DefaultAuthTransport` + `SessionEstablisher` protocol with `NullSessionEstablisher` test double) — the implementation half of the decision-0001 Bearer-default / lazy-session-fallback design.
- `APIError` mapping for the `{ "error": ... }` body and HTTP status families (`badRequest`, `unauthorized`, `forbidden`, `notFound`, `httpStatus`, `decoding`, `transport`).
- `Paginated<T>` + `PaginationInfo` + `PaginatedDecoder` (collection-key-driven) + `PageIterator`.

### 1.2 — Messages / User / Auth endpoint groups + live contract test — DONE
- Commit: `86eea76`.
- `Endpoints/MessagesEndpoint.swift` + `DTOs/MessageDTO.swift`: 11 Messages rows including `Paginated` for `list` / `userMessages`, non-standard envelopes for `scheduled` (`ScheduledMessagesResponse`) and `replies` (`RepliesResponse`), `dig`/`undig`, and raw-body uploads.
- `Endpoints/UserEndpoint.swift` + `DTOs/UserDTO.swift`: 8 User rows; the two confirmed session-only reads (`/api/user/identities`, `/api/user/organizations`) carry `auth: .session` per decision 0001.
- `Endpoints/AuthEndpoint.swift` + `DTOs/AuthDTO.swift`: 5 additive Auth rows (`forgotPassword`, `resetPassword`, `sendVerificationEmail`, `verifyEmail`, `logout`). `AuthService` retains ownership of the credential-exchange endpoints (`signIn` → `/api/auth/sync-token`, `register` → `/api/auth/register`) so token-persistence side effects stay co-located.
- `ContractTests.swift` added — env-gated live `POST /api/auth/sync-token` + `GET /api/messages?limit=3` against `https://interlinedlist.com`, never logging credentials or tokens; skipped when `INTERLINEDLIST_EMAIL` / `INTERLINEDLIST_PASSWORD` are absent.
- `AuthService.requestPasswordReset` re-routed from the previously-coded `/api/auth/password-reset/request` (404 on live API) to the working `/api/auth/forgot-password`; legacy `PasswordResetRequest` retained but marked `@available(deprecated)`.

### 1.3 — Lists / Documents / Follow / Orgs / Notifications / Exports endpoint groups — DONE
- Commits: `a1e6d1c` (parallel groups), `6ed194a` (merge).
- `Endpoints/ListsEndpoint.swift` + `DTOs/ListDTO.swift`: 21 Lists rows + 3 List Connections rows. Includes dynamic-schema `ListRowDTO.rowData` (`[String: ListJSONValue]`), public no-auth browse routes, watchers, and connections.
- `Endpoints/DocumentsEndpoint.swift` + `DTOs/DocumentDTO.swift`: 14 Documents & Sync rows including the delta-sync read (`DocumentSyncResponse`), push-sync write (`DocumentSyncRequest`), folder CRUD, and multipart image upload via `RequestBody.raw`.
- `Endpoints/FollowEndpoint.swift` + `DTOs/FollowDTO.swift`: 11 Follow rows. Listing-shape ambiguity for followers/following/mutual called out in the file's doc comment — typed as bare arrays; switchable to `Paginated<FollowUserDTO>` without changing call sites if the live envelope turns out to be wrapped.
- `Endpoints/OrganizationsEndpoint.swift` + `DTOs/OrganizationDTO.swift`: 9 Organizations rows including the `addMember` envelope (`OrganizationMembershipResponse`).
- `Endpoints/NotificationsEndpoint.swift` + `DTOs/NotificationDTO.swift`: 3 Notifications rows. Non-standard tray envelope (`{ unreadCount, items }`) modeled as `NotificationTrayDTO`; `scope=tray` query parameter defaulted.
- `Endpoints/ExportsEndpoint.swift` + `DTOs/ExportDTO.swift`: 4 Exports rows — `auth: .session` per decision 0001 allowlist; CSV responses retrieved via `APIClient.sendRaw` + `CSVExport.from(_:)` (not JSON-decoded).

### Test counts per suite (`swift test --package-path Packages/InterlinedKit`, run 2026-06-18)

| Suite | Tests | Notes |
| --- | ---: | --- |
| `APIClientTests` | 10 | Send / sendVoid / sendRaw, header injection, JSON encoding, 401 safety-net. |
| `APIErrorTests` | 13 | Status-code → `APIError` mapping incl. malformed bodies. |
| `AuthEndpointTests` | 16 | Builders + `forgotPassword`, `resetPassword`, `sendVerificationEmail`, `verifyEmail`, `logout` round-trips. |
| `AuthServiceTests` | 7 | `signIn` happy / invalid / failure, `signOut`, `hasStoredToken`. |
| `AuthTransportTests` | 6 | `DefaultAuthTransport` routing and 401 retry. |
| `ContractTests` | 2 | Env-gated live API; **both skipped in this run** (no `INTERLINEDLIST_EMAIL` / `INTERLINEDLIST_PASSWORD`). |
| `DocumentsEndpointTests` | 9 | Builder shape + sync delta + image upload + sync push + boundary cases. |
| `ExportsEndpointTests` | 6 | Builders + CSV bytes via `sendRaw` over session transport + forbidden failure + boundary. |
| `FollowEndpointTests` | 9 | Builders + status / counts / followers + unauthorized retry path. |
| `ListsEndpointTests` | 11 | Builders + paginated decode + dynamic-schema row + connections envelope. |
| `MessagesEndpointTests` | 34 | Builders + create (incl. M6 cross-post fields) + scheduled + replies + dig/undig + raw upload + public messages. |
| `NotificationsEndpointTests` | 7 | Builders + tray decode + mark-read + mark-all-read + boundary + malformed. |
| `OrganizationsEndpointTests` | 8 | Builders + list / members / add-member envelope + boundary. |
| `PaginationTests` | 8 | `Paginated<T>` decoder across collection keys + error cases. |
| `TokenStoreTests` | 5 | Read / write / overwrite / delete on `InMemoryTokenStore`. |
| `UserEndpointTests` | 23 | Builders + envelopes + identities & organizations through session transport + update / avatar / change-email / delete. |
| **Total** | **174** | All passing; 0 failures. |

### Wave 1 gate — PASSED (2026-06-18)

- `swift test --package-path Packages/InterlinedKit` → **174/174 passing** (12.2 s, including the 1.5 s spent in the two env-gated `ContractTests` cases that issue an `XCTSkip` because no credentials are present).
- Coverage matrix delta: **0 → 92 Implemented** (☑), **0 → 6 fully Tested** (☑) plus **85 partial** (◐⁴) — see `api-coverage.md` for the full row breakdown and the new partial-coverage convention.

### Coverage matrix delta (after this update)

| | Before Wave 1 | After Wave 1 |
| --- | ---: | ---: |
| Implemented (☑) | 0 / 98 | **92 / 98** |
| Tested fully (☑) | 0 / 98 | **6 / 98** |
| Tested partial (◐⁴) | 0 / 98 | **85 / 98** |
| Untested (☐) | 98 / 98 | **7 / 98** |

The 6 unimplemented rows (`POST /api/auth/login` ⁵, the four `GET /api/auth/.../authorize` OAuth rows, and `GET /api/auth/linkedin/status`) are all M6/M7 work and were correctly out of Wave 1 scope. `POST /api/auth/register` is implemented in `AuthService` but lacks dedicated stubbed unit tests (footnote 6); the other 6 untested rows are the unimplemented rows above.

### Deviations and follow-ups

1. **Planned-service column corrections (matrix footnote 1, 7).** `UserService` and `ExportsService` names from PLAN.md §3's ellipsis are confirmed by the Wave 1 implementation as `InterlinedKit.User` / `InterlinedKit.Exports` namespaces. `GET /api/user/organizations` was previously listed under `OrgService`; corrected to `UserService¹` because the live path is `/api/user/organizations` and the builder lives in `User`.
2. **`POST /api/auth/login` deferred (matrix footnote 5).** Decision 0001 makes Bearer the primary transport; cookie-session login is needed only to satisfy the small session-only allowlist. Wave 1 wires the seam (`SessionEstablisher`) but ships only the `NullSessionEstablisher` test double — a real one calling `POST /api/auth/login` lands with the first feature that exercises a session-only endpoint (likely the M7 Exports menu, or earlier if a Wave 2 feature requires it). No row contradicts PLAN.md; the deferral is a sequencing choice.
3. **Path correction in `AuthService.requestPasswordReset`.** The previously-coded `/api/auth/password-reset/request` returns 404 on the live API; `forgotPassword` is the working endpoint. `PasswordResetRequest` retained as a deprecated source-compat stub; consumers should migrate to `ForgotPasswordRequest`.
4. **`MessagesEndpointTests` M6 carry-in (matrix footnote 2).** `test_givenCrossPostAndScheduled_whenCreateBuilt_thenEncodesAllSetFields` already exercises encoding for `scheduledAt`, `mastodonProviderIds`, `crossPostToBluesky`, and `crossPostToLinkedIn`, so the M6 wave update need only confirm a domain-service path consumes those fields before the row counts toward M6.
5. **Follower / following / mutual listing envelope unknown.** `FollowEndpoint`'s file-level doc records the open assumption: bare arrays of `FollowUserDTO`, with a one-line switch to `Paginated<FollowUserDTO>` if the live API turns out to wrap them under `"data"`. The contract test only covers the timeline today — flagged for either a follow-up live probe or a Wave 5 (Social) confirmation when the social-feature work begins.
6. **Per-endpoint behavior depth (footnote 4).** Of 92 implemented rows, only 6 carry the full happy + invalid + failure + empty/boundary quartet PLAN.md §7 requires. The remaining 85 are marked partial (◐⁴): every row has at least a builder-shape assertion and at least one behavior case, and `APIClientTests` / `APIErrorTests` exhaustively cover the cross-cutting error mapping that every endpoint inherits. The pragmatic call: backfill per-endpoint quartet tests in the milestone wave that ships the consuming domain service, so the per-endpoint tests can pin both the request builder and the service's call site simultaneously. Each subsequent wave's documentation update must convert the partial (◐⁴) rows for endpoints it consumes into full ☑ before the wave gate.
7. **OAuth endpoints and `linkedin/status` intentionally deferred to M6** (matrix milestone column already reflects this).

---

## Wave 2 — InterlinedDomain / Persistence / M1 UI (PLAN.md §6 M1)

Wave 2 lands the M1 read-only core: the `InterlinedDomain` slice (models + services), the `InterlinedPersistence` SwiftData timeline cache, and the App-layer composition root + Timeline / Lists / Profile features. Path ownership stayed inside `Packages/InterlinedDomain/**`, `Packages/InterlinedPersistence/**`, and `App/**`; no `InterlinedKit` source paths were touched this wave (its 174/174 suite from Wave 1 is unchanged). Write-side M5 social methods were explicitly deferred — `SocialService` ships read-only.

### Decisions

- **2026-06-21 — Decision 0002 recorded.** Public user profile (`GET /api/users/[username]`) does not exist on the live API; M1 `SocialService.profile(username:)` falls back to the embedded author of `GET /api/user/[username]/messages` (fields limited to `{ id, username, displayName, avatar }`). See [decisions/0002-public-profile-fallback.md](decisions/0002-public-profile-fallback.md). Coverage matrix updated with footnote 8 and the `GET /api/user/[username]/messages` row annotated as the M1 profile carrier; no Implemented / Tested counts change.

### 2.1 — InterlinedDomain slice (Messages / Session / Entitlements) — DONE

- Commit: `b33d66c`.
- Domain models for the M1 read surface: `MessageBody`, `MessageAuthor`, `MessageThread` and their mappers off `MessageDTO` / `RepliesResponse`.
- `MessagesService` — paged timeline (all / mine / tag scopes), message-by-id read, replies-by-id read, public-author messages — all routed through `InterlinedKit.Messages` and the Wave 1 `APIClient`.
- `SessionService` — current-user read off `GET /api/user`, surfaced as a `Session` domain value; `EntitlementsService` reads `customerStatus` from the same payload.
- BDD-named unit tests against `APIClient` stubs; this slice raised the Domain suite to 61 passing tests at commit time.

### 2.2 — Lists & Social domain services + models — DONE

- New domain models: `UserProfile` (incl. `UserProfile.init(fromEmbeddedAuthorOf: MessageDTO)` per decision 0002), `ListSummary`, `ListDetail`, `ListRow`, plus `ListMappers` and `ProfileMappers`.
- `ListsService` (public-browse only for M1): `lists(of:limit:offset:)`, `detail(username:slug:)`, `rows(username:slug:limit:offset:)` — backed by the three `GET /api/users/[username]/lists*` rows.
- `SocialService` (read-only for M1): `profile(username:)` via the decision-0002 embedded-author fallback, plus `status(of:)`, `counts(of:)`, `followers(of:limit:offset:)`, `following(of:limit:offset:)`. Surfaces a typed `SocialError.profileUnavailable(username:)` for the empty-public-messages case. M5 write methods (follow / unfollow / approve / reject / remove / mutual / requests) are explicitly deferred to the M5 wave.
- Tests: `ListsServiceTests`, `SocialServiceTests` — 15 new BDD-named cases covering the embedded-author projection, the nil-rich-fields M1 guarantee from decision 0002, and the empty-public-messages error path.
- Domain suite now passes **76/76**.

### 2.3 — InterlinedPersistence SwiftData cache — DONE

- New folder layout inside `Packages/InterlinedPersistence/Sources/InterlinedPersistence/`:
  - `Schema/` — `MessageRecord.swift` (SwiftData `@Model`), `TimelinePageRecord.swift` (page key + ordered message IDs).
  - `Mapping/` — `MessageRecordMapping.swift` (round-trip between `Message` domain value and `MessageRecord`).
  - `Stores/` — `SwiftDataMessageStore.swift` (`MessageStore` implementation with in-memory and on-disk factories; `NullMessageStore` no-op for hostile boot conditions).
- `SwiftDataMessageStoreTests.swift` — 10 new BDD-named cases covering round-trip, second-write-wins, cross-key isolation, clear, repost hydration, and the repost dropped-silently-when-missing path.
- Persistence suite now passes **13/13**.

### 2.4 — App-layer composition root + Timeline / Lists / Profile UI — DONE

- `App/Composition/AppEnvironment.swift` — composition root wiring `KeychainTokenStore` → `DefaultAuthTransport` (Bearer-only, `NullSessionEstablisher` for M1 per decision 0001) → `APIClient` → `SwiftDataMessageStore.inMemory()` → `MessagesService`, with a shared-client `ListsService` and `SocialService`. Exposed to SwiftUI via `@EnvironmentObject` and the `\.appEnvironment` environment key. Falls back to `NullMessageStore` if the in-memory SwiftData store can't be constructed.
- Timeline feature: `TimelineRootView`, `TimelineViewModel`, `MessageRowView`, `MessageDetailView`, `MessageDetailViewModel`. Scope picker (All / Mine), tag filter, infinite scroll (paged at row N-5), pull-to-refresh, detail thread view.
- Lists feature: `ListsBrowserView`, `ListsBrowserViewModel`, `ListRowSummaryView`, `ListDetailView`, `ListDetailViewModel`. Username → public-list browse with list detail + rows.
- Social feature: `ProfileHeaderView`, `ProfileViewModel`, `ProfileRootView`.
- `App/Navigation/MainWindowView.swift` — `SidebarDetailDispatcher` now routes `.timeline → TimelineRootView()`, `.lists → ListsBrowserView()`, `.profile → ProfileRootView()`. Remaining sections (Scheduled, Notifications, Documents, Organizations) stay on placeholders pending later milestones.
- `App/InterlinedListApp.swift` — installs `AppEnvironment.live()` at scene level.
- `TimelinePlaceholderView`, `ListsPlaceholderView`, `SocialPlaceholderView` retained as preview fallbacks with docstrings updated to note they're superseded.

### Wave 2 gate — PASSED (2026-06-21)

- App build: `xcodebuild -scheme InterlinedList -destination 'platform=macOS' build` → **BUILD SUCCEEDED**.
- Domain tests: `swift test --package-path Packages/InterlinedDomain` → **76/76 passing**.
- Persistence tests: `swift test --package-path Packages/InterlinedPersistence` → **13/13 passing**.
- InterlinedKit suite unchanged this wave — still **174/174** from Wave 1 (no source paths in `Packages/InterlinedKit/**` touched).
- Path-ownership check: changes confined to `Packages/InterlinedDomain/**`, `Packages/InterlinedPersistence/**`, `App/**`, and `docs/**` — no overlaps with Wave 1 paths; conflict rules held.

### Test counts per suite (combined Domain + Persistence, run 2026-06-21)

| Suite | Tests | Notes |
| --- | ---: | --- |
| `InterlinedDomainTests` (full) | 76 | Includes the new `ListsServiceTests` and `SocialServiceTests` (15 new cases this wave) on top of the 2.1 Messages / Session / Entitlements suites. |
| `InterlinedPersistenceTests` (full) | 13 | Includes the 10 new `SwiftDataMessageStoreTests` cases this wave on top of the Wave 0 baseline. |
| **Total (Domain + Persistence)** | **89** | All passing; 0 failures. InterlinedKit unchanged at 174/174. |

### Coverage matrix delta (after this update)

The M1 consumption rule from Wave 1 deviation 6 applied: every M1-consumed row that was partial (◐⁴) after Wave 1 is now fully tested (☑) at the domain-service layer.

| | Before Wave 2 | After Wave 2 |
| --- | ---: | ---: |
| Implemented (☑) | 92 / 98 | **92 / 98** |
| Tested fully (☑) | 6 / 98 | **16 / 98** |
| Tested partial (◐⁴) | 85 / 98 | **75 / 98** |
| Untested (☐) | 7 / 98 | **7 / 98** |

Rows flipped ◐⁴ → ☑ this wave (10 total, all M1):

- Messages: `GET /api/messages`, `GET /api/messages/[id]/replies` (`GET /api/messages/[id]` was already ☑ from Wave 1).
- Lists (public): `GET /api/users/[username]/lists`, `GET /api/users/[username]/lists/[id]`, `GET /api/users/[username]/lists/[id]/data`.
- Follow (read-only M1 subset): `GET /api/follow/[userId]/status`, `GET /api/follow/[userId]/counts`, `GET /api/follow/[userId]/followers`, `GET /api/follow/[userId]/following`. The remaining Follow rows (write paths, mutual, requests) stay ◐⁴ for M5.
- Public: `GET /api/user/[username]/messages`.

`GET /api/messages/[id]` was already ☑ after Wave 1 (per Wave 1's 6 fully-tested rows) and remains ☑; it is consumed by M1 detail view but contributes no flip to the total above.

### Deviations and follow-ups

1. **Latent kit-import compile failure surfaced when wiring `.profile` to `ProfileRootView`.** `ProfileHeaderView` and `ProfileViewModel` referenced `FollowCountsDTO` (an `InterlinedKit` type) while importing only `InterlinedDomain`. The defect was masked through earlier 2.4 iterations because the `SidebarDetailDispatcher` still routed `.profile` to `SocialPlaceholderView`, so the App target never compiled the new files. The dispatcher change to `ProfileRootView()` first exposed the missing import; fixed by adding `import InterlinedKit` to both files. **Recommendation for a Wave 3 architectural decision (do not implement in this docs task):** either codify a rule that any App-layer file referencing a kit DTO must `import InterlinedKit`, OR adopt `@_exported import InterlinedKit` from `InterlinedDomain` to re-export the kit's public surface so domain consumers do not have to know which layer a type lives in. The trade-off (surface-area leak vs. consumer ergonomics) belongs in a Wave 3 decision record before either path is taken.
2. **`SocialService` ships read-only for M1.** Write methods (`follow`, `unfollow`, `approve`, `reject`, `remove`, `mutual`, `requests`) are deferred to the M5 wave per PLAN.md §6; the Wave 1 `InterlinedKit.Follow` builders for those rows stay at ◐⁴ until M5 consumes them.
3. **List rows are projected via `ListRow` with dynamic `rowData`.** The M1 list-detail UI renders rows with the dynamic-schema `rowData` typed as `[String: ListJSONValue]` from `InterlinedKit.ListRowDTO`. No schema-driven typing for row values is in scope until M3 (Lists CRUD).
4. **Composition root uses `SwiftDataMessageStore.inMemory()` for M1.** On-disk persistence is wired (the factory exists) but the live `AppEnvironment` defaults to the in-memory store so the M1 read-only core does not need a schema-migration story before M4. A `NullMessageStore` is the documented fallback if the in-memory store fails to construct at boot.
5. **Zero-public-messages users surface as `SocialError.profileUnavailable(username:)`.** This is the documented limit of the decision-0002 fallback, not a defect; M1 UX renders the typed error as a friendly empty state. Will resolve when the upstream `GET /api/users/[username]` lands and decision 0002 is superseded.
