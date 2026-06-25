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

---

## Wave 3 — InterlinedDomain M2 write surface + App-layer Posting UI (PLAN.md §6 M2)

Wave 3 lands the M2 posting kickoff: a Decision-0003 architectural rule for kit-import policy, the `InterlinedDomain.MessagesService` write surface (`create / reply / repost / update / delete / dig / undig`) plus a `FollowCounts` domain model so the M1 Social views drop their `InterlinedKit` imports, then the App-layer Composer / inline-reply / optimistic-dig / repost / edit / delete UI that consumes those write methods end-to-end. Path ownership stayed inside `Packages/InterlinedDomain/**`, `App/**`, `InterlinedList.xcodeproj/**` (for the new test target only), and `docs/decisions/**` for the recorded decision; `InterlinedKit` source paths were not touched this wave (its 174/174 suite from Wave 1 is unchanged), and `InterlinedPersistence` source paths were not touched either (its 13/13 from Wave 2 is unchanged).

### Decisions

- **2026-06-22 — Decision 0003 recorded and accepted.** App-layer files (`App/Features/**`, `App/Navigation/**`, `App/MenuCommands/**`) must not `import InterlinedKit`; the only permitted location is the composition root (`App/Composition/AppEnvironment.swift`). Domain mappers in `Packages/InterlinedDomain/**` carry the kit-to-domain projection so view code only ever sees domain values. The `FollowCounts` model added this wave is the first downstream consequence — `ProfileHeaderView`, `ProfileViewModel`, and the Wave 2 deviation-1 follow-up are resolved by this rule. See [decisions/0003-kit-import-policy.md](decisions/0003-kit-import-policy.md). The decision picks the consumer-ergonomics-preserving option from Wave 2 deviation 1 (introduce a domain-level type) over the surface-area-leak option (`@_exported import`).

### 3.1 — Decision 0003 + InterlinedDomain M2 write surface — DONE

- Commit: `c07ac8a`.
- Decision 0003 (kit-import policy) recorded and merged.
- `MessagesService` write surface: `create / reply / repost / update(messageId:…) / delete(messageId:) / dig(messageId:) / undig(messageId:)` — every method wraps the existing Wave 1 `InterlinedKit.Messages` builders and returns domain values via the established mappers.
- `MessageStore.remove(id:)` added to the persistence protocol with a no-op default so existing conformers (incl. `NullMessageStore`) keep compiling; `InMemoryMessageStore` evicts the message across both the by-id index and any timeline page that referenced it.
- `FollowCounts` domain model introduced; `ProfileHeaderView` / `ProfileViewModel` / the third Social view dropped `import InterlinedKit` and now consume the domain projection only. This is the first material proof point of decision 0003.
- Domain suite: 76 → **99 passing** (23 new BDD-named cases across the write methods and the `FollowCounts` projection).

### 3.2 — App-layer M2 UI (Composer / reply / dig / repost / edit / delete) — DONE

- Commit pending (orchestrator just verified gate; uncommitted at the time of this entry).
- **Composer window.** Dedicated SwiftUI `Window` scene opened via ⌘N (`CommandGroup(replacing: .newItem)` in `App/MenuCommands/ComposeCommands.swift`). `ComposerViewModel` supports both `.newPost` (calls `MessagesService.create`) and `.edit(messageID:original:)` (calls `MessagesService.update`). UI: plain-text body, tag-token entry (comma/whitespace split, leading `#` stripped, dedupe-preserving-order), public/private visibility toggle, ⌘↩ submit; empty/whitespace bodies rejected before any service call.
- **Inline reply.** `MessageDetailView` gained a bottom `DisclosureGroup` composer that calls `MessageDetailViewModel.postReply` → `MessagesService.reply`.
- **Optimistic dig/undig.** `MessageRowView` and `MessageDetailView` snapshot the original message, flip locally, then call `dig`/`undig`; on success the service return value replaces the snapshot, on failure the snapshot is restored. A `pendingDigOperations: Set<Message.ID>` debounces rapid toggling.
- **Repost.** Context-menu entry opens `RepostSheetView` (commentary + visibility) → `RepostSheetViewModel.submit` → `MessagesService.repost`.
- **Edit and Delete.** Context-menu entries are gated by ownership via the new App-layer `CurrentUserStore` (an adapter wrapping `SessionManaging`); both items are hidden when `currentUserID` is `nil`. Delete uses `.confirmationDialog`. Root-message delete routes through `TimelineViewModel.deleteMessage` and `MessageDetailViewModel.deleteCurrentMessage`.
- **Cross-window write propagation.** New `ComposerEventBus` (actor-backed pub/sub) broadcasts write events; `TimelineViewModel.apply(event:)` and `MessageDetailViewModel.apply(event:)` translate to pure local mutations (prepend / replace / remove), so the timeline and detail windows stay coherent without re-fetching. Reply events are routed only to the matching parent detail view.
- **Test target.** New `InterlinedListTests` test target added to `InterlinedList.xcodeproj` using a `PBXFileSystemSynchronizedRootGroup` rooted at `AppTests/`, so future test files do not require pbxproj edits — they land in `AppTests/` and are picked up automatically. **44 BDD-named tests** added this wave.
- **Decision 0003 compliance.** Kit-import grep on `App/**`: zero `Features/**` imports of `InterlinedKit`; the only `import InterlinedKit` is in `App/Composition/AppEnvironment.swift` — the documented permitted location. Decision 0003 holds.

### Wave 3 gate — PASSED (2026-06-22)

- App build: `xcodebuild -scheme InterlinedList -destination 'platform=macOS' build` → **BUILD SUCCEEDED**.
- App tests: `xcodebuild -scheme InterlinedList -destination 'platform=macOS' test` → **44/44 passing** in the new `InterlinedListTests` target.
- Domain tests: `swift test --package-path Packages/InterlinedDomain` → **99/99 passing**.
- Kit tests: `swift test --package-path Packages/InterlinedKit` → **174/174 passing** (unchanged; no Kit source paths touched).
- Persistence tests: `swift test --package-path Packages/InterlinedPersistence` → **13/13 passing** (unchanged; no Persistence source paths touched).
- Path-ownership check: changes confined to `Packages/InterlinedDomain/**`, `App/**`, `InterlinedList.xcodeproj/**` (test-target add only), `docs/decisions/0003-kit-import-policy.md`, and `docs/**` for this wave-end update — no overlaps with Wave 1 or Wave 2 paths; conflict rules held.
- Decision-0003 compliance check: `App/**` kit-import grep returned only the permitted composition-root import.

### Test counts per suite (run 2026-06-22)

| Suite | Tests | Notes |
| --- | ---: | --- |
| `InterlinedListTests.ComposerViewModelTests` | 9 | New-post and edit flows, tag-token parsing, empty-body rejection, ⌘↩ submission gate. |
| `InterlinedListTests.RepostSheetViewModelTests` | 4 | Commentary + visibility round-trip through `MessagesService.repost`. |
| `InterlinedListTests.TimelineViewModelTests` | 13 | Includes optimistic dig/undig (success and restore-on-failure), `apply(event:)` prepend / replace / remove, `deleteMessage`, scope-change behavior. |
| `InterlinedListTests.MessageDetailViewModelTests` | 14 | Inline reply, optimistic dig/undig on detail, repost, edit, root delete, reply-scoped event routing. |
| `InterlinedListTests.CurrentUserStoreTests` | 4 | Restore / refresh / sign-out transitions and ownership-gating reads. |
| **`InterlinedListTests` total** | **44** | New test target; all passing. |
| `InterlinedDomainTests` (full) | 99 | +23 cases this wave covering `create / reply / repost / update / delete / dig / undig` quartets and the `FollowCounts` mapper. |
| `InterlinedPersistenceTests` (full) | 13 | Unchanged from Wave 2. |
| `InterlinedKitTests` (full) | 174 | Unchanged from Wave 1. |
| **Grand total across all targets** | **330** | All passing; 0 failures. |

### Coverage matrix delta (after this update)

The M2 consumption rule (Wave 1 deviation 6, reiterated in the matrix footnote 4) applied: every M2-consumed row that was partial (◐⁴) after Wave 2 is now fully tested (☑) end-to-end (Kit builder → Domain service → App view-model).

| | Before Wave 3 | After Wave 3 |
| --- | ---: | ---: |
| Implemented (☑) | 92 / 98 | **92 / 98** |
| Tested fully (☑) | 16 / 98 | **20 / 98** |
| Tested partial (◐⁴) | 75 / 98 | **71 / 98** |
| Untested (☐) | 7 / 98 | **7 / 98** |

Rows flipped ◐⁴ → ☑ this wave (**4 total**, all M2-consumed end-to-end). The orchestrator brief listed six row-paths to flip, but two of those rows — `POST /api/messages` and `GET /api/user` — were already ☑ on the matrix before this wave (`POST /api/messages` from Wave 1 footnote 2 carry-in; `GET /api/user` from Wave 2's M1 closure). The four genuine flips are:

- Messages: `PUT /api/messages/[id]` (`ComposerViewModel.submit` edit case → `MessagesService.update`).
- Messages: `DELETE /api/messages/[id]` (`TimelineViewModel.deleteMessage` and `MessageDetailViewModel.deleteCurrentMessage` → `MessagesService.delete`).
- Messages: `POST /api/messages/[id]/dig` (`toggleDig` undug→dug branch → `MessagesService.dig`).
- Messages: `DELETE /api/messages/[id]/dig` (`toggleDig` dug→undug branch → `MessagesService.undig`).

Re-consumed but unchanged (☑ already):

- `POST /api/messages` — re-exercised this wave by all three Wave 3 entry points (`create` for new posts, `reply` for inline replies, `repost` for the repost sheet). Each is covered by dedicated `MessagesServiceTests` quartets and by App-layer tests in `ComposerViewModelTests`, `MessageDetailViewModelTests`, and `RepostSheetViewModelTests`. Cross-post / scheduled / media-upload request fields on this row remain M6 per footnote 2.
- `GET /api/user` — additionally consumed by the App layer this wave through `CurrentUserStore.restore` → `SessionManaging.restore` → `SessionService.fetchCurrentUser` for ownership gating of Edit / Delete (`CurrentUserStoreTests`, 4 cases). Row state was already ☑ from Wave 2.

### Deviations and follow-ups

1. **Reply-delete is wired in the context menu but not in the view model.** `MessageDetailViewModel` only exposes `deleteCurrentMessage` (root). A reply's Delete menu item shows the `.confirmationDialog` but does not call through. Scoped out of M2 because PLAN.md §6 M2 says "delete/edit own messages" without specifying reply-level granularity. Follow-up: add `MessageDetailViewModel.deleteReply(id:)` in an M2 polish slice or M5.
2. **Repost is a sheet, not a window.** Matches PLAN.md §6 M2 wording ("a small sheet"). Flagged here in case a later milestone wants window parity with the composer.
3. **Edit reuses `ComposerWindowView` inside a sheet.** Allowed by PLAN.md §6 M2 ("Edit reopens the composer pre-populated"). To open edits in a dedicated window so the timeline stays visible, change the `.sheet(item:)` call to `openWindow(id:value:)` with a second `Window` scene.
4. **`AsyncStream` deinit-cancel concession.** `CurrentUserStore`'s subscription Task uses `[weak self]`; deinit-time cancellation of the handle is not wired because Swift 6 Observation-macro semantics block `nonisolated` storage on the handle. The Task ends naturally on the next stream value after deallocation — acceptable for production. Fix path if it ever matters: wrap the handle in a separate non-observed helper class.
5. **`TimelineViewModelTests.seedForTest` seeds state via `apply(event: .messageCreated)`.** Mild test-code smell — the long-term cleaner shape is an `internal` (test-only) `replaceMessagesForTest(_:)` under `#if DEBUG`. Not blocking, not done this wave.
6. **SourceKit-only diagnostic noise after pbxproj mutation.** Adding the `InterlinedListTests` target via direct pbxproj edits left Xcode's SourceKit indexer reporting stale "No such module 'InterlinedDomain'" errors across every `App/**` file. `xcodebuild` was unaffected. Resolves with Xcode's **File → Packages → Reset Package Caches** or **Product → Clean Build Folder**. Noted here for future contributors who land pbxproj edits this way.

---

## Wave 4 — InterlinedDomain M3 write surface + Persistence lists cache + App-layer Lists UI (PLAN.md §6 M3)

Wave 4 lands M3 Lists end-to-end: the `InterlinedDomain` Lists write surface (CRUD, schema DSL, row CRUD, watchers, connections, GitHub-source refresh) plus a `FollowCounts`-style domain projection for every Lists wire type; the `InterlinedPersistence` SwiftData lists cache; and the App-layer Lists UI (owned-lists root with disclosure tree, schema editor, rows table + row inspector, watchers panel, list-connections graph, public-list "Save to my lists" hook). Path ownership stayed inside `Packages/InterlinedDomain/**`, `Packages/InterlinedPersistence/**`, `App/**`, and `InterlinedList.xcodeproj/**` (no test-target additions this wave — `InterlinedListTests` re-uses the Wave 3 synchronized folder group, so new tests landed in `AppTests/` without pbxproj edits). `InterlinedKit` source paths were not touched (its 174/174 suite from Wave 1 is unchanged).

### Decisions

- **No new architectural decisions this wave.** Decision 0003 (kit-import policy) from Wave 3 remains the load-bearing rule for App-layer composition and was verified end-of-wave: the `import InterlinedKit` grep across `App/Features/**`, `App/Navigation/**`, and `App/MenuCommands/**` returned empty (the only kit import in `App/**` lives in `App/Composition/AppEnvironment.swift`, the documented permitted location). Every new Lists view model, view, and event-bus type in this wave consumes domain values only — `OwnedList`, `ListSchema`, `SchemaFieldType`, `ListRow`, `WatcherRole`, `ListConnection`, `GitHubListSource` — and never reaches into `InterlinedKit` DTOs.

### 4.1 — InterlinedDomain Lists write surface + schema DSL + InterlinedPersistence lists cache — DONE

- Commit: `415c5c2`.
- **Domain models:** `OwnedList`, `OwnedListsPage`, `ListSchema`, `SchemaField`, `SchemaFieldType { text, number, boolean, date, url, email }`, `ListConnection`, `ListWatcher`, `WatcherStatus`, `WatcherRole { owner, editor, viewer, .other(String) }`, `GitHubListSource`, `OwnedListMappers`. The `WatcherRole.other(String)` case preserves unknown wire values so a future role added server-side does not crash the parser (a defensive shape NW-1 already leans on).
- **Schema DSL:** `Schema/SchemaDSL.swift` — parse + serialize round-trip with a typed `SchemaDSLError`. Property-style tests cover round-trip, every field type, whitespace variants, duplicate field names, missing types, and trailing commas — the deepest test suite PLAN.md §7 calls out for the parser.
- **`ListsService` write surface:** `myLists`, `detail`, `create`, `update`, `delete`, `schema`, `updateSchema`, `refresh`, row CRUD (`rows`, `addRow`, `updateRow`, `deleteRow`, `getRow`), watchers (`watchers`, `myWatcher`, `watcherUsers`, `setWatcher`, `removeWatcher`), connections (`connections`, `addConnection`, `removeConnection`). Every write routes through a `requireListManagement()` guard that consults `EntitlementsService.canManageLists`, throwing `ListsError.subscriberRequired` before any HTTP call. The default permissive flag stays on through M6 — this is defensive gating wired now so M6's entitlement toggle is a one-line policy change, not a search-and-replace across services.
- **`EntitlementsService` extension:** gains `canManageLists` plus `init(customerStatus:canManageLists:)` test seam.
- **`ListsStore` cache port** (domain-side protocol) added to keep the App layer from knowing about SwiftData directly.
- **Persistence SwiftData lists cache:** new `@Model` records `ListRecord`, `ListsPageRecord`, `ListSchemaRecord`, `SchemaFieldRecord`, `ListRowRecord`, `ListConnectionRecord`, `ListWatcherRecord`; `RowDataCodec` (a JSON-blob codec for the dynamic `[String: ListCellValue]` row shape — keeps `InterlinedPersistence` free of any `InterlinedKit` import); `SwiftDataListsStore` actor with `inMemory()` + `onDisk(at:)` factories and a cascading `removeList` that evicts rows / schema / watchers / connections / page-index entries. `NullListsStore` no-op for hostile boot conditions, matching the M1 `NullMessageStore` pattern.
- **Test counts:** Domain **99 → 181 (+82)**, including the property-style schema DSL suite and the per-method `ListsService` quartets. Persistence **13 → 30 (+17)**, including round-trip, cascading delete, page-index isolation, and the row-data codec round-trip. Kit unchanged at **174**.
- **Endpoint consumption:** the 21 Lists endpoint rows (incl. 3 List Connections) are reachable at the domain-service layer after this commit, but per the Wave 1 deviation-6 rule, they remain ◐⁴ in the coverage matrix until the App layer consumes them end-to-end — which happens in 4.3 below.

### 4.3 — App-layer Lists UI — DONE

- Commits: `461e7df` + `155c955` (view models + `ListsEventBus` + `AppEnvironment` wiring, user-committed), `099d8d9` (views, sidebar router, menu commands).
- **`OwnedListsRootView`** — `NavigationSplitView` with a sidebar disclosure tree that honors `OwnedList.parentID` for nested lists. Toolbar: New List (⇧⌘N), Refresh (calls `refresh` on a GitHub-backed list), Edit Schema, Share (watchers), Connections. Context-menu Delete uses `.confirmationDialog`. List-row metadata (visibility badge, last-refreshed time when present, child count) renders from the domain model only.
- **`NewListSheetView`** — title, description, schema DSL string, parent picker, visibility toggle. GitHub-source fields (`gitHubRepository`, `gitHubPath`, `gitHubBranch`) are surface-only this wave pending the `POST /api/lists` write-side companion documented in [API-backend-prompts-to-build.md](../API-backend-prompts-to-build.md) item 2.3.
- **`SchemaEditorView`** — per-field form builder over `ListSchema`: name, type picker (`SchemaFieldType`), nullable toggle, `.onMove` reorder, full validation before submit. Read-only when the current user's `WatcherRole` does not include schema-edit rights (decided locally from `GET /api/lists/[id]/watchers/me`).
- **`ListRowsView` + `RowInspectorView`** — typed input cells per `SchemaFieldType` (date picker for `date`, stepper for `number`, etc.), cards/list view toggle, optimistic add/update/delete with snapshot rollback on failure. **A dynamic-column SwiftUI `Table` was the original target but deferred** — see deviation 1 below.
- **`WatchersView`** — role editor only this wave (no invite-by-handle), with an explicit infobox citing NW-1 and the API-backend-prompts item 1.5 user-lookup ask. Optimistic role-change and remove with snapshot rollback.
- **`ListConnectionsView`** — pure SwiftUI `Canvas` + gesture handlers (drag-to-move nodes, drag-from-node-to-node to add an edge, tap-to-remove an edge). No `AppKit` import. Layout is a **deterministic radial v1**: nodes are placed on a circle at equal angular intervals from a stable hash of `OwnedList.id`, so the same set of lists always renders in the same arrangement. A `TODO(M3.x)` marker in `ListConnectionsViewModel` flags the force-directed upgrade for a polish wave.
- **`ListsSidebarRouter`** — ownership gating: signed-in users see `OwnedListsRootView`; signed-out users see the M1 `ListsBrowserView` (preserved). Reads from `CurrentUserStore` (Wave 3).
- **Public-list "Save to my lists" hook** — `ListDetailView` + `ListDetailViewModel.saveToMyLists` create an owned list with the source's title, description, and schema string. **Metadata-only v1** — row-level cloning waits on the [API-backend-prompts-to-build.md](../API-backend-prompts-to-build.md) item 2.3a clone endpoint. The UI surfaces this limit inline.
- **Menu integration:** `ListMenuCommands` adds a Lists menu with "New List" on ⇧⌘N (avoiding the ⌘N collision with the Wave 3 `ComposeCommands`). `MainWindowView` routes `.lists` through `ListsSidebarRouter`.
- **Cross-window write propagation:** new `ListsEventBus` (actor-backed pub/sub, mirroring the Wave 3 `ComposerEventBus` shape) broadcasts list/row/watcher/connection mutations so the owned-lists root, the rows view, the schema editor, the watchers panel, and the connections graph all stay coherent without re-fetching.
- **SwiftUI-only constraint enforced.** `grep -R "import AppKit" App/` returned empty at the gate — every Lists view in this wave is pure SwiftUI, including the connections-graph canvas. This is the explicit policy choice the agent and orchestrator agreed to before the wave started; the deterministic radial layout is what made it feasible without an AppKit drop-down.
- **Decision 0003 compliance.** `grep -R "import InterlinedKit" App/Features App/Navigation App/MenuCommands` returned empty at the gate. The only kit import in `App/**` remains the documented permitted one in `App/Composition/AppEnvironment.swift`. The wave's view models all consume domain values via the 4.1 `OwnedList` / `ListSchema` / `ListRow` / `WatcherRole` / `ListConnection` projections.
- **App tests:** **44 → 106 (+62)** — new view-model suites: `OwnedListsViewModelTests` (14), `NewListViewModelTests` (4), `SchemaEditorViewModelTests` (10), `ListRowsViewModelTests` (14), `WatchersViewModelTests` (9), `ListConnectionsViewModelTests` (11), plus the `StubListsService` test double under `AppTests/Support/`. The 44 Wave 3 tests are unchanged and still passing.

### Wave 4 gate — PASSED (2026-06-23)

- App build: `xcodebuild -scheme InterlinedList -destination 'platform=macOS' build` → **BUILD SUCCEEDED**.
- App tests: `xcodebuild -scheme InterlinedList -destination 'platform=macOS' test` → **106/106 passing** in `InterlinedListTests`.
- Domain tests: `swift test --package-path Packages/InterlinedDomain` → **181/181 passing**.
- Persistence tests: `swift test --package-path Packages/InterlinedPersistence` → **30/30 passing**.
- Kit tests: `swift test --package-path Packages/InterlinedKit` → **174/174 passing** (unchanged; no Kit source paths touched).
- Path-ownership check: changes confined to `Packages/InterlinedDomain/**`, `Packages/InterlinedPersistence/**`, `App/**`, `InterlinedList.xcodeproj/**` (no new targets — `AppTests/` synchronized group from Wave 3 absorbed the new tests), and `docs/**` for this wave-end update — no overlaps with Wave 1, Wave 2, or Wave 3 paths; conflict rules held.
- Decision-0003 compliance check: `grep -R "import InterlinedKit" App/Features App/Navigation App/MenuCommands` → empty. The only `App/**` kit import remains the permitted composition-root one.
- SwiftUI-only check: `grep -R "import AppKit" App/` → empty. Connections graph uses SwiftUI `Canvas`.

### Test counts per suite (run 2026-06-23)

| Suite | Tests | Notes |
| --- | ---: | --- |
| `InterlinedListTests.OwnedListsViewModelTests` | 14 | Initial load + load-more pagination, refresh, delete with snapshot rollback, parent-id nesting, error surfacing. |
| `InterlinedListTests.NewListViewModelTests` | 4 | Title/schema validation, GitHub-source field carry-through, submit success and failure paths. |
| `InterlinedListTests.SchemaEditorViewModelTests` | 10 | Field add / remove / reorder, type-change validation, save success and failure, read-only gating from `myWatcher`. |
| `InterlinedListTests.ListRowsViewModelTests` | 14 | Paged load, add / update / delete with optimistic snapshot + rollback, typed cell coercion per `SchemaFieldType`. |
| `InterlinedListTests.WatchersViewModelTests` | 9 | Load `watchers/users`, optimistic `setRole` + restore-on-failure, optimistic `remove` + restore-on-failure. |
| `InterlinedListTests.ListConnectionsViewModelTests` | 11 | Load, add-connection, remove-connection, deterministic radial layout placement, gesture-translation pure functions. |
| `InterlinedListTests` Wave-3 carry-over | 44 | Unchanged — `ComposerViewModelTests` (9), `RepostSheetViewModelTests` (4), `TimelineViewModelTests` (13), `MessageDetailViewModelTests` (14), `CurrentUserStoreTests` (4). |
| **`InterlinedListTests` total** | **106** | All passing. |
| `InterlinedDomainTests` (full) | 181 | +82 cases this wave: `OwnedListsServiceTests` (the full quartet across CRUD / schema / rows / watchers / connections / refresh), `SchemaDSLTests` (property-style), `EntitlementsServiceTests` (canManageLists). |
| `InterlinedPersistenceTests` (full) | 30 | +17 cases this wave: `SwiftDataListsStoreTests` covering round-trip, cascading delete, page-index isolation, and `RowDataCodec` round-trip. |
| `InterlinedKitTests` (full) | 174 | Unchanged from Wave 1. |
| **Grand total across all targets** | **491** | All passing; 0 failures. |

### Coverage matrix delta (after this update)

The M3 consumption rule (Wave 1 deviation 6, reiterated in matrix footnote 4) applied: every M3-consumed row exercised by a tested App-layer view model this wave flips ◐⁴ → ☑. Four Lists rows are reachable through `ListsService` but were not exercised by a tested view model this wave; they stay ◐⁴ under new footnote 9. Two more (`GET /api/lists`, `POST /api/lists`) stay ◐⁴ until the M3 polish slice pins the full happy + invalid + failure + empty/boundary quartets at the view-model layer.

| | Before Wave 4 | After Wave 4 |
| --- | ---: | ---: |
| Implemented (☑) | 92 / 98 | **92 / 98** |
| Tested fully (☑) | 20 / 98 | **35 / 98** |
| Tested partial (◐⁴) | 71 / 98 | **56 / 98** |
| Untested (☐) | 7 / 98 | **7 / 98** |

Rows flipped ◐⁴ → ☑ this wave (**15 total**, all M3-consumed end-to-end):

- Lists (owned): `DELETE /api/lists/[id]` (`OwnedListsViewModel.deleteList`).
- Lists (owned): `GET /api/lists/[id]/schema` (`ListRowsViewModel.initialLoad` + `SchemaEditorView.loadSchema`).
- Lists (owned): `PUT /api/lists/[id]/schema` (`SchemaEditorViewModel.save`).
- Lists (owned): `POST /api/lists/[id]/refresh` (`OwnedListsViewModel.refreshList`).
- Lists (owned): `GET /api/lists/[id]/data` (`ListRowsViewModel.initialLoad` / `loadMore`).
- Lists (owned): `POST /api/lists/[id]/data` (`ListRowsViewModel.addRow`).
- Lists (owned): `PATCH /api/lists/[id]/data/[rowId]` (`ListRowsViewModel.updateRow`).
- Lists (owned): `DELETE /api/lists/[id]/data/[rowId]` (`ListRowsViewModel.deleteRows`).
- Lists (watchers): `GET /api/lists/[id]/watchers/me` (`SchemaEditorView.loadSchema` for role gating).
- Lists (watchers): `GET /api/lists/[id]/watchers/users` (`WatchersViewModel.load`).
- Lists (watchers): `PUT /api/lists/[id]/watchers/[userId]` (`WatchersViewModel.setRole`).
- Lists (watchers): `DELETE /api/lists/[id]/watchers/[userId]` (`WatchersViewModel.remove`).
- List Connections: `GET /api/lists/connections` (`ListConnectionsViewModel.load`).
- List Connections: `POST /api/lists/connections` (`ListConnectionsViewModel.addConnection`).
- List Connections: `DELETE /api/lists/connections/[id]` (`ListConnectionsViewModel.removeConnection`).

Held back at ◐⁴ this wave (new footnote 9):

- `GET /api/lists/[id]` — reachable via `ListsService.detail`; not driven by a tested view model. Detail-rename UX deferred to a polish slice.
- `PUT /api/lists/[id]` — reachable via `ListsService.update`; rename UX deferred.
- `GET /api/lists/[id]/data/[rowId]` — `RowInspectorView` reads from `ListRowsViewModel.rows` (already paginated), so the single-row hydration endpoint is not on a tested path this wave.
- `GET /api/lists/[id]/watchers` — `WatchersView` consumes `/watchers/users` only this wave; the alternative watcher-pagination envelope is reachable through the service but not exercised by a tested view model.

Held back at ◐⁴ pending polish-slice quartet coverage:

- `GET /api/lists` — `OwnedListsViewModel.initialLoad` / `loadMore` exercise the request path; full quartet of view-model tests lands in the polish slice.
- `POST /api/lists` — `NewListViewModel.submit` + `ListDetailViewModel.saveToMyLists` exercise the request path; full quartet lands in the polish slice.

The three public-Lists rows (`GET /api/users/[username]/lists`, `GET /api/users/[username]/lists/[id]`, `GET /api/users/[username]/lists/[id]/data`) were already ☑ from Wave 2 and remain ☑.

### Deviations and follow-ups

1. **Dynamic-column SwiftUI `Table` deferred.** PLAN.md §1 calls out a SwiftUI `Table` grid view for lists rows. The dynamic-column `Table` constructor lives behind macOS 14.4 (`TableColumnForEach`), while the project deployment target is macOS 14.0. Rather than bump the target mid-wave, `ListRowsView` renders a `List` of typed-cell rows for v1. Follow-up: revisit when the deployment target moves (or build a column-builder workaround), tracked as TODO in `ListRowsView`.
2. **Connections graph layout is deterministic radial v1.** `ListConnectionsViewModel` ships a stable hash-positioned radial arrangement so the same set of lists always renders in the same place. A `TODO(M3.x)` marker flags the upgrade to a force-directed (or simulated annealing) layout for a polish wave. Drag-to-move, drag-to-add-edge, and tap-to-remove-edge are already wired, so the upgrade is layout-only.
3. **GitHub-source create fields are surface-only.** `NewListSheetView` surfaces `gitHubRepository`, `gitHubPath`, `gitHubBranch` but the create endpoint does not yet accept a `gitHubSource` block — see [API-backend-prompts-to-build.md](../API-backend-prompts-to-build.md) item 2.3 companion ask. The fields are stubbed off pending the write-side endpoint shape.
4. **"Save to my lists" is metadata-only.** The hook copies title / description / schema string but not the rows. Row-level cloning waits on [API-backend-prompts-to-build.md](../API-backend-prompts-to-build.md) item 2.3a (`POST /api/lists/clone`). The UI surfaces the limit inline so the user is not surprised.
5. **Watcher invite-by-handle deliberately omitted.** Per [NEXT-WORK.md NW-1](../NEXT-WORK.md), the invite flow waits on [API-backend-prompts-to-build.md](../API-backend-prompts-to-build.md) item 1.5 (`GET /api/users/lookup` or `/search`). `WatchersView` ships role-edit-only with an inline infobox explaining the wait. The `ListsService.setWatcher(listId:userId:role:)` domain method is fully wired and tested — only the user-lookup leg is missing.
6. **In-place rename / edit context-menu wiring held back.** A list's rename action and the edit-list-metadata context-menu item are deliberately deferred to an M3 polish slice. `ListsService.update` is wired and reachable; the App-layer UX is the only thing missing. This is the same row-level deferral that keeps `PUT /api/lists/[id]` at ◐⁴ in the coverage matrix.
7. **Four `◐⁴` Lists rows held back per coverage-matrix footnote 9.** `GET /api/lists/[id]`, `PUT /api/lists/[id]`, `GET /api/lists/[id]/data/[rowId]`, `GET /api/lists/[id]/watchers` — all reachable through the service, none on a tested view-model path this wave. The Wave 1 footnote-4 backfill rule still applies; they flip when the polish slice consumes them.
8. **Stale SourceKit index after new files were added.** Same pattern as Wave 3 deviation 6. Adding the Lists view models, views, event bus, and `StubListsService` test double left Xcode's SourceKit indexer reporting stale "No such module" errors on first reopen. `xcodebuild` was unaffected. Resolves with **File → Packages → Reset Package Caches** or **Product → Clean Build Folder**. Carrying the note forward so contributors who land file additions know not to chase ghosts.
9. **Auth transport secrets activated; CI contract job is staged but inert.** As of 2026-06-23 ~15:50 UTC the `INTERLINEDLIST_EMAIL` and `INTERLINEDLIST_PASSWORD` repo secrets are set, and the new `.github/workflows/contract-tests.yml` workflow is committed on `dev`. The workflow does **not** yet trigger because `workflow_dispatch` and `schedule` only register against the default branch (`main`); GitHub will not surface the manual-run button or schedule the job until `dev` merges to `main`. The `ContractTests` cases in `InterlinedKitTests` continue to `XCTSkip` locally when the env vars are absent (unchanged behavior since Wave 1). No action needed this wave — flagging here so the next merge-to-`main` consciously activates the contract job.

---

## Wave 5 — InterlinedDomain M4 Documents slice + Persistence sync engine + App-layer Documents UI (PLAN.md §6 M4)

Wave 5 lands M4 Documents end-to-end: the `InterlinedDomain` Documents slice (models, mappers, `DocumentsService` full CRUD + folders + image upload, `ImagePrep` pipeline, `DocumentSyncTransport` seam), the `InterlinedPersistence` SwiftData document cache + outbox + `DocumentSyncEngine` actor (pull delta → server-wins conflict resolution → outbox push → cursor advance), and the App-layer Documents UI (three-column root, folder tree, list per folder, Markdown editor + Textual-rendered preview, conflict banner, sync-status indicator, menu commands). The wave also lands the first third-party SPM dependency in App-target history (`gonzalezreal/textual` @ 0.5.0) and the corollary macOS deployment-target bump (14 → 15), both atomically, per [Decision 0004](decisions/0004-markdown-library-and-macos15.md). Path ownership stayed inside `Packages/InterlinedDomain/**`, `Packages/InterlinedPersistence/**`, `App/**`, `InterlinedList.xcodeproj/**` (pbxproj edits only — Textual SPM dep + macOS 15 across the 6 build configurations + `AppTests/` synchronized group from Wave 3 absorbed the new tests with no target additions), `docs/decisions/0004-markdown-library-and-macos15.md`, `README.md` (badge + Building requirements), `docs/user/feature-status.md` (M4 → Shipped + three Limits bullets, set in Wave 5.3), and `docs/**` for this wave-end update. **`InterlinedKit` source paths were not touched this wave** (its 174/174 suite from Wave 1 is unchanged) — verified by `git show --stat daf1eef babb6d2`.

### Decisions

- **2026-06-23 — Decision 0004 recorded and accepted.** `gonzalezreal/textual` chosen as the App target's **first third-party SPM dependency** (Markdown preview rendering for the M4 Documents editor); MarkdownUI is in maintenance mode, MarkdownView transitively imports AppKit through Highlightr, Splash is stale, swift-markdown is parser-only. Textual's platform floor forces a **macOS deployment target bump 14 → 15 (Sonoma → Sequoia)** across all four locations (xcodeproj + three `Package.swift` manifests). The bump is acceptable for a v1 desktop client because Sequoia shipped September 2024 (2+ years before this decision) and aligns with the load-bearing SwiftUI-only constraint (the only candidate library whose dependency tree never reaches into AppKit). Textual is pinned at `from: "0.5.0"` (`.upToNextMajor`); see [decisions/0004-markdown-library-and-macos15.md](decisions/0004-markdown-library-and-macos15.md). The decision was locked in ahead of Wave 5.3 by the orchestrator after the Wave 5.1 swift-engineer subagent began running.

### 5.1 — InterlinedDomain Documents slice + Persistence sync engine — DONE

- Commit: `daf1eef`.
- **Domain models:** `Document`, `FolderNode`, `DocumentSyncEvent`, `DocumentChange`, `DocumentMappers`. The Documents domain slice has been fully decoupled from `InterlinedKit` DTOs at the consumer surface per decision 0003 — view models only ever see domain values.
- **Caching port:** `DocumentStore` protocol with a clean port shape so the App layer never knows about SwiftData directly (same pattern as `MessageStore` from Wave 2 and `ListsStore` from Wave 4).
- **`ImagePrep` pipeline:** passthrough → 1200 px downscale → lossless re-encode (HEIC then PNG) → JPEG quality ladder (`0.9 → 0.5`). Pure CoreGraphics / ImageIO; **no `import AppKit`**. Surfaces a typed "image too large" error when no rung of the quality ladder fits the upload budget.
- **`DocumentsService`:** full CRUD (`documents(in:limit:offset:)`, `document(id:)`, `create`, `update`, `delete`), folders (`folders`, `folder(id:)`, `createFolder`, `renameFolder`, `deleteFolder`), `uploadImage` (multipart via `ImagePrep`), plus the sync passthroughs `pullDelta` / `pushChange` consumed by the engine.
- **`DocumentSyncTransport` seam:** a protocol surface the engine talks to, so the App layer's `KitDocumentSyncTransport` (Wave 5.3) lives in the composition root while the engine itself stays kit-import-free.
- **Persistence SwiftData document cache + outbox:** new `@Model` records `DocumentRecord` (with a `localEditedAt` dirty bit), `FolderRecord`, `OutboxEntryRecord`, `SyncStateRecord`; `DocumentRecordMapping` and `DocumentChangeCodec` (a JSON-blob codec for outbox change payloads — keeps `InterlinedPersistence` free of any wire-format awareness inside the record types). `SwiftDataDocumentStore` actor with `inMemory()` + `onDisk(at:)` factories and a cascading folder delete that evicts contained documents.
- **`DocumentSyncEngine` actor:** the core M4 mechanic. `syncNow` runs `pull delta → server-wins conflict resolution (local preserved as "<id>-localcopy-<UUID>") → outbox push → cursor advance`. Emits an `AsyncStream<DocumentSyncEvent>` with strictly ordered `conflictResolved → deltaApplied → pushed` events; downstream buffer is `bufferingNewest(64)` so a slow observer can never block the engine. The server-wins policy with local-copy preservation is the safe default in the absence of a document version/etag from the server ([API-backend-prompts-to-build.md](../API-backend-prompts-to-build.md) item 3.1) — without an `If-Match` header the engine cannot tell a true conflict from a normal write, so every disagreement preserves the local copy.
- **Persistence `Package.swift` gained a `InterlinedKit` dependency** so `DocumentsError.syncFailed(underlying: APIError)` can carry the kit error type up to the App-layer banner. Decision 0003 is App-layer-only (it forbids `import InterlinedKit` in `App/Features/**`, `App/Navigation/**`, `App/MenuCommands/**`); a Persistence-layer kit import for typed error carriage is in policy.
- **Test counts:** Domain **181 → 244 (+63)** including `DocumentMappersTests` (18), `ImagePrepTests` (8), `DocumentsServiceTests` (32), and expanded `Fixtures`. Persistence **30 → 70 (+40)** including `SwiftDataDocumentStoreTests` and `DocumentSyncEngineTests` with a 50-trial randomized soak covering interleaved pull / push / conflict orderings. Kit unchanged at **174**.
- **Endpoint consumption:** the 14 Documents & Sync rows are reachable at the domain-service / engine layer after this commit, but per the Wave 1 deviation-6 rule, they remain ◐⁴ in the coverage matrix until the App layer consumes them end-to-end — which happens in 5.3 below.

### 5.3 — App-layer Documents UI + macOS 15 bump + Textual SPM dep — DONE

- Commit: `babb6d2`.
- **Infrastructure (decision 0004) landed atomically.** `MACOSX_DEPLOYMENT_TARGET = 15.0` across all **3 `Package.swift` manifests** + all **6 pbxproj build configurations** (Debug/Release for `InterlinedList`, `InterlinedListTests`, and the `MARKETING_VERSION` configurations) + `App/Resources/Info.plist` (`LSMinimumSystemVersion`). The bump went in as one commit-able unit ahead of any Textual usage, with `xcodebuild build` verified green before the dep add.
- **Textual SPM dep added.** `https://github.com/gonzalezreal/textual` @ `0.5.0` (`.upToNextMajor`), linked only to the `InterlinedList` app target — the three SPM packages remain free of third-party deps. Resolved cleanly with `xcodebuild -resolvePackageDependencies` → `textual 0.5.0 resolved`. Transitive deps (`swiftui-math`, `swift-concurrency-extras`) verified pure-SwiftUI — the SwiftUI-only check (`grep -R "import AppKit" App/`) returned empty at the gate.
- **Composition root + lifecycle.** `AppEnvironment` exposes `documentsService`, `documentSyncEngine`, and the `documentSyncEvents` `AsyncStream`. `KitDocumentSyncTransport` wraps `APIClient` for the engine — the **only** App-layer file allowed to `import InterlinedKit` per decision 0003, and it sits in `App/Composition/`. `InterlinedListApp` on-launch `.task` fires `syncNow()` detached after `currentUserStore.restore()` (errors swallowed; manual sync via the toolbar remains).
- **Documents feature** (`App/Features/Documents/`):
  - `DocumentsRootView` — three-column `NavigationSplitView` with toolbar (New Document, Sync Now, status indicator).
  - `DocumentsSidebarView` + `FolderTreeViewModel` — disclosure tree with create / rename / delete folders, optimistic with snapshot rollback on failure.
  - `DocumentsListView` + `DocumentsListViewModel` — list per folder, CRUD + `deltaApplied` event handling (so a sync result that touches the open folder updates in place), pagination heuristic.
  - `DocumentEditorView` + `DocumentEditorViewModel` — vanilla SwiftUI `TextEditor` for editing, `Textual.StructuredText(markdown:)` for preview, 1.5 s debounced auto-save (clock injectable for tests), drag-and-drop + `.fileImporter` image upload routed through `DocumentsService.uploadImage` → `ImagePrep`.
  - `ConflictBannerView` — banner surfaces `conflictResolved` events that match the currently-open document; "Open local copy" action navigates to the preserved-as copy.
  - `SyncStatusView` + `SyncStatusViewModel` — `Idle / Syncing / LastSynced(at:) / Failed(message:)` state machine; toolbar manual-sync button.
- **Menu commands.** `DocumentsMenuCommands` adds the Documents menu with **New Document (⌥⌘N)** and **Sync Now (⌥⌘S)** — both posted via `NotificationCenter` to avoid collisions with the Wave 3 Composer (⌘N) and the existing menu surface. `MainWindowView` routes `.documents` to `DocumentsRootView`.
- **SwiftUI-only constraint verified.** `grep -R "import AppKit" App/` returned empty at the gate; `grep -R "import AppKit" Packages/` returned empty at the gate. Textual's dependency tree contributes zero AppKit imports.
- **Decision 0003 compliance verified.** `grep -R "import InterlinedKit" App/Features App/Navigation App/MenuCommands` returned empty at the gate. The only `App/**` kit import is the documented permitted one in `App/Composition/AppEnvironment.swift` (+ the new `KitDocumentSyncTransport.swift` in the same composition-root directory). The wave's view models all consume domain values via the 5.1 `Document` / `FolderNode` / `DocumentChange` / `DocumentSyncEvent` projections.
- **App tests:** **106 → 150 (+44)** — new view-model suites: `FolderTreeViewModelTests` (11), `DocumentsListViewModelTests` (12), `DocumentEditorViewModelTests` (10), `SyncStatusViewModelTests` (5), `ConflictBannerViewModelTests` (6), plus the `StubDocumentsService` test double under `AppTests/Support/`. The 106 Wave 4 tests are unchanged and still passing.
- **Docs touches inside this wave's commit (Wave 5.3 owned).** `README.md` macOS badge `14+` → `15+` and Building requirements bumped; `docs/user/feature-status.md` M4 row flipped to **Shipped** and three new Limits bullets added (document sync is manual / on-launch, document images are resized client-side before upload, macOS 15 is now the minimum). Verified at this wave gate; not re-touched here.

### Wave 5 gate — PASSED (2026-06-23)

- App build: `xcodebuild -scheme InterlinedList -destination 'platform=macOS' build` → **BUILD SUCCEEDED** on the macOS 15 deployment target.
- App tests: `xcodebuild -scheme InterlinedList -destination 'platform=macOS' test` → **150/150 passing** in `InterlinedListTests`.
- Domain tests: `swift test --package-path Packages/InterlinedDomain` → **244/244 passing**.
- Persistence tests: `swift test --package-path Packages/InterlinedPersistence` → **70/70 passing** (incl. the 50-trial `DocumentSyncEngineTests` randomized soak).
- Kit tests: `swift test --package-path Packages/InterlinedKit` → **174/174 passing** (unchanged; no Kit source paths touched this wave — verified by `git show --stat daf1eef babb6d2`, neither commit lists any file under `Packages/InterlinedKit/Sources/**`).
- SPM resolution: `xcodebuild -resolvePackageDependencies` → **textual 0.5.0 resolved** cleanly (first third-party dep in App-target history).
- Path-ownership check: changes confined to `Packages/InterlinedDomain/**`, `Packages/InterlinedPersistence/**`, `App/**`, `InterlinedList.xcodeproj/**` (pbxproj edits only — Textual SPM dep + macOS 15 across the 6 build configurations), `docs/decisions/0004-markdown-library-and-macos15.md`, `README.md`, `docs/user/feature-status.md`, and `docs/**` for this wave-end update — no overlaps with Wave 1 through Wave 4 paths; conflict rules held.
- Decision-0003 compliance check: `grep -R "import InterlinedKit" App/Features App/Navigation App/MenuCommands` → empty. The only `App/**` kit imports remain the permitted composition-root ones (`AppEnvironment.swift` + `KitDocumentSyncTransport.swift`).
- SwiftUI-only check: `grep -R "import AppKit" App/` → empty; `grep -R "import AppKit" Packages/` → empty. Textual's dependency tree (`swiftui-math`, `swift-concurrency-extras`) contributes no AppKit imports.
- macOS-14-residue check: `grep -R "macOS(.v14)" Packages/` → empty; `grep -R "MACOSX_DEPLOYMENT_TARGET = 14" InterlinedList.xcodeproj/project.pbxproj` → empty. The bump is uniform across the 4 location classes.

### Test counts per suite (run 2026-06-23)

| Suite | Tests | Notes |
| --- | ---: | --- |
| `InterlinedListTests.FolderTreeViewModelTests` | 11 | Initial load, create / rename / delete folders with optimistic snapshot + rollback, error surfacing. |
| `InterlinedListTests.DocumentsListViewModelTests` | 12 | Reload, pagination heuristic, create / delete document with optimistic rollback, `deltaApplied` event handling for the open folder. |
| `InterlinedListTests.DocumentEditorViewModelTests` | 10 | Debounced auto-save with injected clock, manual `saveNow`, drag-and-drop / file-importer image upload through `ImagePrep`, save-failure surfacing. |
| `InterlinedListTests.SyncStatusViewModelTests` | 5 | `Idle / Syncing / LastSynced / Failed` state-machine transitions; manual-sync trigger. |
| `InterlinedListTests.ConflictBannerViewModelTests` | 6 | `conflictResolved` event filtering (matches open document id), "Open local copy" action wiring, banner dismiss. |
| `InterlinedListTests` Wave-4 carry-over | 106 | Unchanged — `OwnedListsViewModelTests` (14), `NewListViewModelTests` (4), `SchemaEditorViewModelTests` (10), `ListRowsViewModelTests` (14), `WatchersViewModelTests` (9), `ListConnectionsViewModelTests` (11), plus the 44 Wave-3 carry-over. |
| **`InterlinedListTests` total** | **150** | All passing. |
| `InterlinedDomainTests` (full) | 244 | +63 cases this wave: `DocumentMappersTests` (18), `ImagePrepTests` (8), `DocumentsServiceTests` (32), Fixtures expanded. |
| `InterlinedPersistenceTests` (full) | 70 | +40 cases this wave: `SwiftDataDocumentStoreTests` covering round-trip / cascading folder-delete / outbox FIFO; `DocumentSyncEngineTests` covering pull / push / conflict-preservation / cursor advance plus a 50-trial randomized interleaving soak. |
| `InterlinedKitTests` (full) | 174 | Unchanged from Wave 1 (no Kit source paths touched). |
| **Grand total across all targets** | **638** | All passing; 0 failures. |

### Coverage matrix delta (after this update)

The M4 consumption rule (Wave 1 deviation 6, reiterated in matrix footnote 4) applied: every M4-consumed Documents & Sync row exercised by a tested App-layer view model this wave flips ◐⁴ → ☑. Two detail-read rows are reachable through their domain-service methods but Wave 5.3 view models open documents / folders via the list payload rather than re-reading by id; those stay ◐⁴ under new footnote 10.

| | Before Wave 5 | After Wave 5 |
| --- | ---: | ---: |
| Implemented (☑) | 92 / 98 | **92 / 98** |
| Tested fully (☑) | 35 / 98 | **47 / 98** |
| Tested partial (◐⁴) | 56 / 98 | **44 / 98** |
| Untested (☐) | 7 / 98 | **7 / 98** |

Rows flipped ◐⁴ → ☑ this wave (**12 total**, all M4-consumed end-to-end Kit builder → Domain service → App view-model):

- Sync: `GET /api/documents/sync` (`KitDocumentSyncTransport.pullDelta` via `DocumentSyncEngine.syncNow` via `SyncStatusViewModel.syncNow`).
- Sync: `POST /api/documents/sync` (`KitDocumentSyncTransport.pushChange` via `DocumentSyncEngine.syncNow` outbox push).
- Documents: `GET /api/documents` (`DocumentsService.documents(in:limit:offset:)` when folder is nil → `DocumentsListViewModel.reload`).
- Documents: `POST /api/documents` (`DocumentsService.create` → `DocumentsListViewModel.createDocument`).
- Documents: `PATCH /api/documents/[id]` (`DocumentsService.update` → `DocumentEditorViewModel.saveNow`).
- Documents: `DELETE /api/documents/[id]` (`DocumentsService.delete` → `DocumentsListViewModel.deleteDocument`).
- Documents: `POST /api/documents/[id]/images/upload` (`DocumentsService.uploadImage` → `DocumentEditorViewModel.uploadImage`; `ImagePrep` exercised in the upload path).
- Folders: `GET /api/documents/folders` (`DocumentsService.folders` → `FolderTreeViewModel.initialLoad`).
- Folders: `POST /api/documents/folders` (`DocumentsService.createFolder` → `FolderTreeViewModel.createFolder`).
- Folders: `PATCH /api/documents/folders/[id]` (`DocumentsService.renameFolder` → `FolderTreeViewModel.renameFolder`).
- Folders: `DELETE /api/documents/folders/[id]` (`DocumentsService.deleteFolder` → `FolderTreeViewModel.deleteFolder`).
- Folders: `GET /api/documents/folders/[id]/documents` (`DocumentsService.documents(in:limit:offset:)` when folderID != nil → `DocumentsListViewModel.reload`).

Held back at ◐⁴ this wave (new footnote 10):

- `GET /api/documents/[id]` — reachable via `DocumentsService.document(id:)`; Wave 5.3 view models open documents from the list / sync-delta payload rather than re-reading by id. Held pending a polish slice that consumes the by-id read path (e.g. a deep-link or quick-look hydrator).
- `GET /api/documents/folders/[id]` — reachable via `DocumentsService.folder(id:)`; same pattern as above.

### Deviations and follow-ups

1. **Markdown toolbar inserts at end-of-buffer, not at cursor.** SwiftUI `TextEditor` on macOS 15 does not expose the selection binding required to insert at the caret; `TextSelection` for `TextEditor` landed in macOS 26. The toolbar buttons (bold / italic / link / heading) currently append the wrapped or stubbed Markdown at the end of the document body. Follow-up: revisit when the deployment target moves to macOS 26 or when a SwiftUI-only selection workaround surfaces.
2. **Drag-drop accepts `Data` only this wave.** The drag-drop handler in `DocumentEditorView` accepts `Data` payloads (rasterized images from screenshots, the browser, the Finder preview, etc.). A `URL.self` branch — for dragging a file by reference, where the dropped item is a file URL pointing at an on-disk image — is a v1.x add. Follow-up: extend `DocumentEditorViewModel.uploadImage` to accept a `URL` input and route through the same `ImagePrep` pipeline after a `Data(contentsOf:)` read.
3. **"Open local copy" silently fails across folder boundaries.** When the sync engine resolves a conflict by preserving the local copy as `<id>-localcopy-<UUID>`, the conflict banner's "Open local copy" action calls a refresh on the **currently loaded folder**. If the preserved copy was written into a different folder (because the document's `folderId` changed in the server payload), the refresh returns the same set and the navigation silently does nothing. **Backend ask filed this wave:** [API-backend-prompts-to-build.md](../API-backend-prompts-to-build.md) item **3.7 — Sync conflict event needs folderId** (P3). Have the sync delta API confirm `folderId` is included on every preserved-copy creation so the engine can route the banner action correctly.
4. **Two Documents & Sync rows held at ◐⁴ per coverage-matrix footnote 10.** `GET /api/documents/[id]` and `GET /api/documents/folders/[id]` — both reachable through their domain-service methods, neither on a tested view-model path this wave (Wave 5.3 view models read from the list payload and the sync delta). The Wave 1 footnote-4 backfill rule still applies; they flip when a polish slice consumes them.
5. **Persistence package now imports InterlinedKit.** `Packages/InterlinedPersistence/Package.swift` gained an `InterlinedKit` dependency this wave so `DocumentsError.syncFailed(underlying: APIError)` (returned by `DocumentSyncEngine`) can carry the kit error type up to the App-layer banner. Decision 0003's "no kit imports" rule is **App-layer-only** (it forbids `import InterlinedKit` in `App/Features/**`, `App/Navigation/**`, `App/MenuCommands/**`); a Persistence-layer kit import for typed error carriage is in policy and was not flagged at the gate.
6. **macOS 15 deployment target bump cuts off Sonoma users.** Users on macOS 14 (Sonoma) can no longer install the app after this wave. The risk is captured in [Decision 0004's risk register](decisions/0004-markdown-library-and-macos15.md#risk-register); the trade-off was deliberate (Sequoia is 2+ years old at this point, and the SwiftUI-only constraint left Textual as the only acceptable Markdown library, which forces the bump). Documented user-side in `docs/user/feature-status.md`.
7. **Stale SourceKit index after the pbxproj mutation.** Same pattern as Wave 3 deviation 6 and Wave 4 deviation 8. Adding the Textual SPM dep + the deployment-target bump + the new Documents view-model files left Xcode's SourceKit indexer reporting stale "No such module" / "No such product" errors on first reopen. `xcodebuild` was unaffected. Resolves with **File → Packages → Reset Package Caches** or **Product → Clean Build Folder**. Carrying the note forward.
8. **Auth transport secrets activated; CI contract job still inert on `dev`.** Carry-over from Wave 4 deviation 9 — no change this wave. As of 2026-06-23 ~15:50 UTC the `INTERLINEDLIST_EMAIL` / `INTERLINEDLIST_PASSWORD` repo secrets are set, and `.github/workflows/contract-tests.yml` is committed on `dev`; the workflow does not yet trigger because `workflow_dispatch` and `schedule` only register against the default branch (`main`). The contract job will activate when `dev` merges to `main`. Still outstanding as of this gate.

---

## Wave 6 — InterlinedDomain M5 Social + Notifications slice + Persistence stores + App-layer Social/Notifications UI (PLAN.md §6 M5)

Wave 6 lands M5 Social + Notifications end-to-end: the InterlinedKit Wave 1 deviation 5 closure (Follow envelopes pinned against the live API), the `InterlinedDomain` Social write surface + Notifications slice (`SocialService.follow / unfollow / approve / reject / removeFollower / mutual / requests`, `NotificationsService.tray / markRead / markAllRead`, plus `FollowRelationship` + `FollowAction`, `FollowRequest`, `MutualCounts`, `Notification` + `NotificationKind` + `NotificationTarget`, and the supporting mappers), the `InterlinedPersistence` SwiftData stores (`SwiftDataNotificationStore`, `SwiftDataFollowCountsStore`), the App-layer UI (`FollowButton`, three-tab `SocialRosterRootView`, `NotificationsRootView` with inline Approve/Reject for follow-request rows, `ProfileHeaderView` mutuals row, dock-tile unread badge, lazy UN-permission timing, deep-link menu commands), and a new architectural decision: [Decision 0005](decisions/0005-dock-badge-appkit-exception.md) — a narrow `import AppKit` exception scoped to exactly one composition-root file (`App/Composition/AppDelegate.swift`) for the macOS dock badge.

Path ownership stayed inside `Packages/InterlinedDomain/**`, `Packages/InterlinedPersistence/**`, `App/**`, `docs/decisions/0005-dock-badge-appkit-exception.md`, and `docs/**` / `README.md` / `API-backend-prompts-to-build.md` for the docs touches. **`InterlinedKit` was touched this wave only to close Wave 1 deviation 5** (Follow envelopes against the live API) and pick up 3 new test cases — its source paths under `Packages/InterlinedKit/Sources/InterlinedKit/{DTOs,Endpoints}/Follow*` shifted; **no other Kit source paths moved**, verified by `git show --stat cae57cc da13846 159f71a 085b91f 9a66154`.

### Decisions

- **2026-06-24 — Decision 0005 recorded and accepted.** Narrow `import AppKit` exception authorized in exactly one new file — `App/Composition/AppDelegate.swift` — owned by the composition root, used solely for the `NSApplication.shared.dockTile.badgeLabel` writer and the `UNUserNotificationCenterDelegate` hook. The Wave 1+ `App/**` AppKit grep is amended to allow that one file (and only that file); every other `App/**` AppKit hit remains a violation. The choice followed the SwiftUI-only memory rule (`feedback_swiftui_only.md`) by pausing-and-asking, then taking option **A** ("tiny `@NSApplicationDelegateAdaptor` + dock-tile badge as a single documented exception file") because PLAN.md §5 explicitly calls for the dock badge and macOS 15 SwiftUI has no public dock-badge API. The exception's shape mirrors decision 0003's `App/Composition/AppEnvironment.swift` carve-out (one file, one method, one purpose, named by path in the decision and at the verification gate). See [decisions/0005-dock-badge-appkit-exception.md](decisions/0005-dock-badge-appkit-exception.md).

### 6.1 — InterlinedKit Wave 1 deviation 5 closure + InterlinedDomain M5 slice + Persistence stores + namespace rename — DONE

- Commits: `cae57cc` (Kit Follow envelope pin to live API + Domain mapper updates), `da13846` (domain models + services + tests + initial persistence schemas), `159f71a` (interim namespace-alias workaround for the `Notification` clash), `085b91f` (Wave 6.1 closure: `InterlinedDomain` → `InterlinedDomain_Module` marker rename — replaces the alias workaround — plus the `SwiftDataNotificationStore` / `SwiftDataFollowCountsStore` test suites and Follow action backend ask 2.3b).
- **InterlinedKit (deviation 5 closure).** `FollowUserDTO`: `avatarUrl` → `avatar` (live key) and new `followId`, `createdAt`, `status` fields the live API actually returns. `FollowMutualCountsDTO` replaces `FollowMutualDTO` — the endpoint returns `{ mutualFollowers, mutualFollowing }` counts, **not** a list of users. `FollowRequestsResponse { requests: [...] }` for `/api/follow/requests` (no pagination today — `API-backend-prompts-to-build.md` ask 2.1 downgraded to P3 and marked resolved). `Follow.followers` / `Follow.following` typed as `Request<Paginated<FollowUserDTO>>` with `paginationKey "followers" / "following"` plus `limit` / `offset` / `status` query parameters. `Follow.mutual` typed as `Request<FollowMutualCountsDTO>`. `Follow.requests` typed as `Request<FollowRequestsResponse>` (drops the previous wrong `Paginated<FollowRequestDTO>` shape). `FollowEndpointTests` rewritten — 11 → 12 cases including pagination decode, mutual counts, requests envelope, and query-param coverage. **Kit: 174 → 177 (+3)** — Wave 1 deviation 5 **CLOSED**.
- **InterlinedDomain models.** `FollowRelationship` + `FollowAction` (the typed "following / pendingRequest / followedBy" projection), `FollowRequest`, `MutualCounts`, `Notification`, `NotificationKind` (8 typed cases — `dig`, `reply`, `mention`, `follow_request`, `follow_accepted`, `list_shared`, `list_row_added`, `org_invite` — plus `.other(String)` for forward-compatibility, matching the defensive shape `WatcherRole` introduced in Wave 4), `NotificationTarget`, `FollowMappers`, `NotificationMappers`. Backend ask 2.4 (P2 — typed notification kinds) is reflected in the closed enum on the macOS side; when the server documents its kind taxonomy the `.other` fallback narrows.
- **InterlinedDomain services.** `SocialService` write surface — `follow / unfollow / approve / reject / removeFollower / mutual / requests` — each routed through the Wave 1 `InterlinedKit.Follow` builders and mapped to domain values. The follow path currently chains `POST /api/follow/[userId]` then `GET /api/follow/[userId]/status` because the action endpoint's response envelope does not reliably distinguish "now following" from "request pending" — backend ask 2.3b (P2, added this wave) proposes a `relationship` block on the action response to halve the round-trip count. `NotificationsService.tray / markRead / markAllRead` — the tray method drops the client-side `limit` parameter since the live API uses `notificationTrayLimit` clamped 10-40 server-side.
- **InterlinedPersistence SwiftData stores.** New `@Model` records `NotificationRecord` and `FollowCountsRecord`; `NotificationRecordMapping` (round-trip between domain `Notification` and the record) and a JSON-blob codec inside the actor for `NotificationTarget` payloads (keeps `InterlinedPersistence` free of wire-format awareness inside the record types). `SwiftDataNotificationStore` actor (tray round-trip, mark-read flag flip, mark-all-read badge zero, every `NotificationTarget` case round-trip, clear cascade). `SwiftDataFollowCountsStore` actor (follow + mutual counts combination, per-user isolation, second-write-wins, remove, clear). Test counts: **70 → 90 (+20)** — `SwiftDataNotificationStoreTests` (11) + `SwiftDataFollowCountsStoreTests` (9).
- **Namespace rename.** The `Notification` domain model collided with `Foundation.Notification` once SwiftData-backed mappers brought both into the same file. Commit `159f71a` introduced a `DomainNotificationAlias.swift` workaround inside `InterlinedPersistence`; commit `085b91f` replaced that workaround with the cleaner fix — renaming the public module-marker enum `InterlinedDomain` → `InterlinedDomain_Module` (a low-traffic version marker; only consumer was `InterlinedPersistence`, also updated). The alias file was deleted in the same commit. The disambiguation lets `NotificationRecordMapping.swift` and `SwiftDataNotificationStore.swift` use explicit `InterlinedDomain.Notification` references without further per-file `typealias` declarations.
- **Domain test counts:** **244 → 299 (+55)** including `FollowRequestsTests` (Requests envelope projection), `MutualCountsTests` (counts projection), `NotificationMappersTests` (every kind + target case + `.other` fallback), `NotificationsServiceTests` (tray quartet + markRead / markAllRead), and `SocialServiceWriteTests` (the full quartet across follow / unfollow / approve / reject / removeFollower / mutual / requests).
- **Endpoint consumption:** the M5 Follow + Notifications endpoint rows are reachable at the domain-service layer after this wave, but per the Wave 1 deviation-6 rule they remain ◐⁴ until the App layer consumes them end-to-end — which happens in 6.3 below.

### 6.3 — App-layer Social + Notifications UI + Decision 0005 + AppKit exception — DONE

- Commit: `9a66154`.
- **Decision 0005 landed and verified.** `App/Composition/AppDelegate.swift` is the only file in the App target permitted to `import AppKit`. The file is a `NSApplicationDelegateAdaptor` with a `updateDockBadge(unreadCount:)` method that writes `NSApplication.shared.dockTile.badgeLabel`, plus a `UNUserNotificationCenterDelegate` hook for banner presentation (foreground delivery) and activation routing (brings the app forward — deep-link routing to the related message / list / profile is a `TODO(M5.x)`). The wave-gate AppKit grep was amended per the decision: `grep -rEn "^[[:space:]]*import AppKit" App/ | grep -v '^App/Composition/AppDelegate.swift:'` returns empty.
- **Composition root** (the documented exception files):
  - `App/Composition/AppDelegate.swift` — new this wave; the single AppKit-allowed file.
  - `App/Composition/NotificationsEventBus.swift` — actor-backed pub/sub matching the Wave 3 `ComposerEventBus` / Wave 4 `ListsEventBus` shape; carries unread-count change events.
  - `App/Composition/NotificationsUnreadBadgeCoordinator.swift` — subscribes to the bus, writes the dock badge through an `@MainActor @Sendable` closure (testable seam — tests inject a stub closure that captures invocations).
  - `App/Composition/FollowRelationshipReader.swift` — composition-root adapter that consumes the kit `FollowStatusDTO` and projects it into a domain-style protocol the view models depend on. This is the same Decision 0003 carve-out shape as `App/Composition/AppEnvironment.swift` — one file, one purpose, named by path. **Temporary shim**: the adapter is dead code once backend ask 3.8 (P3, added this wave) migrates `SocialServicing.status(of:)` to return the domain `FollowRelationship` directly. Tracked as deviation 1 below.
  - `App/Composition/AppEnvironment.swift` — extended with `NotificationsService`, `SwiftDataFollowCountsStore`, and `FollowRelationshipReader` wiring.
- **Notifications feature** (`App/Features/Notifications/`):
  - `NotificationsRootView` + `NotificationsListViewModel` — paged tray, `markRead` and `markAllRead` with optimistic updates and snapshot rollback. The view's `.task` lazily calls `NotificationsPermissionCoordinator.requestIfNeeded()` so the macOS UN-permission prompt only appears the first time the user opens Notifications, not at app launch.
  - `NotificationRowView` + `NotificationRowCopy` — per-`NotificationKind` copy (e.g. "Adron followed you", "Lena dug your post"), SF Symbols icon per kind, **inline Approve/Reject buttons for `follow_request` rows** routed through the shared `FollowRequestRowViewModel`.
  - `NotificationsPermissionCoordinator` — UserDefaults-backed "asked" flag, `requestIfNeeded()` checks the flag before calling `UNUserNotificationCenter.current().requestAuthorization`; only fires the prompt once.
- **Social feature** (`App/Features/Social/`):
  - `FollowButton` + `FollowButtonViewModel` — optimistic follow / unfollow with snapshot rollback, **hidden during the initial relationship probe** so a "Follow" label never flashes against a user already followed (the documented limit surfaced in `docs/user/feature-status.md`). Pending-request state renders as "Requested" when the target account is private.
  - `SocialRosterRootView` + `SocialRosterViewModel` — three-tab Followers / Following / Requests; paginated lists; Approve / Reject on Requests is optimistic row-drop with snapshot rollback on failure. Routed from the new `.connections` sidebar entry (see Navigation below).
  - `FollowRequestRowViewModel` — **shared between the tray and the roster panel** so the optimistic UI behaves identically across both surfaces (a single source of truth for the row's pending-action state).
  - `ProfileHeaderView` + `ProfileViewModel` — mutuals row (`MutualCounts`), follower / following counts, Follow button slot, decision-0002 empty-profile path preserved.
- **Menu commands** (`App/MenuCommands/`):
  - `NotificationsMenuCommands` — Show Notifications (⌘0), Mark All Read (⌥⌘R), Refresh (⌃⌘R).
  - `SocialMenuCommands` — Show Followers / Following / Requests (⌃⌘1 / ⌃⌘2 / ⌃⌘3).
- **Navigation.** `MainWindowView` gained a new `.connections` sidebar entry routing to `SocialRosterRootView`; `.notifications` now routes to `NotificationsRootView` (no longer the placeholder); menu deep-links flow via `onReceive(NotificationCenter)` to avoid pbxproj-level coupling.
- **Decision 0003 compliance.** `grep -R "import InterlinedKit" App/Features App/Navigation App/MenuCommands` returned empty at the gate. The `App/**` kit imports remain confined to `App/Composition/` — `AppEnvironment.swift` (Wave 2), `KitDocumentSyncTransport.swift` (Wave 5), and now `FollowRelationshipReader.swift` (this wave, decision-0003 carve-out shape).
- **Decision 0005 compliance.** The amended AppKit grep returned only the single allowed hit (`App/Composition/AppDelegate.swift`); no other file in the App target imports AppKit.
- **App tests:** **150 → 220 (+70)** — new view-model suites: `FollowButtonViewModelTests` (11), `ProfileHeaderViewModelTests` (5), `SocialRosterViewModelTests` (14), `FollowRequestRowViewModelTests` (7), `NotificationsListViewModelTests` (9), `NotificationRowCopyTests` (13), `NotificationsUnreadBadgeCoordinatorTests` (7), `NotificationsPermissionCoordinatorTests` (4). New support stubs under `AppTests/Support/`: `StubSocialService`, `StubNotificationsService`, `StubFollowRelationshipReader`. The 150 Wave 5 tests are unchanged and still passing.
- **Docs touches inside this wave's commit (Wave 6.3 owned).** `README.md` M5 row flipped to **Shipped** in the status table; `docs/user/feature-status.md` M5 row flipped to **Shipped** and four new Limits bullets added (UN-permission first-open timing, follow-button initial-state probe, notification deep-link minimal v1, system-banner permission semantics). `API-backend-prompts-to-build.md` gained ask **3.8** (P3 — domain-typed follow-relationship read, so `FollowRelationshipReader` can be deleted). Verified at this wave gate; the coverage-snapshot line on the README is refreshed in this docs gate to match the new totals.

### Wave 6 gate — PASSED (2026-06-24)

- App build: `xcodebuild -scheme InterlinedList -destination 'platform=macOS' build` → **BUILD SUCCEEDED**.
- App tests: `xcodebuild -scheme InterlinedList -destination 'platform=macOS' test` → **220/220 passing** in `InterlinedListTests`.
- Domain tests: `swift test --package-path Packages/InterlinedDomain` → **299/299 passing**.
- Persistence tests: `swift test --package-path Packages/InterlinedPersistence` → **90/90 passing**.
- Kit tests: `swift test --package-path Packages/InterlinedKit` → **177/177 passing** (174 → 177 from the Wave 1 deviation 5 closure in commit `cae57cc`; the only Kit source paths that moved are under `Sources/InterlinedKit/{DTOs,Endpoints}/Follow*`).
- Path-ownership check: changes confined to `Packages/InterlinedKit/Sources/InterlinedKit/{DTOs,Endpoints}/Follow*` + `Packages/InterlinedKit/Tests/InterlinedKitTests/FollowEndpointTests.swift` (deviation-5 closure scope only), `Packages/InterlinedDomain/**`, `Packages/InterlinedPersistence/**`, `App/**`, `docs/decisions/0005-dock-badge-appkit-exception.md`, `README.md`, `docs/user/feature-status.md`, `API-backend-prompts-to-build.md`, and `docs/**` for this wave-end update — no overlaps with Wave 1 through Wave 5 paths; conflict rules held.
- Decision-0003 compliance check: `grep -R "import InterlinedKit" App/Features App/Navigation App/MenuCommands` → empty. The only `App/**` kit imports remain the permitted composition-root ones (`AppEnvironment.swift`, `KitDocumentSyncTransport.swift`, `FollowRelationshipReader.swift`).
- Decision-0005 amended AppKit check: `grep -rEn "^[[:space:]]*import AppKit" App/ | grep -v '^App/Composition/AppDelegate.swift:'` → empty. The only AppKit hit in the App target is the documented exception file.
- SwiftUI-only check (Packages): `grep -R "import AppKit" Packages/` → empty.

### Test counts per suite (run 2026-06-24)

| Suite | Tests | Notes |
| --- | ---: | --- |
| `InterlinedListTests.FollowButtonViewModelTests` | 11 | Initial-probe hidden state, optimistic follow / unfollow with snapshot rollback, pending-request state for private accounts, error surfacing. |
| `InterlinedListTests.ProfileHeaderViewModelTests` | 5 | Profile load with `MutualCounts`, follower / following counts, follow-button slot wiring, decision-0002 empty-profile path. |
| `InterlinedListTests.SocialRosterViewModelTests` | 14 | Followers / Following / Requests tab loads, pagination, optimistic approve / reject with snapshot rollback, error surfacing. |
| `InterlinedListTests.FollowRequestRowViewModelTests` | 7 | Shared model for tray + roster; approve / reject quartet; pending-action lockout. |
| `InterlinedListTests.NotificationsListViewModelTests` | 9 | Tray load, paginate, `markRead` optimistic flag flip with rollback, `markAllRead` batch with rollback. |
| `InterlinedListTests.NotificationRowCopyTests` | 13 | Per-`NotificationKind` copy + SF Symbols icon mapping (8 cases + `.other` fallback + edge cases). |
| `InterlinedListTests.NotificationsUnreadBadgeCoordinatorTests` | 7 | Bus subscription, dock-badge write via injected `@MainActor @Sendable` closure, zero-count clears badge. |
| `InterlinedListTests.NotificationsPermissionCoordinatorTests` | 4 | UserDefaults-backed "asked" flag, `requestIfNeeded()` prompts once, idempotent on second call. |
| `InterlinedListTests` Wave-5 carry-over | 150 | Unchanged — `FolderTreeViewModelTests` (11), `DocumentsListViewModelTests` (12), `DocumentEditorViewModelTests` (10), `SyncStatusViewModelTests` (5), `ConflictBannerViewModelTests` (6), plus the 106 Wave-4 carry-over and the 44 Wave-3 carry-over. |
| **`InterlinedListTests` total** | **220** | All passing. |
| `InterlinedDomainTests` (full) | 299 | +55 cases this wave: `FollowRequestsTests`, `MutualCountsTests`, `NotificationMappersTests`, `NotificationsServiceTests`, `SocialServiceWriteTests` quartets across follow / unfollow / approve / reject / removeFollower / mutual / requests. |
| `InterlinedPersistenceTests` (full) | 90 | +20 cases this wave: `SwiftDataNotificationStoreTests` (11) covering tray round-trip / mark-read / mark-all-read / every `NotificationTarget` case / clear cascade; `SwiftDataFollowCountsStoreTests` (9) covering follow + mutual combination / per-user isolation / second-write-wins / remove / clear. |
| `InterlinedKitTests` (full) | 177 | +3 cases this wave from the Wave 1 deviation 5 closure (`FollowEndpointTests` rewritten — pagination decode, mutual counts, requests envelope, query params). Other Kit suites unchanged. |
| **Grand total across all targets** | **786** | All passing; 0 failures. |

### Coverage matrix delta (after this update)

The M5 consumption rule (Wave 1 deviation 6, reiterated in matrix footnote 4) applied: every M5-consumed row exercised by a tested App-layer view model this wave flips ◐⁴ → ☑. One Follow row (`POST /api/follow/[userId]/remove`) is reachable through `SocialService.removeFollower` but no Wave 6.3 view model surfaces a "remove from my followers" action against an already-accepted follower; it stays ◐⁴ under new footnote 11.

| | Before Wave 6 | After Wave 6 |
| --- | ---: | ---: |
| Implemented (☑) | 92 / 98 | **92 / 98** |
| Tested fully (☑) | 47 / 98 | **55 / 98** |
| Tested partial (◐⁴) | 44 / 98 | **36 / 98** |
| Untested (☐) | 7 / 98 | **7 / 98** |

Rows flipped ◐⁴ → ☑ this wave (**8 total**, all M5-consumed end-to-end Kit builder → Domain service → App view-model):

- Follow: `POST /api/follow/[userId]` (`SocialService.follow` → `FollowButtonViewModel.performFollow`).
- Follow: `DELETE /api/follow/[userId]` (`SocialService.unfollow` → `FollowButtonViewModel.performUnfollow`).
- Follow: `GET /api/follow/[userId]/mutual` (`SocialService.mutual` → `ProfileViewModel.loadProfile`).
- Follow: `POST /api/follow/[userId]/approve` (`SocialService.approve` → `SocialRosterViewModel.approve` and the shared `FollowRequestRowViewModel.approve` consumed from both the tray and the Requests tab).
- Follow: `POST /api/follow/[userId]/reject` (`SocialService.reject` → `SocialRosterViewModel.reject` and `FollowRequestRowViewModel.reject`).
- Follow: `GET /api/follow/requests` (`SocialService.requests` → `SocialRosterViewModel.loadRequests`).
- Notifications: `PATCH /api/notifications/[id]/read` (`NotificationsService.markRead` → `NotificationsListViewModel.markRead`).
- Notifications: `POST /api/notifications/mark-all-read` (`NotificationsService.markAllRead` → `NotificationsListViewModel.markAllRead`).

Re-consumed but unchanged (☑ already from earlier waves):

- `GET /api/follow/[userId]/status` — already ☑ from Wave 2 (M1 read-only Social subset); re-consumed this wave by `FollowRelationshipReader` → `FollowButtonViewModel.refreshRelationship`. Row state unchanged.
- `GET /api/follow/[userId]/followers` / `GET /api/follow/[userId]/following` / `GET /api/follow/[userId]/counts` — already ☑ from Wave 2; re-consumed this wave by `SocialRosterViewModel.loadFollowers` / `loadFollowing` and `ProfileViewModel.loadProfile`. Row state unchanged.
- `GET /api/notifications?scope=tray` — already ☑ from Wave 1 (in the 6 fully-tested rows); re-consumed this wave by `NotificationsListViewModel.load`. Row state unchanged.

Held back at ◐⁴ this wave (new footnote 11):

- `POST /api/follow/[userId]/remove` — reachable via `SocialService.removeFollower(userId:)` (the "remove a user from **my** followers" action, distinct from `DELETE /api/follow/[userId]` which unfollows someone I follow). No Wave 6.3 view model surfaces it; the Followers tab in `SocialRosterRootView` displays the roster and the Requests tab approves/rejects, but neither yet exposes a "remove this follower" context-menu action. Flips when a polish slice (likely a `SocialRosterRowViewModel.removeFollower` context-menu action on the Followers tab) consumes it.

### Deviations and follow-ups

1. **`App/Composition/FollowRelationshipReader.swift` is a temporary shim.** It exists because `SocialServicing.status(of:)` returns the kit `FollowStatusDTO` today; an App-layer view model that wants the relationship would either reference the kit type (violating decision 0003) or — what this wave actually does — read through a composition-root adapter. Backend ask **3.8** (P3, added 2026-06-24) is the cleanup path: migrate `SocialServicing.status(of:)` to return the domain `FollowRelationship` directly. The mapping is total and lossless and already lives in `FollowMappers.swift`; once shipped, this file is dead code and deleted.
2. **Wave 1 deviation 5 closed this wave.** The follower/following/mutual/requests listing envelope ambiguity flagged at Wave 1 was pinned to the live API in commit `cae57cc`: followers/following use a `{ <key>: [...], pagination: {...} }` envelope; mutual returns counts (`{ mutualFollowers, mutualFollowing }`), not a user list; requests returns `{ requests: [...] }` with no pagination today. Kit suite gained 3 cases (174 → 177).
3. **`POST /api/follow/[userId]/remove` held at ◐⁴.** The "remove a user from my followers" action is reachable via `SocialService.removeFollower` but no tested view model this wave surfaces it. Tracked in coverage-matrix footnote 11; flips with the next M5 polish slice.
4. **Notification deep-link routing is a stub.** `AppDelegate.userNotificationCenter(_:didReceive:)` brings the app forward on notification activation but does **not** route to the related message / list / profile. The notification's `target` (typed `NotificationTarget` in the domain layer) is available; the routing layer to consume it is a `TODO(M5.x)` in `App/Composition/AppDelegate.swift`. In the meantime, the in-app Notifications tab is the route — also surfaced as a Limits bullet in `docs/user/feature-status.md`. Backend ask **2.4** (P2 — typed notification kinds + `routePath` field) remains the cleanest server-side enabler for the polish.
5. **UN-permission-denied UX is minimal.** When the user denies the macOS notifications prompt, the in-app Notifications tab still works but there is no "system notifications are off — open System Settings" hint anywhere in the UI. A v1.1 polish pass should add an inline banner in `NotificationsRootView` that detects the denied state via `UNUserNotificationCenter.current().notificationSettings()` and offers a deep-link to **System Settings > Notifications > InterlinedList**.
6. **Markdown editor cursor-aware insertions still deferred.** Carry-over from Wave 5 deviation 1 — no change this wave. SwiftUI `TextEditor`'s `TextSelection` API is macOS 26+; the toolbar still appends at end-of-buffer. Tracked for a future deployment-target bump.
7. **Sidebar growth at 8 rows.** The Wave 6 addition of `.connections` brings the sidebar to **Timeline / Lists / Profile / Connections / Documents / Notifications / Scheduled / Organizations** (with Scheduled and Organizations on placeholders pending M6, and Settings pending M7). The list is approaching the visual ceiling for an undivided sidebar; a regrouping pass (sections, dividers, possibly disclosure groups) is deferred until M6/M7 lands the remaining destinations so the grouping decision can be made with all rows visible at once.
8. **Stale SourceKit index after the new files were added.** Same pattern as Wave 3 deviation 6, Wave 4 deviation 8, Wave 5 deviation 7. Adding `App/Composition/AppDelegate.swift` + the new Social / Notifications view-model files + the new persistence stores left Xcode's SourceKit indexer reporting stale "No such module" / "No such type" errors on first reopen. `xcodebuild` was unaffected. Resolves with **File → Packages → Reset Package Caches** or **Product → Clean Build Folder**.
9. **`dev` → `main` merge happened during this wave.** Commits `cae57cc`, `da13846`, `159f71a`, `085b91f` and `9a66154` landed on `main` directly (verified by `git log --oneline -15`; the previous `dev` branch's last commit `d1e3575` was the Wave 5 docs gate). Future commits should remain on `main` per the user's branching pattern; the Wave 4 deviation 9 / Wave 5 deviation 8 carry-over about the contract-tests workflow being inert on `dev` is **resolved by this merge** — `workflow_dispatch` and `schedule` triggers register against the default branch, which is now seeing the workflow file.

---

## Wave 7 — InterlinedDomain M6 Subscriber surface + Persistence org/identity stores + App-layer Orgs / Composer-M6 / Linked-accounts UI (PLAN.md §6 M6)

Wave 7 lands M6 Subscriber + orgs end-to-end: the 7.0 OAuth spike + Kit gap closure (additive OAuth builders), the `InterlinedDomain` M6 slice (`OrgService` over all 9 Organizations endpoints, `UserService` identities / organizations + `identityLinkURL`, the subscriber-gated `MessagesService` M6 write surface — media / scheduled / cross-post), the `InterlinedPersistence` `SwiftDataOrgStore` + `SwiftDataLinkedIdentityStore`, the App-layer Organizations UI (`.organizations` route flipped off its placeholder), the M6 composer extensions + read-only Scheduled sidebar section (`.scheduled` route flipped), and the browser-handoff Linked-accounts pane in a real `SettingsRootView` (`.settings` scene off its placeholder). The wave's one new architectural decision — [Decision 0006](decisions/0006-oauth-identity-linking-browser-handoff.md) — records that **native OAuth identity-linking is blocked upstream** ([spike 0002](spikes/0002-oauth-identity-linking.md)) and ships the browser-handoff fallback, which deliberately needs **no AppKit / new-framework exception** (pure SwiftUI `@Environment(\.openURL)`).

Path ownership stayed inside `Packages/InterlinedKit/**` (the additive 7.0 OAuth builders + the 7.3 `UserService.identityLinkURL`-supporting builder + the 7.2 entitlements-backstop test surface), `Packages/InterlinedDomain/**`, `Packages/InterlinedPersistence/**`, `App/**`, `docs/spikes/0002-oauth-identity-linking.md`, `docs/decisions/0006-oauth-identity-linking-browser-handoff.md`, and `docs/**` / `README.md` / `NEXT-WORK.md` / `API-backend-prompts-to-build.md` for the docs touches. No PLAN.md / ORCHESTRATION.md / `docs/decisions/0001`–`0005` edits (read-only).

### Decisions

- **2026-06-25 — Decision 0006 recorded and accepted.** Native OAuth identity-linking (PLAN.md §4's `ASWebAuthenticationSession` mechanism) is **deferred — blocked upstream**. The 7.0 spike ([spike 0002](spikes/0002-oauth-identity-linking.md)) live-probed all four providers' `/authorize` flows and found the callback is a **web** URL on `interlinedlist.com` (no custom scheme / universal link a native client can register or intercept), the flow is **cookie-bound** (not Bearer-bound), and there is no code-exchange or bearer `…/link` endpoint to complete against. The decision ships the zero-upstream-change **browser-handoff fallback**: a Settings → Linked accounts pane opens `…/authorize?link=true` in the default browser via SwiftUI `@Environment(\.openURL)`. Unlike Decision 0005 (which carved out one AppKit file for the dock badge), this decision **needs no AppKit / new-framework exception** — `openURL` is public SwiftUI and the kit-import policy (decision 0003) is preserved by the new `UserServicing.identityLinkURL(provider:instance:)` domain method. The maintainer question is filed verbatim as `API-backend-prompts-to-build.md` ask 2.6 and tracked in `NEXT-WORK.md` NW-5. See [decisions/0006-oauth-identity-linking-browser-handoff.md](decisions/0006-oauth-identity-linking-browser-handoff.md).

### 7.0 — OAuth spike + InterlinedKit OAuth-builder gap closure — DONE

- **Spike.** [`docs/spikes/0002-oauth-identity-linking.md`](spikes/0002-oauth-identity-linking.md) — unauthenticated, redirect-not-followed `curl` against the live API characterizing `GET /api/auth/{github,mastodon,bluesky,linkedin}/authorize` (+ `?link=true` / `?instance=` behavior) and `GET /api/auth/linkedin/status`. **Verdict: native OAuth identity-linking is blocked upstream** — `/authorize` 307s to a *web* `…/callback`, the flow is cookie-bound (`HttpOnly` `oauth_state` + the web session cookie), and there is no custom-scheme / universal-link callback or bearer `…/link` endpoint a native client can complete against.
- **Kit gap closure (additive only).** `OAuthProvider` enum (`github` / `mastodon` / `bluesky` / `linkedin`, `.other(String)` for forward-compat) + `LinkedInStatusResponse` DTO (`DTOs/OAuthDTO.swift`); `Auth.authorize(provider:link:instance:) -> Request<EmptyResponse>` (public GET; `?link` / `?instance` query; `EmptyResponse` phantom because the endpoint replies 307 with no JSON body) and `Auth.linkedinStatus() -> Request<LinkedInStatusResponse>` (`Endpoints/AuthEndpoint.swift`). These make the five M6 OAuth coverage rows *buildable* but commit to **no UI** and **no new framework**.
- **Kit test count:** **177 → 190 (+13)** from the OAuth builder suite (provider matrix, `?link` / `?instance` query encoding, `linkedinStatus` decode, `.other` round-trip).

### 7.1 — InterlinedDomain M6 slice + Persistence org/identity stores — DONE

- **Domain — OrgService.** `OrgService` over all **9** Organizations endpoints, with `Organization` / `OrgMember` / `OrgUser` / `OrgRole` (`.other(String)` for forward-compat, matching the defensive shape `WatcherRole` (Wave 4) and `NotificationKind` (Wave 6) introduced) / `OrgsPage` / `OrgMembersPage` / `OrgMappers`. Methods: list-all, `create`, `organization(id:)`, `update`, `members(of:)`, `addMember`, `setMemberRole`, `removeMember`, `users(of:)`.
- **Domain — UserService.** `identities()` / `organizations()` projecting to `LinkedIdentity` / `IdentityProvider` (`.other(String)`); plus the new `identityLinkURL(provider:instance:) throws -> URL` (7.3) that resolves the Kit `Auth.authorize` builder against the configured base URL — keeps Decision 0003 intact so the App layer never touches a Kit type.
- **Domain — MessagesService M6 write surface.** `createPost` (media references + `scheduledAt` + cross-post flags: Mastodon provider-ids / Bluesky / LinkedIn), `scheduledPosts()`, `uploadImage` / `uploadVideo` via the `ImagePrep` pipeline (reused from Wave 5). All subscriber-gated via `EntitlementsService` — non-subscribers get `MessagesError.subscriberRequired` before any network call. Media limits are **hard-coded constants tagged `TODO(backend ask P2.5)`** (machine-readable limits are not yet exposed; deviation 7 below).
- **`EntitlementsService.canManageLists` left untouched.** Its flip belongs to a future M6 Lists-gating slice, not this wave (deviation 6 below).
- **Persistence.** `SwiftDataOrgStore` (orgs + per-org members, flat orgID keying) + `SwiftDataLinkedIdentityStore` (single-user identity cache); enums persisted as `wireToken` (lossless round-trip, `.other` preserved). Scheduled-post caching is **deferred** — it reuses the existing `MessageRecord` / `SwiftDataMessageStore` since `scheduledAt` is already persisted there.
- **Test counts (7.1 share):** Domain **+81** (OrgService / UserService / MessagesService M6); Persistence **+30** (`SwiftDataOrgStore` + `SwiftDataLinkedIdentityStore`).
- **Endpoint consumption:** the M6 Organizations + identities + media-upload rows are reachable at the domain-service layer after this slice, but per the Wave 1 deviation-6 rule they remain ◐⁴ until the App layer consumes them end-to-end — which happens in 7.2 / 7.3 / 7.4 below.

### 7.2 — App-layer composer M6 extensions + read-only Scheduled section + live-entitlements backstop — DONE

- **Composer M6 extensions** (`App/Features/Compose/`). Media attach via `.fileImporter` + `.dropDestination` + `AsyncImage` thumbnails (SwiftUI-only — no AppKit); `DatePicker` scheduling; cross-post toggles (Mastodon provider-ids / Bluesky / LinkedIn); subscriber-gated UI (controls disabled + an upsell affordance when the current user is not a subscriber). The composer's `createPost` path carries the M6 request fields end-to-end (resolves coverage-matrix footnote 2).
- **Read-only Scheduled sidebar section.** `ScheduledPostsRootView` + `ScheduledPostsViewModel` consuming `GET /api/messages/scheduled`; the `.scheduled` route flipped off its placeholder. **Read-only** — no cancel / reschedule (deviation 4; `NEXT-WORK.md` NW-3).
- **Deliverable B — live entitlements backstop.** `MessagesService` gained an **additive** `entitlementsProvider: @Sendable () -> EntitlementsService` initializer so the domain subscriber gate evaluates the **live** current-user `customerStatus` at call time (wired via a `LiveEntitlements` box updated by `CurrentUserStore`) rather than a value captured at construction. PLAN §8's 403 / lapse refresh hook was added so a mid-session entitlement change is respected.
- **Test counts (7.2 share):** Kit **+3** (`MessagesService` entitlements-backstop test surface), App `InterlinedListTests` **+24**.

### 7.3 — App-layer Organizations UI — DONE

- **Organizations feature** (`App/Features/Organizations/`). `OrganizationsRootView` + list / detail / member-roster with a role editor: `OrganizationsListViewModel` (lists the current user's orgs via `UserService.organizations()`), `OrganizationDetailViewModel` (`OrgService.organization(id:)` + `update`), `OrgMembersViewModel` (`members(of:)` + `addMember` + `setMemberRole` + `removeMember`). The `.organizations` sidebar route flipped off its placeholder.
- **Member-add is by raw userId** — no handle→userId lookup, the **same gap as NW-1 / backend ask 1.5**. Role edit / remove work for existing members. Tracked as deviation 3 and `NEXT-WORK.md` NW-6.
- **Domain — `identityLinkURL`.** Added this slice (`UserService.identityLinkURL(provider:instance:)`, Kit **+5** tests) to back the 7.4 Linked-accounts pane while keeping the App layer kit-import-free.

### 7.4 — App-layer Linked-accounts (browser handoff) — DONE

- **Decision 0006 fallback.** User-approved fallback since native linking is blocked. `SettingsRootView` **replaces** `SettingsPlaceholderView` in the `Settings{}` scene; its **Linked accounts** pane (`LinkedAccountsView` + `LinkedAccountsViewModel`) lists `UserService.identities()` and, per provider, offers **"Link account ↗"** that opens the web `…/authorize?link=true` in the default browser via SwiftUI `@Environment(\.openURL)` — **no AppKit, no new framework, no in-app completion.** Mastodon prompts for an instance domain first. After the browser flow, the pane refreshes `identities()`.
- **Decision 0003 intact.** The link URL is built by the domain `UserService.identityLinkURL(provider:instance:)` (which resolves the Kit `Auth.authorize` builder against the base URL); the App layer never references a Kit type.
- **Test counts (7.3 / 7.4 share):** App `InterlinedListTests` **+34**.

### Wave 7 gate — PASSED (2026-06-25)

- App build: `xcodebuild test -project InterlinedList.xcodeproj -scheme InterlinedList -destination 'platform=macOS'` → `Executed 278 tests, with 0 failures` / `** TEST SUCCEEDED **`.
- Domain tests: `swift test --package-path Packages/InterlinedDomain` → **388/388 passing**.
- Persistence tests: `swift test --package-path Packages/InterlinedPersistence` → **120/120 passing**.
- Kit tests: `swift test --package-path Packages/InterlinedKit` → **190/190 passing**.
- Decision-0003 compliance check: `grep -rEn "^[[:space:]]*import InterlinedKit" App/Features App/Navigation App/MenuCommands` → empty. The only `App/**` kit imports remain the permitted composition-root ones.
- Decision-0005 amended AppKit check: `grep -rEn "^[[:space:]]*import AppKit" App/ | grep -v AppDelegate.swift` → empty. The browser-handoff Linked-accounts pane uses SwiftUI `openURL` only — it adds **no** new AppKit hit, consistent with Decision 0006.
- SwiftUI-only check (Packages): `grep -R "import AppKit" Packages/` → empty.
- Path-ownership check: changes confined to `Packages/InterlinedKit/**`, `Packages/InterlinedDomain/**`, `Packages/InterlinedPersistence/**`, `App/**`, `docs/spikes/0002-oauth-identity-linking.md`, `docs/decisions/0006-oauth-identity-linking-browser-handoff.md`, `README.md`, `NEXT-WORK.md`, `API-backend-prompts-to-build.md`, and `docs/**` for this wave-end update — no overlaps with prior-wave paths; conflict rules held.

### Test counts per suite (run 2026-06-25)

| Suite | Tests | Notes |
| --- | ---: | --- |
| `InterlinedListTests` (full) | 278 | 220 → 278 (+58): **+24** in 7.2 (composer M6 extensions, read-only Scheduled section view model, live-entitlements backstop wiring) and **+34** in 7.3 / 7.4 (`OrganizationsListViewModel` / `OrganizationDetailViewModel` / `OrgMembersViewModel`, `LinkedAccountsViewModel`). The 220 Wave-6 tests are unchanged and still passing. |
| `InterlinedDomainTests` (full) | 388 | 299 → 388 (+89): **+81** in 7.1 (`OrgService` / `UserService` / `MessagesService` M6 quartets across all 9 Organizations endpoints, identities / organizations, `createPost` / `scheduledPosts` / `uploadImage` / `uploadVideo`, subscriber-gate paths), **+5** in 7.3 (`UserService.identityLinkURL`), **+3** in 7.2 (`MessagesService` entitlements-backstop). |
| `InterlinedPersistenceTests` (full) | 120 | 90 → 120 (+30): `SwiftDataOrgStore` (orgs + per-org members, flat orgID keying, second-write-wins, per-org isolation, clear cascade) + `SwiftDataLinkedIdentityStore` (single-user identity cache, `wireToken` round-trip incl. `.other`, clear). |
| `InterlinedKitTests` (full) | 190 | 177 → 190 (+13): the 7.0 OAuth builder suite (`Auth.authorize(provider:link:instance:)` provider matrix + `?link` / `?instance` query encoding, `Auth.linkedinStatus()` decode, `OAuthProvider.other` round-trip). Other Kit suites unchanged. |
| **Grand total across all targets** | **976** | All passing; 0 failures. |

### Coverage matrix delta (after this update)

The M6 consumption rule (Wave 1 deviation 6, reiterated in matrix footnote 4) applied: every M6-consumed row exercised by a tested App-layer view model this wave flips ◐⁴ → ☑. Separately, the five OAuth rows flip **Implemented** ☐ → ☑ (Kit builders landed in 7.0) but their **Tested** column stays untested (☐¹²) **by design** — native completion is blocked upstream ([decision 0006](decisions/0006-oauth-identity-linking-browser-handoff.md)), the app browser-opens the `…/authorize` URL rather than sending it, so there is no app-side send to test. Two OrgService read rows stay ◐⁴ (new footnote 13).

| | Before Wave 7 | After Wave 7 |
| --- | ---: | ---: |
| Implemented (☑) | 92 / 98 | **97 / 98** |
| Tested fully (☑) | 55 / 98 | **66 / 98** |
| Tested partial (◐⁴) | 36 / 98 | **25 / 98** |
| Untested (☐) | 7 / 98 | **7 / 98** |

**Implemented +5** (92 → 97): the four `GET /api/auth/{github,mastodon,bluesky,linkedin}/authorize` rows and `GET /api/auth/linkedin/status` gained Kit builders in 7.0. The single remaining unimplemented row is `POST /api/auth/login`⁵ (decision-0001 session-fallback login, still stubbed via `NullSessionEstablisher`).

Rows flipped ◐⁴ → ☑ this wave (**11 total**, all M6-consumed end-to-end Kit builder → Domain service → App view-model):

- User / Orgs: `GET /api/user/organizations` (`UserService.organizations` → `OrganizationsListViewModel`).
- Orgs: `POST /api/organizations` (`OrgService.create` → `OrganizationsListViewModel`).
- Orgs: `GET /api/organizations/[id]` (`OrgService.organization(id:)` → `OrganizationDetailViewModel`).
- Orgs: `PATCH /api/organizations/[id]` (`OrgService.update` → `OrganizationDetailViewModel`).
- Orgs: `GET /api/organizations/[id]/members` (`OrgService.members(of:)` → `OrgMembersViewModel`).
- Orgs: `POST /api/organizations/[id]/members` (`OrgService.addMember` → `OrgMembersViewModel`, by raw userId).
- Orgs: `PUT /api/organizations/[id]/members/[userId]` (`OrgService.setMemberRole` → `OrgMembersViewModel` role editor).
- Orgs: `DELETE /api/organizations/[id]/members/[userId]` (`OrgService.removeMember` → `OrgMembersViewModel`).
- User: `GET /api/user/identities` (`UserService.identities` → `LinkedAccountsViewModel`).
- Messages: `POST /api/messages/images/upload` (`MessagesService.uploadImage` → `ComposerViewModel`; `ImagePrep` exercised).
- Messages: `POST /api/messages/videos/upload` (`MessagesService.uploadVideo` → `ComposerViewModel`).

Implemented but Tested-untested by design this wave (new footnote 12, ☐¹²):

- `GET /api/auth/github/authorize`, `GET /api/auth/mastodon/authorize`, `GET /api/auth/bluesky/authorize`, `GET /api/auth/linkedin/authorize` — Kit builders exist; reached **indirectly** via `UserService.identityLinkURL` → `LinkedAccountsView` → SwiftUI `openURL` (browser-opened, not sent by the app). Native completion blocked upstream (spike 0002 / decision 0006).
- `GET /api/auth/linkedin/status` — Kit builder exists but is currently **unconsumed**.

Re-consumed but unchanged (☑ already from earlier waves):

- `POST /api/messages` — already ☑ from Wave 1 (M6-field builder coverage, footnote 2). Its scheduled / cross-post / media request fields are now consumed end-to-end via `ComposerViewModel` this wave; **footnote 2 is resolved** (the M6-field carriage is closed rather than pending). Row state unchanged.
- `GET /api/messages/scheduled` — already ☑ from Wave 1; re-consumed read-only this wave by `ScheduledPostsViewModel`. Row state unchanged.

Held back at ◐⁴ this wave (new footnote 13):

- `GET /api/organizations` (list-all variant) — reachable via `OrgService` but the Organizations UI lists the current user's orgs via `UserService.organizations()` (`GET /api/user/organizations`) instead, so the list-all path stays unconsumed.
- `GET /api/organizations/[id]/users` — reachable via `OrgService.users(of:)` but the member roster renders from `GET /api/organizations/[id]/members` (`OrgMembersViewModel`), leaving the `/users` projection unconsumed.

### Deviations and follow-ups

1. **Native OAuth identity-linking is blocked upstream; M6 ships a browser handoff.** [Spike 0002](spikes/0002-oauth-identity-linking.md) found the `/authorize` callback is a web URL (no custom scheme / universal link), the flow is cookie-bound (not Bearer), and there is no bearer `…/link` endpoint. [Decision 0006](decisions/0006-oauth-identity-linking-browser-handoff.md) ships the zero-upstream-change fallback: Settings → Linked accounts opens `…/authorize?link=true` in the default browser via SwiftUI `openURL`, no in-app completion. Deliberately **no AppKit / new-framework exception** is created (contrast Decision 0005). Maintainer question filed verbatim as backend ask **2.6** (P2); resume design tracked in `NEXT-WORK.md` NW-5. The five OAuth coverage rows flip Implemented but stay Tested-☐¹² until the upstream contract lands.
2. **`MessagesService` live-entitlements backstop (Deliverable B).** The domain subscriber gate evaluates the live current-user `customerStatus` at call time via an additive `entitlementsProvider: @Sendable () -> EntitlementsService` init (wired through a `LiveEntitlements` box updated by `CurrentUserStore`), so a mid-session entitlement change is respected rather than a value captured at construction. PLAN §8's 403 / lapse refresh hook was added. Additive — no existing call site changed.
3. **Org member-add is by raw userId — no handle search.** `OrgMembersViewModel` → `OrgService.addMember` takes a `userId`; there is no handle→userId lookup. Same blocker as NW-1 / backend ask **1.5** (now noted on 1.5 as a second consumer). Role edit / remove work for existing members. Tracked in `NEXT-WORK.md` NW-6.
4. **Scheduled section is read-only.** `ScheduledPostsRootView` lists `GET /api/messages/scheduled` but cannot cancel or reschedule a post before `scheduledAt` fires (no documented cancel / reschedule path). Backend ask **3.3** (P3); tracked in `NEXT-WORK.md` NW-3.
5. **Two OrgService reads unconsumed this wave (coverage footnote 13).** `GET /api/organizations` (list-all — UI uses `UserService.organizations()` instead) and `GET /api/organizations/[id]/users` (`OrgService.users(of:)` — roster renders from `/members`). Both reachable, neither on a tested view-model path this wave; the Wave 1 footnote-4 backfill rule still applies. Tracked in `NEXT-WORK.md` NW-6.
6. **`EntitlementsService.canManageLists` left untouched.** Its flip belongs to a future M6 Lists-gating slice, not this wave. The M6 subscriber gating shipped this wave covers the composer / media / scheduled / cross-post surface (`MessagesError.subscriberRequired`); list-management gating is a separate, deliberately deferred slice. No behavior change to `canManageLists` this wave.
7. **M6 media limits hard-coded (`TODO(backend ask P2.5)`).** `ImagePrep` resizes against hard-coded 1200 px / 1.4 MB image and 3 MB video budgets because machine-readable upload limits are not exposed by the API (backend ask **2.5**, P2 — Wave 7 note added there). The constants are tagged `TODO(backend ask P2.5)` and replaced when the limits become discoverable.
8. **Cross-post per-platform result + readiness gaps.** The composer sends cross-post targets but cannot render a per-platform "posted ✓ / failed" status sheet (backend ask **1.4**, P1; `NEXT-WORK.md` NW-2), and can only pre-flight LinkedIn readiness — not Bluesky / Mastodon (backend ask **3.6**, P3; `NEXT-WORK.md` NW-4). Both surfaced as `docs/user/feature-status.md` Limits bullets.
9. **Stale SourceKit index after the new files were added.** Same recurring pattern as Wave 3 deviation 6, Wave 4 deviation 8, Wave 5 deviation 7, Wave 6 deviation 8. Adding the Organizations / Composer-M6 / Linked-accounts view-model files + the new persistence stores left Xcode's SourceKit indexer reporting stale "No such module" / "No such type" errors on first reopen. `xcodebuild` was unaffected. Resolves with **File → Packages → Reset Package Caches** or **Product → Clean Build Folder**. Carrying the note forward.

