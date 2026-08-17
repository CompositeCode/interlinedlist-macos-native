# InterlinedList macOS — Work Consolidation

**Single source of truth for remaining work, in execution order.** This file consolidates and replaces six older docs (see [Provenance](#provenance)): the parity gap lists, the backend-blocker index + paste-ready prompts, the Document Sync Agent plan, and the v1 release checklist.

- **Consolidated:** 2026-08-15 · **Branch:** `dev` · **Bundle:** `com.interlinedlist.macos` · **Team:** `BJA9558E4B`
- **Structure:** [§1 Immediate work (do now)](#1-immediate-work--unblocked-do-now) → [§2 Blocked work (backend / spike-first)](#2-blocked-work--backend-gated-or-spike-first) → [§3 Final work (release & App Store)](#3-final-work--release--app-store)
- **Test baseline (all green, 2026-08-16):** SyncAgent **53** · InterlinedKit **286** · InterlinedDomain **590** · InterlinedPersistence ~**135** · App target **566** (`xcodebuild test … CODE_SIGNING_ALLOWED=NO`). Packages run under plain `swift test`; the App test target needs the signing override on this machine.
- **Distribution model:** notarized **`.pkg`** (+ `.dmg`) is the **current** ship path (closed-source private repo, no `LICENSE`). Mac App Store is a **later** path on a separate branch. Billing is handled by the web app — the native app has **no** in-app-purchase surface; it only *reads* `customerStatus` to gate subscriber features.

---

## Status snapshot — already shipped (do NOT re-implement)

The July web-parity batch (`feature/web-parity-batch-2026-07`) merged into `dev`. Shipped with services + App UI + tests:

- **Messaging & safety:** Direct Messages (folders/threads/read-state/unread badge/image attachments) · Moderation (block/mute/report + Settings ▸ Blocked & Muted).
- **Collaboration:** Share Links & resolve/claim for lists + documents (`interlinedlist://…/shared/{token}`) · Search (messages/lists/documents) · List Folders (cycle-safe tree).
- **Reach & content:** X/Twitter cross-post (⚠️ field name unverified — see [§1](#g7-verify-x-twitter-cross-post-field-name)) · server document templates · rich public profiles (`GET /api/users/{username}`) · schema DSL `select`/`markdown` · cards + real-`Table` grid list views · Markdown export (lists) + CSV export.
- **Auth:** native OAuth identity linking (`POST /api/auth/{provider}/link` + `interlinedlist://oauth/callback` + `ASWebAuthenticationSession`) — directly unblocks GitHub/X linking.
- **Settings storage (2026-08-16):** server-synced account **Preferences** — the backend now accepts `POST /api/user/update` (previously 405). `UserSettings` domain model + mapper, `UserService.settings()`/`updateSettings()`, and a Settings ▸ **Preferences** pane (public-by-default, advanced post options, link previews, posts-per-page, private account) with change-gated Save. 9 tests. *Deferred:* `theme` and `viewingPreference` (valid value sets unconfirmed; PATCH omits them so they're never clobbered).
- **Infrastructure (beyond parity):** on-disk **SWR cache + launch prefetch** (Lists/Documents/Scheduled/Organizations paint-from-cache, revalidate in background) · the **Document Sync Agent** (`SyncAgent/` — a bundled `LSUIElement` menu-bar utility that mirrors documents to a local Markdown folder for Obsidian; built + unit/live-tested; remaining work is on-device ship validation in [§3](#3b-document-sync-agent--on-device-validation)) · friendly loading-error messages + rotating debug log · App target is now **sandboxed + hardened**.

Milestones **M0–M7** feature work is complete; post-milestone items NW-1…NW-6, S1/S3/S4, B8 are done.

---

## 1. Immediate work — unblocked, do now

Everything here is client-side and buildable today (the backend already exists or none is needed). Ordered by value.

### 1a. Parity features buildable now

<a id="g4-github-issue-integration"></a>
**G4 · GitHub issue integration** *(largest buildable parity gap; backend live)*
The `/api/github/*` routes are deployed (`GET /api/github/repos` → 400 "GitHub account not linked" — the route exists; 400 is just the unlinked state), and native OAuth linking already ships, so linking is no longer a blocker. Build the issue-write client: `GitHubEndpoint` (`repos`, `issues(repo:state:)`, `createIssue`, `updateIssue` PATCH labels/assignees, `comment`, `assignees`, `labels`, `nextIssueNumber`) → `GitHubService` (requires a linked identity; if unlinked, deep-link the existing native OAuth flow) → App ("Create issue from message" overflow action + issue browse/create/comment inside GitHub-backed lists + inline "Link GitHub" CTA). **Verify-first:** link the test account's GitHub identity once and observe the live request/response shapes before finalizing the decode paths (backend shape docs are requested in [§2 · P1-H](#p1-h-github-issue-shapes) but you can proceed by observation). **Size M.**

<a id="g7-verify-x-twitter-cross-post-field-name"></a>
**G7 · Verify X/Twitter cross-post field name** *(one-file fix)*
The composer ships an X/Twitter toggle sending `crossPostToTwitter: true` on `POST /api/messages`, pattern-matched from Bluesky/LinkedIn but **never verified** (test account has no linked X identity). Link an X identity, post, and confirm the field is `crossPostToTwitter` (vs `crossPostToX`) and that the result appears in the `crossPosts[]` envelope with a stable `platform` value. If wrong, it's a one-line change in `CreateMessageRequest`. **Size S.** (Backend confirmation prompt: [§2 · P2-H](#p2-h-x-twitter-field-name).)

**G11a · LinkedIn posting target** — ✅ **Target-aware toggle shipped 2026-08-15.** `LinkedInService` is now wired into `AppEnvironment`; enabling the composer's LinkedIn cross-post toggle fetches `postingTargets()` and shows **which destination the post publishes to** ("Posting as …"), rolls the toggle back with a connect hint when the account has no LinkedIn target, and surfaces the org-scope-missing note — all mirroring the Bluesky/Mastodon readiness pattern and reusing the verified `crossPostToLinkedIn` request path. 6 composer tests. **Deferred (needs a verified wire shape):** a true multi-*target selector* and the `POST /api/linkedin/sync-pages` refresh both wait on a confirmed per-target request field; LinkedIn **org** pages are upstream-blocked (G11b).

**G14 · `/api/limits` composer validation** — ✅ **Message-length validation shipped 2026-08-15.** New Kit `Limits` endpoint + `LimitsDTO`; domain `ContentLimits` model + `ContentLimitsService` (fetch with `ContentLimits.default` fallback); wired into the composer as a live character counter + publish gate (over-limit disables Post, turns the counter/border red). 13 tests (4 Kit + 4 Domain + 5 App). **Remaining follow-up (smaller):** feed the same `ContentLimits` into `ImagePrep` so the image/video *size* ceilings are server-driven too — today `ImagePrep` keeps the matching hard-coded constants (which equal the live values).

### 1b. Client-side follow-ups & polish (no backend)

- **ERD list view** — **scoped 2026-08-16 (needs a product call before building).** Findings: (b) a **list-to-list connection graph is redundant** — it already ships as `ListConnectionsView` (nodes = lists, edges = `ListConnection`, add/remove/label, now with the force-directed layout); recommend closing that interpretation. (a) A **true entity-*relationship* diagram (FK-style edges between list schemas) is backend-blocked** — there is no cross-list reference data; the `link(listSlug)` schema field type is deferred (P2-G). The one buildable, data-backed scope is (a) as a **per-list schema *entity* view** (one entity box: the list's fields + types, `select` options; optionally parent/`ListConnection` neighbor edges) added as a third `ViewMode` on `ListRowsViewModel` — App-layer only, no Kit/Domain changes. **But it's thin** (close to a restyle of the schema editor's field list), so confirm product intent — schema-entity view (buildable, Size S) vs. a true relationship ERD (blocked on P2-G) — before building.
- ~~**Per-document / per-thread "Export as Markdown" buttons**~~ — ✅ **Shipped 2026-08-15.** The document-editor toolbar ("Export as Markdown") and the message-thread toolbar now export via a shared `MarkdownExportRequest` + the existing `MarkdownFileDocument` save flow; `ExportViewModel` was de-duplicated onto the shared type. 10 tests.
- ~~**Public grid on read-only `ListDetailView`**~~ — ✅ **Shipped 2026-08-15.** The public list browser now has a Cards/Table segmented toggle above the rows and renders a real `Table` (one column per derived field, "Load More" footer), mirroring the owned `ListRowsView`; `ListDetailViewModel` gained a `viewMode` (default Cards). 4 tests; `StubListsService` public paths made programmable.
- ~~**S2 · Message store on-disk persistence**~~ — ✅ **Verified done 2026-08-15.** `AppEnvironment.makeMessageStore()` already returns the on-disk `SwiftDataMessageStore` (in-memory → `NullMessageStore` fallbacks), matching the lists/documents/orgs caches — the timeline paints from disk on launch and revalidates. The SWR-cache commit closed the swap; only a stale "TODO M4" doc-comment remained (now corrected). `InMemoryMessageStore` is test-only.
- ~~**M3.x · Force-directed connections-graph layout**~~ — ✅ **Shipped 2026-08-16.** New pure, deterministic `ForceDirectedLayout` engine (`InterlinedDomain`, Fruchterman–Reingold; seeded by node index, fixed iterations, epsilon-guarded — no `Date`/RNG); `ListConnectionsViewModel.layout(in:)` uses it, with dragged nodes pinned across relayouts. 12 domain + 3 view-model tests.

---

## 2. Blocked work — backend-gated or spike-first

Cannot be finished from the client alone. Each item carries a paste-ready prompt for the InterlinedList backend Claude Code session (base URL `https://interlinedlist.com`). **The single high-impact backend blocker is P1-G (Following feed);** everything else is a spike, a confirmation, or low-priority polish.

### 2a. High-impact blocker

<a id="p1-g-following-feed"></a>
**P1-G · Following / home feed endpoint** — **HIGH.** Re-verified 2026-07-31: `GET /api/messages` ignores `feed`/`scope`/`following`/`filter` (every variant returns the same "all" feed) and `POST /api/user/update {viewingPreference}` → 405. The client's `TimelineScope.following` is fully UI-wired (All/Mine/Following picker) but `MessagesService.timeline` short-circuits `.following` to an empty "coming soon" page (`MessagesService.swift:364`). One client branch flips to consume this the moment it exists.

> **PROMPT:** You are working on the InterlinedList API (interlinedlist.com). Add a followed-accounts timeline feed. Preferred: extend `GET /api/messages` with `?scope=following` (or add `GET /api/feed/following`), returning only messages authored by accounts the caller follows, using the **same paginated envelope** as `GET /api/messages` (same `limit`/`offset`/`hasMore` shape). Bearer auth. Document it. Note: as of 2026-07-31 the live server silently ignores `scope`/`feed`/`following`/`filter` on `GET /api/messages` and `POST /api/user/update {viewingPreference}` → 405, so this needs a real implementation, not just docs. The macOS client already has the UI wired and flips one branch to consume it.

### 2b. Spike-first native gaps

**G9 · Push notifications (APNs)** — route live (`POST /api/push/register` → 400 "token is required"). **Spike S2 first:** does a sandboxed, notarized, non-App-Store `.pkg` support APNs, and what provisioning is required? Also confirm the `unregister` verb (POST → 405, likely DELETE). Deep-link routing wants the backend `routePath` field ([P2-C](#p2-c-notification-routepath)). Then: register the device token on launch/sign-in, unregister on sign-out; real pushes augment (don't replace) tray polling. **Size M.**

**G10 · Multi-account switching** — **Spike S4 first:** `/api/auth/accounts` returns 401 under Bearer (session-cookie-only). Resolve the Bearer-vs-session constraint (drive a cookie session for these routes, or request a bearer variant upstream — see [P3-D](#p3-d-sessions-revocation)) before building the account switcher + per-account `KeychainCredentialStore` + cache reset on switch. **Size M.**

### 2c. Backend confirmation & polish asks

Reconciliations and additive niceties. The client already works around each; these make it correct/efficient. Additive fields are always safe (the client decodes by name and ignores unknowns).

<a id="p1-f-auth-decision"></a>
**P1-F · Auth decision on `GET /api/messages`** (200 unauthenticated). Client always sends Bearer — no client change either way; needs a documented decision.
> **PROMPT:** `GET /api/messages?limit=1` returns HTTP 200 with public message content without an `Authorization` header. Make a documented decision. **Option A — Public-by-design:** document that unauthenticated requests return only `publiclyVisible: true` messages; confirm/add the filter; update docs. **Option B — Lock it down:** add an auth check, return 401 `{"error":"unauthorized"}` without a Bearer token. The macOS client always sends a Bearer token — no client change needed either way.

**P2-B · Follow action returns `followedBy`.** Client decodes `{ follow: { status } }`; `followedBy` still needs a 2nd `GET /api/follow/[userId]/status` call.
> **PROMPT:** Extend `POST /api/follow/[userId]` to include a `relationship` block, eliminating one round-trip: `{ "follow": { "status": "active" }, "relationship": { "following": true, "pendingRequest": false, "followedBy": false } }`. Apply the same block to `DELETE /api/follow/[userId]` and `POST /api/follow/[userId]/approve` / `reject`. Additive.

<a id="p2-c-notification-routepath"></a>
**P2-C · Typed notification kinds + `routePath`.** Deep-linking works via the client's typed `NotificationTarget` projection; a stable `routePath` collapses it to a plain URL and unblocks APNs push routing ([G9](#2b-spike-first-native-gaps)).
> **PROMPT:** Document and stabilize the notification `type` field from `GET /api/notifications` and add a `routePath` field. (1) Document the closed enum; the client assumes `dig, reply, mention, follow_request, follow_accepted, list_shared, list_row_added, org_invite` — confirm/correct, and include any DM notification type. (2) Add `routePath` (path relative to `interlinedlist.com`): `dig`/`reply`/`mention` → `/messages/[messageId]`; `follow_request`/`follow_accepted` → `/profile/[actorUsername]`; `list_shared`/`list_row_added` → `/lists/[listSlug]`; `org_invite` → `/organizations/[orgId]`. Additive.

**P2-F · Markdown export format / per-item export.** `/api/exports/*` is CSV-only; client renders MD itself (`MarkdownExporter`), which costs N+1 refetches for bulk export.
> **PROMPT:** Add Markdown export. (1) A format param on the four export endpoints, e.g. `GET /api/exports/lists?format=md` (or `Accept: text/markdown`). (2) Per-resource endpoints: `GET /api/documents/[id]/export?format=md`, `GET /api/messages/[id]/thread/export?format=md`, `GET /api/lists/[id]/export?format=md`. Lists render as Markdown tables.

**P2-G · Schema DSL `select`/`markdown` token spec.** Client emits **and** parses both; `Field:select(a|b|c)` (token `select`, `(...)` wrapper, `|` delimiter) is a **client convention, still API-unconfirmed**.
> **PROMPT:** Document and confirm the list schema DSL type tokens the macOS client now emits: (1) **`select`** with an ordered option set — the client uses `Field:select(a|b|c)`; confirm the token, delimiter, and whether the server persists/re-emits the option list verbatim on `GET .../schema` or normalizes it. (2) **`markdown`** — confirm the cell value is a plain JSON string of raw Markdown. (3) Confirm the server accepts the existing **`email`** token on `PUT .../schema`.

<a id="p2-h-x-twitter-field-name"></a>
**P2-H · X/Twitter cross-post field name.** Client ships `crossPostToTwitter` unverified (see [§1 · G7](#g7-verify-x-twitter-cross-post-field-name)).
> **PROMPT:** Confirm the exact request-body field name for cross-posting a message to X/Twitter on `POST /api/messages`. The client sends `crossPostToTwitter: true` (mirroring `crossPostToBluesky` / `crossPostToLinkedIn`). Confirm this vs `crossPostToX` or another spelling, document it alongside the other cross-post flags, and confirm the per-platform result appears in the `crossPosts[]` response envelope with a stable `platform` value for X.

**P3-A · Document version / ETag** for sync conflict detection.
> **PROMPT:** Add `version: int` to the document object on all read/sync endpoints. Accept `If-Match: <version>` on `PATCH /api/documents/[id]`; when present and stale, return `409 { "error": "version_conflict", "currentVersion": 42, "serverDocument": {…} }`. When absent, keep server-wins (no breaking change). Increment `version` on every successful `PATCH`.

**P3-B · `folderId` on sync-response documents.**
> **PROMPT:** Confirm `GET`/`POST /api/documents/sync` include `folderId` on every document entry — including conflict-resolution preserved-copies and deleted documents (their pre-deletion `folderId`). Add it if missing; document the field name. Confirm the `folderId` field name is consistent between `/api/documents/tree` and `/sync`.

**P3-C · GitHub-backed list refresh metadata + `githubSource` on create.** Client models the projection (`GitHubListSource`); rows carry `source`/`githubRepo` live; refresh fields + create-time `githubSource` unconfirmed. Coordinate with [P1-H](#p1-h-github-issue-shapes).
> **PROMPT:** Add to List objects with `githubSource`: `{ "lastRefreshedAt": "iso-8601 or null", "refreshStatus": "idle|pending|failed", "refreshError": "string or null" }`. Also accept `githubSource` on `POST /api/lists`: `{ "owner", "repo", "path", "ref" }`; if provided, trigger initial refresh and return `refreshStatus: "pending"`.

<a id="p3-d-sessions-revocation"></a>
**P3-D · Token revocation + `GET /api/user/sessions`.** Relates to [G10](#2b-spike-first-native-gaps) (accounts are session-cookie-only, 401 under Bearer); a Bearer-reachable sessions surface helps both.
> **PROMPT:** Add optional `deviceLabel` to `POST /api/auth/sync-token`. Implement `GET /api/user/sessions` → `{ sessions: [{ id, deviceLabel, createdAt, lastUsedAt, isCurrent }] }` and `DELETE /api/user/sessions/[id]` → 204 (token immediately invalid; 400 `{"error":"cannot_revoke_current_session"}` on self-revoke).

**P3-E · `RateLimit-*` headers universally.** Currently only on `POST /api/messages` and `POST /api/documents/sync`; client already nil-guards absent headers.
> **PROMPT:** Add `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset` to every authenticated response, and `Retry-After` on 429s (RFC 6585 + draft IETF RateLimit spec).

**P3-F · Link-preview `fetchStatus` value docs.** Client renders previews, gating on a forward-compatible "ready-ish" value set + title/image presence.
> **PROMPT:** Document the closed value set for `fetchStatus` on message `linkMetadata.links[]` — which value means "preview ready" vs "still fetching" vs "failed" — so the client can gate rendering on the authoritative token(s).

**P3-G · List "save to my lists" clone-with-rows.** `ListDetailViewModel.saveToMyLists` copies title/description/schema only, **no rows** (documented degradation; no clone endpoint exists).
> **PROMPT:** Add `POST /api/lists/[id]/clone` (or a rows-copy option on save) that duplicates a public list's rows into a new owned list, so "save to my lists" carries the data, not just the schema.

**P3-H · Message edit verb reconciliation.** Reference documents `PATCH /api/messages/[id]`; client sends `PUT` (both work live).
> **PROMPT:** The API reference documents message edit as `PATCH /api/messages/[id]`, but the client sends `PUT` and it works. Confirm the canonical verb and reconcile the reference with live behavior. While you're here, confirm the canonical verb for `/api/messages/{id}/replies` (OpenAPI shows `POST`; the client uses `GET`).

<a id="p1-h-github-issue-shapes"></a>
**P1-H · GitHub issue create/comment + labels/assignees shapes** *(docs; unblocks [§1 · G4](#g4-github-issue-integration) end-to-end).* Routes are deployed; shapes are undocumented and can only be exercised once a test identity links GitHub.
> **PROMPT:** The GitHub issue routes are deployed but undocumented for third-party clients. Define and document, with concrete request/response JSON: (1) issue **labels** and **assignees** as fields on GitHub-sourced list rows; (2) the endpoint to **create a GitHub issue** from a synced list; (3) the endpoint to **comment on an issue**; (4) `next-issue-number` if it exists. State the linked-identity precondition and the exact 400 error body when unlinked. Coordinate with P3-C.

### 2d. Upstream-blocked / deferred (confirm demand before building)

- **G11b · LinkedIn org posting pages** — upstream-blocked on this tenant (`orgScopesEnabled:false`, `…/linkedin-page` → 404; not deployed). Personal targets (G11a) are unaffected.
- **G13 · Document presence / live cursors** — highest complexity, lowest urgency; not probed. Confirm demand first.

---

## 3. Final work — release & App Store

Ship gating is orthogonal to parity and can proceed in parallel with §1/§2. Detailed command references live in **`App-Dmg-Pkg-Deployment.md`** (retained).

### 3a. Notarized PKG/DMG release — the current ship path

One-time signing setup on the build machine, then the release run. Complete in order.

**Sparkle keys & Info.plist**
- [ ] Generate the Sparkle Ed25519 key pair: `./bin/generate_keys` (store the private key in a password manager — never commit).
- [ ] Paste the public key into `App/Resources/Info.plist` → `SUPublicEDKeyString` (currently `TODO_REPLACE_WITH_ED25519_PUBLIC_KEY`).
- [ ] Verify the live update-check call, `SUFeedURL`, and `SUPublicEDKeyString` resolve against the published appcast.

**Developer ID credentials & CI secrets**
- [ ] Store notarization credentials: `scripts/store-notarization-profile.sh` (Apple ID, Team ID `BJA9558E4B`, app-specific password) → creates a `NotarizationProfile` Keychain item.
- [ ] Add GitHub Actions secrets (`App-Dmg-Pkg-Deployment.md` §1b): `CERTIFICATES_P12` (base64 of Developer ID Application + Installer .p12), `CERTIFICATES_P12_PASSWORD`, `CODESIGN_IDENTITY`, `INSTALLER_IDENTITY`, `NOTARIZATION_PASSWORD`. *(The `.env` `CODESIGN_IDENTITY` / `INSTALLER_IDENTITY` are placeholders — replace with real Developer ID certs.)*

**Build, sign, publish**
- [ ] Local build: `scripts/notarize-and-package.sh` (env vars per `App-Dmg-Pkg-Deployment.md` §3b) → produces `.pkg` + `.dmg` in `releases/`. This step also builds and embeds the Document Sync Agent (see [§3c](#3b-document-sync-agent--on-device-validation)).
- [ ] Sign the update: `./bin/sign_update releases/InterlinedList-<version>.pkg`; copy the `edSignature` + byte count into `releases/appcast.xml` (replace `TODO_REPLACE_WITH_SIGNATURE` and `length="0"`).
- [ ] Upload `.pkg`, `.dmg`, `.sha256` to `https://interlinedlist.com/downloads/apple/`.
- [ ] Publish the appcast: upload `releases/appcast.xml` to `https://interlinedlist.com/appcast.xml` (needs distribution infra on interlinedlist.com).
- [ ] Tag & push: `git tag v1.0.0 && git push origin v1.0.0` → triggers `release.yml` (draft GitHub release). *(Per project convention, the tag/push is owner-driven.)*
- [ ] Publish the draft GitHub release.

**Backend deploy prerequisite (gates the Moderation feature that already ships client-side)**
- [ ] Run production migrations: `npm run db:migrate:deploy` — two pending: `add_moderation_tables`, `add_moderation_versioning_sessions`.
- [ ] Resolve [P1-F](#p1-f-auth-decision) (document the `GET /api/messages` unauthenticated behavior).

<a id="3b-document-sync-agent--on-device-validation"></a>
### 3b. Document Sync Agent — on-device validation

The agent (`SyncAgent/`) is built and unit/live-tested (53 passing incl. a read-only live check). The packaging pipeline embeds it at `InterlinedList.app/Contents/Library/LoginItems/InterlinedListSync.app` and registers it as an `SMAppService.agent` via **Settings ▸ Document Sync**. Remaining work needs a real Aqua session + Developer ID (not runnable headless):
- [ ] Menu-bar GUI smoke (status item, Preferences window).
- [ ] Full notarized `.pkg` install → `SMAppService.agent` registration (visible in System Settings ▸ Login Items) → the running agent reads the bearer token from the shared Keychain group `$(AppIdentifierPrefix)com.interlinedlist.shared` → syncs with no separate sign-in; confirm legacy-token → shared-group migration.
- [ ] Exercise live **write** paths (create/update/delete) once (they share the request-building + envelope decoder the read paths cover).

### 3c. Mac App Store submission — later, on an `app-store` branch

Removing Sparkle breaks the PKG/DMG channel, so App Store work happens on a separate branch.

**Code changes (`app-store` branch)**
- [ ] **B1 — Remove Sparkle** (six locations per `App-Dmg-Pkg-Deployment.md` §7a): `project.pbxproj` (package ref + product dep + build file), `Package.resolved` (`sparkle` pin), `Info.plist` (`SUFeedURL`, `SUPublicEDKeyString`, comment block), delete `App/Composition/SparkleController.swift` + `App/MenuCommands/UpdatesMenuCommands.swift`, remove `sparkleController` + `UpdatesMenuCommands(…)` from `App/InterlinedListApp.swift`.
- [ ] **B3 — Release signing identity** → change `CODE_SIGN_IDENTITY[sdk=macosx*]` from `Apple Development` to `Apple Distribution` (Release config `BABD889F`).
- [ ] **Version bump** → `MARKETING_VERSION` = `1.0`, `CURRENT_PROJECT_VERSION` = `2` (Debug + Release).

**CI secrets (App Store):** `APPSTORE_CERTIFICATES_P12`, `APPSTORE_CERTIFICATES_P12_PASSWORD`, `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`, `ASC_API_KEY_P8` (base64 of the .p8 — downloadable only once).

**App Store Connect**
- [ ] Register bundle ID `com.interlinedlist.macos` (enable App Sandbox + Hardened Runtime).
- [ ] Create the app record (SKU `interlinedlist-macos-001`), fill metadata (`App-Dmg-Pkg-Deployment.md` §6c), upload screenshots (≥1, recommend 10 @ 2560×1600 → `brand-kit/screenshots/appstore/`), complete the Privacy Nutrition Label (§10).
- [ ] Archive (confirm **Apple Distribution** signing) → Validate → Upload → select build → fill App Review Information (demo account + notes + contact) → Submit.

**Website (hard blockers for the App Store form)**
- [ ] **B6 — Privacy Policy** at `https://interlinedlist.com/privacy` (data collected, storage, third-party sharing = user-triggered cross-posting only, account deletion in Settings, contact, effective date).
- [ ] **B7 — Support page** at `https://interlinedlist.com/support` (contact, help-doc links, bug reporting).
- [ ] Verify both return 200 without login. *(These are the backend `P2-E` ask — deferred until this path is pursued; not needed for the PKG/DMG release.)*

**Demo account (App Review)**
- [ ] Create a reviewer account on interlinedlist.com with subscriber access + sample content (posts, one list with rows, one document). Record credentials for App Store Connect.
- [ ] App Review notes: *"Settings ▸ Linked Accounts opens the default browser for OAuth — return to InterlinedList when done. The 'Following' timeline scope shows a Coming Soon state (backend feed not yet available)."*

### Completion criteria
- **PKG/DMG release:** §1 core done + [§3a](#3a-notarized-pkgdmg-release--the-current-ship-path) + [§3b](#3b-document-sync-agent--on-device-validation) checked. (S2/M3.x are non-blocking polish.)
- **App Store release:** the above **plus** [§3c](#3c-mac-app-store-submission--later-on-an-app-store-branch) fully checked.

---

## Provenance

This file consolidates and replaces the following, now removed (recoverable via git history):

- `feature-gaps.md` — parity gap snapshot (2026-07-18 → refreshed 2026-08-15).
- `the-gaps.md` — the master parity gap list + wave plan + live-probe evidence (2026-07-31).
- `feature-blockages.md` — the backend-blocker index (2026-08-15).
- `blocker-prompts.md` — the paste-ready backend `P#` prompts (preserved in [§2](#2-blocked-work--backend-gated-or-spike-first)).
- `synch-plan.md` — the Document Sync Agent plan (built + tested; remaining validation in [§3b](#3b-document-sync-agent--on-device-validation); full architecture in `SyncAgent/` + git history).
- `v1-release-checklist.md` — the release/App Store checklist (folded into [§3](#3-final-work--release--app-store)).

Retained references: `App-Dmg-Pkg-Deployment.md` (deployment command detail), `README.md`, `docs/`.
