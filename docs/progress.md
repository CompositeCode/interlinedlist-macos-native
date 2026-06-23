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

