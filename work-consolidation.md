# InterlinedList macOS — Work Consolidation

**Single source of truth for remaining work, in execution order.** This file consolidates and replaces six older docs (see [Provenance](#provenance)): the parity gap lists, the backend-blocker index + paste-ready prompts, the Document Sync Agent plan, and the v1 release checklist.

- **Consolidated:** 2026-08-15 · **Last synced to code:** 2026-09-05 · **Last re-measured against the live API:** 2026-09-05 (`GET /api/openapi.json` under a Bearer token from the `.env` test account: **226 paths / 294 operations**; the client builds 154) · **Branch:** `dev` (⚠️ `main` is behind — catch it up before a release cut) · **Bundle:** `com.interlinedlist.macos` · **Team:** `BJA9558E4B`
- **Structure:** [§1 Immediate work (do now)](#1-immediate-work--unblocked-do-now) — including [§1c verb defects](#1c-live-verb-defects--fix-first) and [§1d the 2026-09-05 parity batch](#1d-new-feature-areas-2026-09-05-re-measure) → [§2 Blocked work (backend / spike-first)](#2-blocked-work--backend-gated-or-spike-first) → [§3 Final work (release & App Store)](#3-final-work--release--app-store)
- **Test baseline (all green, re-run 2026-09-05):** InterlinedKit **314** · InterlinedDomain **619** · InterlinedPersistence **135** · App target **622** (`** TEST SUCCEEDED **`). *(Kit/Domain dipped from 317/628 because PR #19 removed the List Folders endpoint + service tests along with the feature.)* Packages verified this session under plain `swift test`; the App target ran green under `xcodebuild test … CODE_SIGNING_ALLOWED=NO` (the signing override is still required on this machine). *(Prior 2026-08-16 baseline was Kit 286 / Domain 590 / App 566; growth is from G4 GitHub issues, sharing collaborators/invites/visibility, and timeline cross-post links.)*
- **Distribution model:** notarized **`.pkg`** (+ `.dmg`) is the **current** ship path (closed-source private repo, no `LICENSE`). Mac App Store is a **later** path on a separate branch. Billing is handled by the web app — the native app has **no** in-app-purchase surface; it only *reads* `customerStatus` to gate subscriber features.

---

## Status snapshot — already shipped (do NOT re-implement)

The July web-parity batch (`feature/web-parity-batch-2026-07`) merged into `dev`. Shipped with services + App UI + tests:

- **Messaging & safety:** Direct Messages (folders/threads/read-state/unread badge/image attachments) · Moderation (block/mute/report + Settings ▸ Blocked & Muted).
- **Collaboration:** Share Links & resolve/claim for lists + documents (`interlinedlist://…/shared/{token}`) · **per-person document collaborators, email invites (lists + documents), and a make-public visibility toggle** (PR #13, merged 2026-09-02) · Search (messages/lists/documents). *(List Folders was shipped then removed 2026-09-04 on `refactor/lists-remove-list-folders` — the feature was retired; owned-lists `parentID` parent/child nesting is unaffected and remains.)*
- **Reach & content:** X/Twitter cross-post (⚠️ field name unverified — see [§1](#g7-verify-x-twitter-cross-post-field-name)) · server document templates · rich public profiles (`GET /api/users/{username}`) · schema DSL `select`/`markdown` · cards + real-`Table` grid list views · Markdown export (lists) + CSV export.
- **Auth:** native OAuth identity linking (`POST /api/auth/{provider}/link` + `interlinedlist://oauth/callback` + `ASWebAuthenticationSession`) — directly unblocks GitHub/X linking.
- **Settings storage (2026-08-16):** server-synced account **Preferences** — the backend now accepts `POST /api/user/update` (previously 405). `UserSettings` domain model + mapper, `UserService.settings()`/`updateSettings()`, and a Settings ▸ **Preferences** pane (public-by-default, advanced post options, link previews, posts-per-page, private account) with change-gated Save. 9 tests. *Deferred:* `theme` and `viewingPreference` (valid value sets unconfirmed; PATCH omits them so they're never clobbered).
- **Infrastructure (beyond parity):** on-disk **SWR cache + launch prefetch** (Lists/Documents/Scheduled/Organizations paint-from-cache, revalidate in background) · the **Document Sync Agent** (`SyncAgent/` — a bundled `LSUIElement` menu-bar utility that mirrors documents to a local Markdown folder for Obsidian; built + unit/live-tested; remaining work is on-device ship validation in [§3](#3b-document-sync-agent--on-device-validation)) · friendly loading-error messages + rotating debug log · App target is now **sandboxed + hardened**.

Milestones **M0–M7** feature work is complete; post-milestone items NW-1…NW-6, S1/S3/S4, B8 are done.

**Merged since this doc was consolidated (2026-08-18 → 2026-09-02):**
- **G4 · GitHub issue integration** (PR #12, merged 2026-08-18) — Kit + Domain client + the full App UI (issue browser in GitHub-backed lists, "create issue from a message", close/reopen + label/assignee editing). Client-complete; only the issue **update** and **comment** routes stay backend-blocked (see [§1 · G4](#g4-github-issue-integration) / [§2 · P1-H2](#p1-h2-github-issue-update-comment-routes)). Also in PR #12: G7 verify, G14 tail, ERD schema-entity view, timeline New Message button, G11a LinkedIn target, force-directed connections layout, Preferences pane, per-item Markdown export.
- **Sharing collaborators / invites / visibility** (PR #13, merged 2026-09-02) — extends the G3 sharing group: per-person document collaborators (search/add/set-role/remove), email invites for lists **and** documents, and a make-public visibility toggle. Full stack (Kit `SharingEndpoint`/`SharingDTO`, Domain `Sharing` models + `SharingService`, App `DocumentCollaborators*`/`Invites*`/`Visibility*` views + VMs) with Kit/Domain/App tests. Create paths are subscriber-gated.
- **Timeline cross-post destination links** (PR #14, merged 2026-09-02) — a message row links out to where it was cross-posted (Bluesky/Mastodon/X/LinkedIn external URLs) via the Domain `Message` cross-post projection + mappers.

**Where we are now (re-measured against the live API 2026-09-05):** the "§1 is exhausted" conclusion **no longer holds**. A fresh authenticated pull of `GET /api/openapi.json` reports **226 paths / 294 operations** — the ~150-endpoint figure this doc was built on is a year-stale baseline. The macOS client builds **154** of them. Stripping the parts a native client should never call (admin 26, cron 7, webhooks 2, analytics-ingest, `test-db`, `openapi.json`, `oauth/client-metadata`, Stripe 2 — billing stays in the web app by owner decision) leaves roughly **100 live operations the app does not implement**, including whole product areas that shipped on the web after the re-baseline: **AI writing/generation, "Create from…" (materialize), Applications settings-and-devices sync, notification preferences, session revocation, tags, and link-metadata previews.**

Worse, six calls the client ships today use a **verb the live server rejects** — message edit, preferences save, list-row edit, organization edit, document-folder rename, and follower removal are all broken against production right now ([§1c](#1c-live-verb-defects--fix-first)). Those are correctness bugs, not gaps.

So the levers are, in priority order: **[§1c](#1c-live-verb-defects--fix-first)** (verb defects — fix first, they break shipped features), **[§1d](#1d-new-feature-areas-2026-09-05-re-measure)** (the new unblocked parity batch), **§2** (still genuinely backend-gated — [P1-G](#p1-g-following-feed) re-verified still broken 2026-09-05), and **§3** (release engineering, unchanged and still the ship path).

*(The G1–G14 batch is indeed complete — the paragraph this replaced was accurate about the gaps known at the time, the G14 `ImagePrep` tail included. What changed is the size of the live surface it was measured against.)*

---

## 1. Immediate work — unblocked, do now

Everything here is client-side and buildable today (the backend already exists or none is needed). Ordered by value.

> **⚠️ Superseded 2026-09-05 by the live re-measure — see [§1c](#1c-live-verb-defects--fix-first) and [§1d](#1d-new-feature-areas-2026-09-05-re-measure).** The statement below is true of the gaps *known at the time*; the live API has since grown well past this doc's baseline.
>
> **Status 2026-09-05 — the G1–G14 batch is DONE.** Every item below is built and merged to `dev`, including the **G14** `ImagePrep` size-ceiling tail (verified in code 2026-09-05 — see G14). The one remaining open thread is **G4**'s issue **update**/**comment** routes, which are backend-blocked ([P1-H2](#p1-h2-github-issue-update-comment-routes)) — not a client gap. No client-only parity work remains; **§3 release is the critical path**.

### 1a. Parity features buildable now

<a id="g4-github-issue-integration"></a>
**G4 · GitHub issue integration** — ✅ **App UI shipped (PR #12, merged 2026-08-18).** The Kit + Domain client and the full App UI (issue browser in GitHub-backed lists, "create issue from a message", close/reopen + label/assignee editing) are built and merged. **Remaining:** the issue **update** and **comment** routes 404/405 live and are pointed at documented-but-unverified paths pending backend confirmation ([P1-H2](#p1-h2-github-issue-update-comment-routes)); success-response envelopes still need a linked test account to exercise. Original scope note below for context.
The `/api/github/*` routes are deployed (`GET /api/github/repos` → 400 "GitHub account not linked" — the route exists; 400 is just the unlinked state), and native OAuth linking already ships, so linking is no longer a blocker. Build the issue-write client: `GitHubEndpoint` (`repos`, `issues(repo:state:)`, `createIssue`, `updateIssue` PATCH labels/assignees, `comment`, `assignees`, `labels`, `nextIssueNumber`) → `GitHubService` (requires a linked identity; if unlinked, deep-link the existing native OAuth flow) → App ("Create issue from message" overflow action + issue browse/create/comment inside GitHub-backed lists + inline "Link GitHub" CTA). **Verify-first:** link the test account's GitHub identity once and observe the live request/response shapes before finalizing the decode paths (backend shape docs are requested in [§2 · P1-H](#p1-h-github-issue-shapes) but you can proceed by observation). **Size M.**

> **Verify pass — route surface DONE, success shapes still need a linked account (2026-08-17).** The success-body decode can't be exercised (test account still unlinked: `GET /api/github/repos` → 400 "not linked"; linking needs the interactive OAuth flow). BUT unlinked route-surface probing found the client's **issue paths were structurally wrong** — G4 would have 404'd on every issue op regardless of linking:
>
> | client op | client path (was) | live | correct route (verified) |
> |---|---|---|---|
> | list issues | `GET /repos/{repo}/issues` | **404** | `GET /api/github/issues?repo=…&state=…` ✅ **fixed** |
> | create issue | `POST /repos/{repo}/issues` | **404** | `POST /api/github/issues?repo=…` (400 "title is required"; `OPTIONS`→`GET,HEAD,OPTIONS,POST`) ✅ **fixed** |
> | update (close/label/assignee) | `PATCH /repos/{repo}/issues/{n}` | **404** | ❓ flat collection rejects `PATCH`/`PUT` (405); no single-issue route found — **unknown, see P1-H2** |
> | comment | `POST /repos/{repo}/issues/{n}/comments` | **404** | ❓ no comment route found — **unknown, see P1-H2** |
> | assignees / labels / next-issue-number | `GET /repos/{repo}/…` | 400 | ✅ client already correct (nested) |
>
> **Fixed in the client:** `GitHub.issues` + `GitHub.createIssue` now hit the flat `/api/github/issues?repo=…` route (endpoint tests updated). **Still blocked:** `updateIssue` (the close/reopen + label/assignee the ask centers on) and `comment` — their live routes could not be found by probing; left pointed at the documented-404 paths with ⚠️ notes rather than guessing. **To finish:** confirm those two routes via [§2 · P1-H2](#p1-h2-github-issue-update-comment-routes) (or link GitHub and watch the web app's network calls), then also confirm the success-response envelope (watch for the same `data`-wrap drift the G7 pass found on `POST /api/messages`).

<a id="g7-verify-x-twitter-cross-post-field-name"></a>
**G7 · Verify X/Twitter cross-post field name** — ✅ **VERIFIED live 2026-08-17.** The test account now **has** a linked X identity (`@interlinedlist`, `provider: twitter`, via `GET /api/user/identities`) — the earlier "no linked X identity" premise is obsolete. A real post with `crossPostToTwitter: true` published to X and came back as `crossPosts: [{ "platform": "twitter", "status": "ok", "externalUrl": "https://twitter.com/interlinedlist/status/…" }]`. **Conclusion:** the request field is `crossPostToTwitter` (not `crossPostToX`) and the stable per-platform value is `"twitter"` — no client change needed; the `MessageDTO.crossPostToTwitter` doc-comment is updated to record the confirmation. The InterlinedList-side test message was deleted afterward (the tweet itself is not un-sendable).

> **Drift caught during the G7 pass (now fixed / logged):**
> - **Create-response envelope drift — FIXED client-side.** Live `POST /api/messages` no longer returns a flat `MessageDTO`; it wraps the message under `data` and reports cross-post results in a sibling top-level `crossPosts` array (`{ message, data:{…}, crossPostResults, crossPosts }`). A bare `MessageDTO` decode of that body throws `keyNotFound("id")`, so a **successful publish surfaced to the user as a failure** and a re-try duplicated the post (and its cross-post). New `MessageWriteResponse` decoder tolerates both the wrapped and flat shapes and folds the top-level `crossPosts` into the message; `Messages.create`/`.update` now return it. Regression tests added.
> - **`PUT /api/messages/[id]` → HTTP 405 — backend ask, see [§2 · P2-I](#p2-i-message-edit-method).** Message **edit** is broken against the live API; the correct verb (likely `PATCH`) needs backend confirmation before a client change. Left as-is (client still sends `PUT`) pending that confirmation.
> - **`GET /api/user/identities` responded 200 under Bearer** even though the client declares it `auth: .session`. Read-only note; no change made (session remains the documented contract).

<a id="g11a-linkedin-posting-target"></a>
**G11a · LinkedIn posting target** — ✅ **Target-aware toggle shipped 2026-08-15.** `LinkedInService` is now wired into `AppEnvironment`; enabling the composer's LinkedIn cross-post toggle fetches `postingTargets()` and shows **which destination the post publishes to** ("Posting as …"), rolls the toggle back with a connect hint when the account has no LinkedIn target, and surfaces the org-scope-missing note — all mirroring the Bluesky/Mastodon readiness pattern and reusing the verified `crossPostToLinkedIn` request path. 6 composer tests. **Deferred (needs a verified wire shape):** a true multi-*target selector* and the `POST /api/linkedin/sync-pages` refresh both wait on a confirmed per-target request field; LinkedIn **org** pages are upstream-blocked (G11b).

**G14 · `/api/limits` composer validation** — ✅ **Message-length validation shipped 2026-08-15.** New Kit `Limits` endpoint + `LimitsDTO`; domain `ContentLimits` model + `ContentLimitsService` (fetch with `ContentLimits.default` fallback); wired into the composer as a live character counter + publish gate (over-limit disables Post, turns the counter/border red). 13 tests (4 Kit + 4 Domain + 5 App). **Tail also shipped — verified 2026-09-05.** The media *size* ceilings are server-driven end to end: `ImagePrep.Limits` + `prepare(_:limits:)` replace the hard-coded constants (which remain only as `Limits.default`), `ContentLimits.imagePrepLimits` projects the live values in, and both `MessagesService.uploadImage` (`MessagesService.swift:654`) and `DocumentsService.uploadImage` (`DocumentsService.swift:300`) pass them; `uploadVideo` (`MessagesService.swift:668`) uses the live `videoMaxBytes` with the static `maxVideoBytes` as fallback. `AppEnvironment` injects `ContentLimitsService` into both services. Covered by `ImagePrepTests` (custom-limits cases) and `MessagesServiceM6Tests` (live-limit override).

### 1b. Client-side follow-ups & polish (no backend)

- ~~**ERD list view**~~ — ✅ **Schema-entity view shipped 2026-08-17** (product call: schema-entity view chosen over the backend-blocked true-relationship ERD). Added a third `ViewMode.entity` to `ListRowsViewModel` with a unit-tested `entityFields` projection (field name, DSL type token, `select` option set folded into a `"select (a | b | c)"` description, and a required/optional badge from `SchemaField.nullable`); `ListRowsView` renders it as a single entity box (App-layer only, no Kit/Domain changes). 2 view-model tests. Prior findings still stand: (b) a list-to-list connection graph already ships as `ListConnectionsView` (interpretation closed); (a) a **true** FK-style relationship ERD stays backend-blocked on P2-G (`link(listSlug)` deferred).
- ~~**Visible "New Message" button on the timeline**~~ — ✅ **Shipped 2026-08-17.** `TimelineRootView` now shows a prominent "New Message" button in its toolbar (visible in every timeline state — list, empty, loading, error, following) that opens the same single-instance composer `Window` as ⌘N / File → New Message via `openWindow(id:)`. Previously the composer was only reachable by keyboard shortcut / menu.
- ~~**Per-document / per-thread "Export as Markdown" buttons**~~ — ✅ **Shipped 2026-08-15.** The document-editor toolbar ("Export as Markdown") and the message-thread toolbar now export via a shared `MarkdownExportRequest` + the existing `MarkdownFileDocument` save flow; `ExportViewModel` was de-duplicated onto the shared type. 10 tests.
- ~~**Public grid on read-only `ListDetailView`**~~ — ✅ **Shipped 2026-08-15.** The public list browser now has a Cards/Table segmented toggle above the rows and renders a real `Table` (one column per derived field, "Load More" footer), mirroring the owned `ListRowsView`; `ListDetailViewModel` gained a `viewMode` (default Cards). 4 tests; `StubListsService` public paths made programmable.
- ~~**S2 · Message store on-disk persistence**~~ — ✅ **Verified done 2026-08-15.** `AppEnvironment.makeMessageStore()` already returns the on-disk `SwiftDataMessageStore` (in-memory → `NullMessageStore` fallbacks), matching the lists/documents/orgs caches — the timeline paints from disk on launch and revalidates. The SWR-cache commit closed the swap; only a stale "TODO M4" doc-comment remained (now corrected). `InMemoryMessageStore` is test-only.
- ~~**M3.x · Force-directed connections-graph layout**~~ — ✅ **Shipped 2026-08-16.** New pure, deterministic `ForceDirectedLayout` engine (`InterlinedDomain`, Fruchterman–Reingold; seeded by node index, fixed iterations, epsilon-guarded — no `Date`/RNG); `ListConnectionsViewModel.layout(in:)` uses it, with dragged nodes pinned across relayouts. 12 domain + 3 view-model tests.

---

<a id="1c-live-verb-defects--fix-first"></a>
### 1c. Live-verb defects — fix first (found 2026-09-05)

Six shipping calls send an HTTP verb the live server does not accept, so the feature behind each one **fails against production today**. Each was confirmed twice: the live `openapi.json` lists only the other verb, and an authenticated `OPTIONS` returns an `Allow` header without the client's verb. No backend work is needed — these are one-line client fixes plus a regression test.

| # | Client call | Sends | Live `Allow` | Broken user-facing behavior |
| --- | --- | --- | --- | --- |
| V1 | `Messages.update` → `/api/messages/{id}` | `PUT` | `DELETE, GET, HEAD, OPTIONS, PATCH` | **Editing a message.** Closes [P2-I](#p2-i-message-edit-method) — the verb is `PATCH`, no backend ask needed. |
| V2 | `User.update` → `/api/user/update` | `POST` | `OPTIONS, PATCH` | **Saving Settings ▸ Preferences.** The pane shipped 2026-08-16 against a `POST` the server no longer accepts. |
| V3 | `Lists.updateRow` → `/api/lists/{id}/data/{rowId}` | `PATCH` | `DELETE, GET, HEAD, OPTIONS, PUT` | **Editing a list row** (the row inspector's save path). |
| V4 | `Organizations.update` → `/api/organizations/{id}` | `PATCH` | `DELETE, GET, HEAD, OPTIONS, PUT` | **Editing an organization.** |
| V5 | `Documents.updateFolder` → `/api/documents/folders/{id}` | `PATCH` | `DELETE, GET, HEAD, OPTIONS, PUT` | **Renaming / moving a document folder.** |
| V6 | `Follow.remove` → `/api/follow/{userId}/remove` | `POST` | `DELETE, OPTIONS` | **Removing a follower.** |

**V7 · GitHub issue update + comment routes — [P1-H2](#p1-h2-github-issue-update-comment-routes) is RESOLVED, and the client is pointed at the wrong paths.** The live spec and `OPTIONS` both confirm the **flat** routes exist: `PATCH /api/github/issues/{owner}/{repo}/{number}` (`Allow: OPTIONS, PATCH`) and `POST /api/github/issues/{owner}/{repo}/{number}/comments` (`Allow: OPTIONS, POST`) — exactly the shape the coverage matrix documented before the 2026-08-17 pass moved the client to nested `/api/github/repos/{repo}/issues/{n}` paths that 404. Point `GitHub.updateIssue` and `GitHub.comment` back at the flat routes and close/reopen, label/assignee editing, and commenting all start working. (`labels`, `assignees`, and `next-issue-number` are already correct — their nested `/api/github/repos/{owner}/{repo}/…` routes answer `GET`.)

> **Verify-before-fix, as always:** `OPTIONS` proves which verb is accepted, not which body shape or response envelope the route returns. Exercise each corrected call against the `.env` test account before tightening any decoder — the `POST /api/messages` envelope drift found during the G7 pass is exactly the failure mode to expect.

<a id="1d-new-feature-areas-2026-09-05-re-measure"></a>
### 1d. New feature areas — the 2026-09-05 re-measure

Product areas that exist on the live API and in the published help docs (`https://interlinedlist.com/help`) but have **no client implementation at all**. Ordered by user-visible value. Sizes are rough. Every one is client-side buildable: the backend already ships them.

<a id="g15-ai"></a>
**G15 · AI writing & generation — HIGH, the biggest single parity gap. Size L.**
Live and available to the test account: `GET /api/ai/status` returns `{"subscriber":true,"providers":["anthropic"],"defaultModels":{…},"quota":{"usedToday":0,"dailyLimit":50,"remaining":50}}`; the write pair is `POST /api/ai/suggest` (run a feature, return a validated **preview**) and `POST /api/ai/generate` (persist a confirmed artifact from that preview). Per `/help/ai` the surface is four features: **composer writing assistant** (rewrite, tighten, expand, fix grammar, convert-to-thread, suggest tags), **series planning** (a brief → a sequence of connected posts, or an article series), **AI list templates** (describe a structure → drafted schema + starter rows), and **AI documents** (from a topic, a list, an existing article, or a URL). Subscriber-gated, and the user brings their own OpenAI / Anthropic / Gemini key via the web Integrations page. The suggest→confirm→generate shape maps cleanly onto a preview sheet with a Confirm button. **The `feature` enum and both request/response bodies are unmodelled in the OpenAPI spec** (`{"feature": string}` is all it declares) — probe live or read the web app's network calls before building.

<a id="g16-materialize"></a>
**G16 · "Create from…" (materialize) — HIGH. Size M.**
`POST /api/materialize` creates a **List, a Document, or both** from a source object. Per `/help/create-from` the sources are one or many messages, one or many lists, one or many list rows, and a whole document or a highlighted markdown selection; the preview lets the user set title/description/visibility, rename columns and change column types for the list target, and choose numbered/bulleted styling for the doc target. On macOS this is a `＋ Create` menu on a row, a selection-bar action for multi-select, and a selection menu in the document editor. Request body is unmodelled in the spec (`{"source": string}`) — probe first.

<a id="g17-app-settings"></a>
**G17 · Applications: synced settings + device registry — HIGH for a native client specifically. Size M.**
`GET/PUT/DELETE /api/user/app-settings/{appKey}`, `GET /api/user/app-settings/{appKey}/bootstrap?deviceId=…`, `GET/POST /api/user/app-settings/{appKey}/devices`, `GET/PUT /api/user/app-settings/{appKey}/devices/{deviceId}/settings`, `PATCH/DELETE /api/user/app-settings/{appKey}/devices/{deviceId}`. Per `/help/app-settings` this is the platform's *own* mechanism for companion apps: **shared settings** follow the account to every machine, **per-machine settings** stay pinned to one computer, one machine is the "main workstation" whose config seeds a brand-new device on first sign-in, and devices can be renamed or deregistered. This is the sanctioned home for the macOS app's preferences **and** the Document Sync Agent's per-machine configuration, replacing purely local `UserDefaults` state. **✅ SHIPPED 2026-09-06** (PR #25 + #30). ⚠️ **The "register an `appKey`" instruction above was wrong — no registration mechanism exists.** A read-only live probe found the segment is a free-form namespace: `GET /api/user/app-settings/<invented-key>/devices` → `200 {"devices":[]}` for a key the server has never seen, and `OPTIONS` on the parent → `allow: DELETE, GET, HEAD, OPTIONS, PUT`. The client uses `interlinedlist-macos` (`AppEnvironment.appSettingsKey`); it must stay **stable**, since changing it orphans stored settings. **Also learned live:** 404 is the ordinary first-run state, not a failure — an app key with nothing stored 404s, and `bootstrap` returns `404 {"source":"none"}` for an unseen device; both now map to empty rather than throwing. **Still unverified:** the *populated* payload shapes, since nothing is stored yet — the DTOs stay tolerant.

<a id="g18-notification-preferences"></a>
**G18 · Notification preferences — MEDIUM. Size S.**
`GET /api/user/notification-preferences` returns a typed event catalogue — `{"events":[{"key":"dig","label":"Digs on your messages","description":"…","channels":{"push":true,"inApp":true}}, …]}` — and `PATCH` writes it. **✅ SHIPPED 2026-09-06** (PR #25) as Settings ▸ Notifications, and the shape is **live-verified**: 8 events, and their `channels` genuinely vary per event (`reply` offers only email; `follow` offers email+push but not inApp), so the pane renders only the channels the server sends — a fixed three-switch pane would show dead controls on six of the eight. Server-driven labels and descriptions mean the pane renders itself from the payload. Also the per-event `channels.push` flags are the switchboard [G9 push](#2b-spike-first-native-gaps) will need.

<a id="g19-sessions"></a>
**G19 · Active sessions & token revocation — MEDIUM. Size S. (Closes the client half of [P3-D](#p3-d-sessions-revocation).)**
`GET /api/user/sessions` is **Bearer-reachable** and returns `{"sessions":[{"id","deviceLabel","createdAt","lastUsedAt","isCurrent"}…]}`; `DELETE /api/user/sessions/{id}` revokes one. **✅ SHIPPED 2026-09-06** (PR #25) as Settings ▸ Security, shape **live-verified** (`{sessions:[{id, deviceLabel, createdAt, lastUsedAt, isCurrent}]}`). Revoking the *current* session signs this Mac out, so that row alone is gated behind a confirmation. It is the honest complement to a never-expiring sync token.

<a id="g20-tags"></a>
**G20 · Tags: trending + autocomplete — MEDIUM. Size S.**
`GET /api/tags/trending` (verified: `{"tags":[{"tag","count","lastUsedAt"}…]}`) and `GET /api/tags/autocomplete` (prefix match on public messages). **✅ SHIPPED 2026-09-06** (PR #25): a composer tag-completion popover and a trending strip on the timeline that reuses the existing tag filter. Both shapes **live-verified** — trending is `{tags:[{tag, count, lastUsedAt}]}` and autocomplete returns the wrapped `{tags:[…]}` form. Pairs naturally with G15's "suggest tags" assistant.

<a id="g21-link-metadata"></a>
**G21 · Link metadata / previews — MEDIUM. Size S–M.**
`GET /api/link-metadata?url=…`, plus `GET /api/messages/{id}/metadata` (read stored metadata, lightweight) and `POST /api/messages/{id}/metadata` (fetch and persist a message's link metadata). The app already **ships a "link previews" toggle** in Settings ▸ Preferences with nothing behind it, and [P3-F](#2c-backend-confirmation--polish-asks) documents the client rendering previews from a value set it guessed. Also `GET /api/images/proxy` for server-side image fetching.

<a id="g22-dm-completeness"></a>
**G22 · Direct-message completeness — MEDIUM. Size S.**
Three routes the DM feature shipped without: `GET /api/dm/conversations` (one row per conversation grouped by `pairKey`, newest first — verified live, `{"items":[],"nextCursor":null}` — this is the natural inbox list, versus today's folder-based `GET /api/dm`), `GET /api/dm/{id}` (single message), and `POST /api/dm/images/upload` (DM image attachments, which the DM composer advertises but cannot perform).

<a id="g23-lists-gaps"></a>
**G23 · Lists: shared-with-me, contributors, watcher add — MEDIUM. Size M.**
`GET /api/lists/watching` (verified live, returns real rows) is the **"shared with me" / watched-lists** surface the sidebar lacks. Also `GET /api/lists/{id}/contributors` (full ranked contributor list), `POST /api/lists/{id}/watchers` (add watchers — the client can only read and delete), `GET /api/lists/shared/{token}/data` (row data for a token-shared list, the read-only viewer's missing half), and the invite landing pair `GET`/`POST /api/lists/invite/{token}`.

<a id="g24-documents-gaps"></a>
**G24 · Documents: sidebar tree, public docs, invites, presence — MEDIUM. Size M.**
`GET /api/documents/tree` returns `{folders, rootDocuments}` in **one** call — today the sidebar assembles that from several. `GET /api/users/{username}/documents` is public documents by user (the profile page has no documents tab). `GET`/`POST /api/documents/invite/{token}` are the invite landing/claim pair matching the list ones. `POST /api/documents/folders/{id}/documents` creates a document directly in a folder. `POST`/`DELETE /api/documents/{id}/presence` is the live-cursor heartbeat — **defer**: it is a collaborative-editing feature with a polling cost, worth building only if multi-user editing is a goal.

<a id="g25-org-admin"></a>
**G25 · Organization admin + LinkedIn org pages — MEDIUM. Size M. (This is [G11b](#2d-upstream-blocked--deferred-confirm-demand-before-building), no longer upstream-blocked.)**
`PUT /api/organizations/{id}` and `DELETE /api/organizations/{id}` (the client can create and read but not rename or delete — and it sends `PATCH`, see [V4](#1c-live-verb-defects--fix-first)), plus the org LinkedIn set that was recorded as 404/not-deployed and now exists: `GET /api/organizations/{id}/linkedin/status`, `POST /api/organizations/{id}/linkedin/sync-pages`, `PUT /api/organizations/{id}/linkedin/assignments`, `DELETE /api/organizations/{id}/linkedin/credential`. Personal-scope `PUT /api/linkedin/posting-targets` and `POST /api/linkedin/sync-pages` also exist, which closes the "needs a verified per-target wire shape" note on [G11a](#g11a-linkedin-posting-target).

<a id="g26-identities"></a>
**G26 · Identity management: unlink + verify — LOW–MEDIUM. Size S.**
`DELETE /api/user/identities` (unlink a provider — Settings ▸ Linked Accounts can link but never unlink), `POST /api/user/identities/verify`, and `GET /api/auth/github/status` (the client has `bluesky`/`mastodon`/`linkedin`/`twitter` status but not GitHub's).

<a id="g27-small-gaps"></a>
**G27 · Small, self-contained gaps — LOW. Size XS each.**
`DELETE /api/notifications/{id}` (delete a single notification; the client can only mark read), `POST /api/messages/{id}/reply-counts`, `GET /api/user/engagement` (aggregate dig/push engagement on your own messages — **note:** returned 401 under Bearer in the 2026-09-05 probe, so it may be session-only; confirm before building), and `PUT /api/documents/{id}` (a full-replace variant beside the `PATCH` the client already uses).

<a id="g28-dashboard"></a>
**G28 · Dashboard / front-wall layouts + widgets — CONFIRM DEMAND before building. Size L.**
`GET`/`PUT /api/user/dashboard-layout`, `GET`/`PUT /api/user/front-wall-layout`, and the widget feeds `GET /api/widgets/{markets,news,transit,transit/stops,bike-share}` plus `GET /api/weather` and `GET /api/location`. `/help/getting-started` puts the Dashboard second in prominence on the web, so this is real product surface — but it is a large, web-layout-shaped feature, and a native app may want its own arrangement rather than mirroring the web's saved layout. **Owner decision needed before any of it is built.**

<a id="g29-blog"></a>
**G29 · Blog — CONFIRM DEMAND. Size M (read) / L (authoring).**
`/help/blog` documents a Blog feature; the public API surface is only subscribe/confirm/unsubscribe (`/api/blog/*`), while authoring lives behind admin-only routes (`/api/admin/blog*`). A native reader is plausible; native authoring is admin-gated and probably out of scope. **Owner decision needed.**

**Explicitly out of scope for the native client** (counted here so future re-measures stop re-flagging them): `/api/admin/**` (26 ops, admin console), `/api/cron/**` (7, scheduler), `/api/webhooks/**` (2, Stripe + Resend), `/api/stripe/**` (2 — billing is managed in the web app by owner decision, see [G8](#2d-upstream-blocked--deferred-confirm-demand-before-building)), `POST /api/analytics/ingest`, `GET /api/test-db`, `GET /api/openapi.json`, `GET /api/oauth/client-metadata`, and `/api/architecture-aggregates/**`.

---

## 2. Blocked work — backend-gated or spike-first

Cannot be finished from the client alone. Each item carries a paste-ready prompt for the InterlinedList backend Claude Code session (base URL `https://interlinedlist.com`). **The single high-impact backend blocker is P1-G (Following feed);** everything else is a spike, a confirmation, or low-priority polish.

### 2a. High-impact blocker

<a id="p1-g-following-feed"></a>
**P1-G · Following / home feed endpoint** — **HIGH. Re-verified STILL BROKEN 2026-09-05:** an authenticated `GET /api/messages?limit=50` and `GET /api/messages?limit=50&scope=following` return the identical 50 messages from the identical author set, so the parameter is still ignored a month on. This remains the one high-impact backend blocker. *(Original 2026-07-31 finding:* `GET /api/messages` ignores `feed`/`scope`/`following`/`filter` (every variant returns the same "all" feed) and `POST /api/user/update {viewingPreference}` → 405. The client's `TimelineScope.following` is fully UI-wired (All/Mine/Following picker) but `MessagesService.timeline` short-circuits `.following` to an empty "coming soon" page (`MessagesService.swift:364`).* ) One client branch flips to consume this the moment it exists.

> **PROMPT:** You are working on the InterlinedList API (interlinedlist.com). Add a followed-accounts timeline feed. Preferred: extend `GET /api/messages` with `?scope=following` (or add `GET /api/feed/following`), returning only messages authored by accounts the caller follows, using the **same paginated envelope** as `GET /api/messages` (same `limit`/`offset`/`hasMore` shape). Bearer auth. Document it. Note: as of 2026-07-31 the live server silently ignores `scope`/`feed`/`following`/`filter` on `GET /api/messages` and `POST /api/user/update {viewingPreference}` → 405, so this needs a real implementation, not just docs. The macOS client already has the UI wired and flips one branch to consume it.

### 2b. Spike-first native gaps

**G9 · Push notifications (APNs)** — routes confirmed in the 2026-09-05 live spec (`POST /api/push/register`, `DELETE /api/push/unregister` — the `unregister` verb question is settled: it is **DELETE**). Per-event push switches now exist too ([G18](#g18-notification-preferences)). **Spike S2 first:** does a sandboxed, notarized, non-App-Store `.pkg` support APNs, and what provisioning is required? Also confirm the `unregister` verb (POST → 405, likely DELETE). Deep-link routing wants the backend `routePath` field ([P2-C](#p2-c-notification-routepath)). Then: register the device token on launch/sign-in, unregister on sign-out; real pushes augment (don't replace) tray polling. **Size M.**

**G10 · Multi-account switching** — **Spike S4 first:** `/api/auth/accounts` returns **401 under Bearer, re-verified 2026-09-05** (session-cookie-only; `/api/auth/switch` and `/api/auth/remove-account` are the same family). Resolve the Bearer-vs-session constraint (drive a cookie session for these routes, or request a bearer variant upstream — see [P3-D](#p3-d-sessions-revocation)) before building the account switcher + per-account `KeychainCredentialStore` + cache reset on switch. **Size M.**

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
**P2-H · X/Twitter cross-post field name** — ✅ **RESOLVED by client-side live verification 2026-08-17 (see [§1 · G7](#g7-verify-x-twitter-cross-post-field-name)).** Field is `crossPostToTwitter`; result value is `"twitter"`. A backend doc update is still nice-to-have but no longer blocking.
> **PROMPT (optional doc-only):** Document `crossPostToTwitter: true` on `POST /api/messages` alongside `crossPostToBluesky` / `crossPostToLinkedIn`, and document the `crossPosts[]` result entry `{ platform: "twitter", status, externalUrl }`.

<a id="p2-i-message-edit-method"></a>
**P2-I · Message edit verb drift — ✅ RESOLVED 2026-09-05, no backend ask needed.** The live spec and `OPTIONS /api/messages/{id}` both give `Allow: DELETE, GET, HEAD, OPTIONS, PATCH` — the edit verb is **`PATCH`**. This is now a client fix, tracked as [V1](#1c-live-verb-defects--fix-first). *(Original 2026-08-17 finding:* The client edits a message via `PUT /api/messages/[id]` (`Messages.update`), but the live route returns **405 Method Not Allowed** with an empty body, so **editing a message is broken end-to-end**. `POST` (create) and `DELETE` work; `GET` returns a flat `MessageDTO`. The correct edit verb needs confirmation before the client changes (likely `PATCH`, mirroring `/api/documents/[id]`). Until then the composer's edit path fails against production.*)
> **PROMPT:** `PUT /api/messages/[id]` returns HTTP 405. Confirm the supported method for editing a message (we expect `PATCH /api/messages/[id]` with the same body shape as `POST /api/messages` — `content`, `publiclyVisible`, `tags`, cross-post flags). Document the verb, the accepted body fields, and the response envelope (the create response now wraps the message under `data` with a top-level `crossPosts` array — confirm edit matches). If `PUT` is intended to keep working, restore it.

<a id="p2-j-article-series-provider-error"></a>
**P2-J · `article_series` returns `502 provider_error` on every attempt** — **NEW, found 2026-09-05, re-confirmed 2026-09-06.** `POST /api/ai/suggest {"feature":"article_series"}` fails with `{"error":"The AI provider rejected the request.","code":"provider_error"}` on three separate attempts across two days, with different briefs, all over the ten-word minimum. The same account, key, and model succeed for `writing_assist`, `message_series`, `powered_template`, and `powered_document`, so it is not entitlement, quota, or input length — the failure is specific to this feature's own server-side path. The macOS client models the feature and maps the failure to a provider-blamed message rather than a user-blamed one, so it degrades honestly, but **Article Series cannot work for any client until this is fixed.**

> **PROMPT:** You are working on the InterlinedList API (interlinedlist.com). `POST /api/ai/suggest` with `{"feature":"article_series","input":"<a multi-sentence brief>"}` returns `502 {"error":"The AI provider rejected the request.","code":"provider_error"}` every time, for a subscriber with a working Anthropic key whose other AI features (`writing_assist`, `message_series`, `powered_template`, `powered_document`) all succeed on the same request path. Reproduced three times across 2026-09-05 and 2026-09-06 with different briefs. Please check the `article_series` prompt/schema construction and what the provider is actually rejecting — likely a malformed tool/response schema for that feature specifically — and confirm the artifact shape it should return (the other features return `{artifact:{kind,…}}`).

**P3-A · Document version / ETag** for sync conflict detection.
> **PROMPT:** Add `version: int` to the document object on all read/sync endpoints. Accept `If-Match: <version>` on `PATCH /api/documents/[id]`; when present and stale, return `409 { "error": "version_conflict", "currentVersion": 42, "serverDocument": {…} }`. When absent, keep server-wins (no breaking change). Increment `version` on every successful `PATCH`.

**P3-B · `folderId` on sync-response documents.**
> **PROMPT:** Confirm `GET`/`POST /api/documents/sync` include `folderId` on every document entry — including conflict-resolution preserved-copies and deleted documents (their pre-deletion `folderId`). Add it if missing; document the field name. Confirm the `folderId` field name is consistent between `/api/documents/tree` and `/sync`.

**P3-C · GitHub-backed list refresh metadata + `githubSource` on create.** Client models the projection (`GitHubListSource`); rows carry `source`/`githubRepo` live; refresh fields + create-time `githubSource` unconfirmed. Coordinate with [P1-H](#p1-h-github-issue-shapes).
> **PROMPT:** Add to List objects with `githubSource`: `{ "lastRefreshedAt": "iso-8601 or null", "refreshStatus": "idle|pending|failed", "refreshError": "string or null" }`. Also accept `githubSource` on `POST /api/lists`: `{ "owner", "repo", "path", "ref" }`; if provided, trigger initial refresh and return `refreshStatus: "pending"`.

<a id="p3-d-sessions-revocation"></a>
**P3-D · Token revocation + `GET /api/user/sessions`** — ✅ **client half unblocked 2026-09-05.** `GET /api/user/sessions` **is** Bearer-reachable and returns `{id, deviceLabel, createdAt, lastUsedAt, isCurrent}` rows; `DELETE /api/user/sessions/{id}` revokes. Build it as [G19](#g19-sessions). The remaining ask is only the accounts/switch family below. Relates to [G10](#2b-spike-first-native-gaps) (accounts are session-cookie-only, 401 under Bearer); a Bearer-reachable sessions surface helps both.
> **PROMPT:** Add optional `deviceLabel` to `POST /api/auth/sync-token`. Implement `GET /api/user/sessions` → `{ sessions: [{ id, deviceLabel, createdAt, lastUsedAt, isCurrent }] }` and `DELETE /api/user/sessions/[id]` → 204 (token immediately invalid; 400 `{"error":"cannot_revoke_current_session"}` on self-revoke).

**P3-E · `RateLimit-*` headers universally.** Currently only on `POST /api/messages` and `POST /api/documents/sync`; client already nil-guards absent headers.
> **PROMPT:** Add `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset` to every authenticated response, and `Retry-After` on 429s (RFC 6585 + draft IETF RateLimit spec).

**P3-F · Link-preview `fetchStatus` value docs.** Client renders previews, gating on a forward-compatible "ready-ish" value set + title/image presence.
> **PROMPT:** Document the closed value set for `fetchStatus` on message `linkMetadata.links[]` — which value means "preview ready" vs "still fetching" vs "failed" — so the client can gate rendering on the authoritative token(s).

**P3-G · List "save to my lists" clone-with-rows.** `ListDetailViewModel.saveToMyLists` copies title/description/schema only, **no rows** (documented degradation; no clone endpoint exists).
> **PROMPT:** Add `POST /api/lists/[id]/clone` (or a rows-copy option on save) that duplicates a public list's rows into a new owned list, so "save to my lists" carries the data, not just the schema.

**P3-H · Message edit verb reconciliation** — ⛔ **superseded / the premise was wrong.** "Both work live" is no longer true (and may never have been): `PUT` is rejected outright. Folded into [P2-I](#p2-i-message-edit-method) / [V1](#1c-live-verb-defects--fix-first).
> **PROMPT:** The API reference documents message edit as `PATCH /api/messages/[id]`, but the client sends `PUT` and it works. Confirm the canonical verb and reconcile the reference with live behavior. While you're here, confirm the canonical verb for `/api/messages/{id}/replies` (OpenAPI shows `POST`; the client uses `GET`).

<a id="p1-h-github-issue-shapes"></a>
**P1-H · GitHub issue create/comment + labels/assignees shapes** *(docs; unblocks [§1 · G4](#g4-github-issue-integration) end-to-end).* **Partially unblocked 2026-09-05: the test account is now GitHub-linked** — `GET /api/github/repos` returns **200** instead of the old 400 "not linked", and `GET /api/github/orgs` (a route the client does not build) also answers 200. But the repo list comes back **empty**, so issue request/response envelopes still cannot be exercised end-to-end; a repo has to be configured on that account first. Routes are deployed; shapes remain undocumented. *(2026-08-17: `create` route + `title`-required confirmed via unlinked probe; `next-issue-number` confirmed to exist.)*
> **PROMPT:** The GitHub issue routes are deployed but undocumented for third-party clients. Define and document, with concrete request/response JSON: (1) issue **labels** and **assignees** as fields on GitHub-sourced list rows; (2) the endpoint to **create a GitHub issue** from a synced list; (3) the endpoint to **comment on an issue**; (4) `next-issue-number` if it exists. State the linked-identity precondition and the exact 400 error body when unlinked. Coordinate with P3-C.

<a id="p1-h2-github-issue-update-comment-routes"></a>
**P1-H2 · GitHub issue UPDATE + COMMENT route location** — ✅ **RESOLVED 2026-09-05 by the live spec; no backend ask needed.** The routes are the **flat** ones the coverage matrix originally documented: `PATCH /api/github/issues/{owner}/{repo}/{number}` (`OPTIONS` → `Allow: OPTIONS, PATCH`) and `POST /api/github/issues/{owner}/{repo}/{number}/comments` (`Allow: OPTIONS, POST`). The 2026-08-17 probe searched nested and single-segment candidates but not the three-segment flat form. Client fix tracked as [V7](#1c-live-verb-defects--fix-first). *(Original 2026-08-17 finding:* Unlinked route-surface probing established the issue **list/create** routes are flat (`GET`/`POST /api/github/issues?repo={owner/repo}`; `OPTIONS`→`Allow: GET, HEAD, OPTIONS, POST`) and the client is now fixed to use them. But the **update** and **comment** routes could not be found: `PATCH`/`PUT /api/github/issues` → 405; every nested/flat single-issue candidate (`/api/github/repos/{repo}/issues/{n}`, `/api/github/issues/{n}`, `/api/github/issues/{n}/comments`, `/api/github/issues/comments`, `/api/github/comments`) → 404.*)
> **PROMPT (ready-to-paste):**
> You are working on the InterlinedList API backend (base URL `https://interlinedlist.com`). The macOS client integrates the GitHub issue routes under `/api/github/*`, but **two** operations point at routes that return 404/405 live, so issue **editing** and **commenting** are broken end-to-end. I mapped the route surface by probing with a Bearer token for an account whose GitHub identity is **not** linked — so every route that *exists* returns `400 {"error":"GitHub account not linked"}`, and every route that is *missing* returns the Next.js HTML 404. Please locate/confirm the two missing routes and document them.
>
> **Already verified — do not change, just don't regress:**
> - List issues: `GET /api/github/issues?repo={owner}/{repo}[&state=open|closed|all]` → 400 not-linked (exists). `OPTIONS` on it → `Allow: GET, HEAD, OPTIONS, POST`.
> - Create issue: `POST /api/github/issues?repo={owner}/{repo}` → `400 {"error":"title is required"}` (exists; `title` required in the JSON body; optional `body`, `labels: string[]`, `assignees: string[]`).
> - `GET /api/github/repos/{owner}/{repo}/assignees`, `…/labels`, `…/next-issue-number` → all 400 not-linked (exist; nested form).
>
> **Gap 1 — edit an existing issue (close/reopen, labels, assignees, title, body).** The client calls `PATCH /api/github/repos/{owner}/{repo}/issues/{number}` → **404**. The flat collection rejects the verb: `PATCH` / `PUT /api/github/issues?repo=…&number=…` → **405** (its `Allow` excludes PATCH/PUT). These also 404: `/api/github/issues/{number}`, `/api/github/repos/{owner}/{repo}/issues/{number}`. **Document the exact METHOD + PATH for editing an issue, and where the issue `number` goes (path segment / query param / body field).** Accepted body fields expected: `state` (`"open"`|`"closed"`), `labels: string[]`, `assignees: string[]`, `title`, `body` (partial updates — only the sent fields change). Include the success-response JSON.
>
> **Gap 2 — comment on an issue.** The client calls `POST /api/github/repos/{owner}/{repo}/issues/{number}/comments` → **404**. These also 404: `/api/github/issues/{number}/comments`, `/api/github/issues/comments`, `/api/github/comments`. **Document the METHOD + PATH + body** (expected `{"body":"…"}`) and the success-response JSON.
>
> **For every issue response (create / update / comment):** state whether the object is returned **bare** or **wrapped** — e.g. `{"issue":{…}}`, `{"data":{…}}`, `{"comment":{…}}`. (Context: `POST /api/messages` recently began wrapping its result under `data` with side-data at the top level, which broke the client's flat decode — flag it here if GitHub issues do the same.)
>
> **Deliverable:** for each of the 4 issue ops (list, create, update, comment): a `METHOD PATH` line, the query/body schema, one example request + response JSON, the Bearer-auth + linked-identity precondition, and the exact unlinked-400 body.

### 2d. Upstream-blocked / deferred (confirm demand before building)

- ~~**G11b · LinkedIn org posting pages** — upstream-blocked on this tenant.~~ — ✅ **DEPLOYED as of the 2026-09-05 live spec; moved to [§1d · G25](#g25-org-admin).** `GET /api/organizations/{id}/linkedin/status`, `POST /api/organizations/{id}/linkedin/sync-pages`, `PUT /api/organizations/{id}/linkedin/assignments`, and `DELETE /api/organizations/{id}/linkedin/credential` all exist now, as do the personal-scope `PUT /api/linkedin/posting-targets` and `POST /api/linkedin/sync-pages`. Re-confirm `orgScopesEnabled` on the tenant before building.
- **G13 · Document presence / live cursors** — routes confirmed live 2026-09-05 (`POST`/`DELETE /api/documents/{id}/presence`, a combined heartbeat+poll), so it is no longer *blocked* — just still the highest-complexity, lowest-urgency item. Tracked with the rest of the document gaps in [§1d · G24](#g24-documents-gaps). Confirm demand first.

---

## 3. Final work — release & App Store

Ship gating is orthogonal to parity and can proceed in parallel with §1/§2. Detailed command references live in **`App-Dmg-Pkg-Deployment.md`** (retained).

### 3a. Notarized PKG/DMG release — the current ship path

One-time signing setup on the build machine, then the release run. Complete in order.

> **Pre-flight audit — 2026-09-05.** The pipeline was reviewed end-to-end *before* the first credentialed run, since every failure mode here only surfaces after a long archive + notarization cycle. Verified sound: all 8 `scripts/*.sh` parse (`bash -n`), `ExportOptions.plist` is `developer-id` + automatic signing, the sync-agent embed paths and both entitlements files exist, the Sparkle code path is fully wired (`SparkleController` + `UpdatesMenuCommands`, `SUFeedURL` set), and the appcast's `minimumSystemVersion` **15.0** matches `MACOSX_DEPLOYMENT_TARGET`.
>
> **One blocking bug found and fixed:** `notarize-and-package.sh` derived the release version by reading `CFBundleShortVersionString` straight out of `App/Resources/Info.plist` — but that file stores the *unexpanded* build variable `$(MARKETING_VERSION)`, so PlistBuddy returned the literal string. Every artifact would have been named `InterlinedList-$(MARKETING_VERSION).pkg` and `pkgbuild --version` would have received that same garbage. It now resolves `MARKETING_VERSION` via `xcodebuild -showBuildSettings` and hard-fails with an actionable message if the value is empty or still contains `$(`. Verified: default → `0.1.0`, explicit `APP_VERSION` honoured, guard exits 1.
>
> **Two decisions still open for the owner (not code bugs):**
> - **Version number is inconsistent across three places** — `MARKETING_VERSION` is **`0.1.0`**, `releases/appcast.xml` advertises **`0.0.1`** ("Version 0.0.1 Alpha", enclosure `InterlinedList-0.0.1-alpha.pkg`), and the tag step below says **`v1.0.0`**. Pick one before cutting the release; the appcast enclosure filename must match what the script actually produces or Sparkle will 404.
> - **Appcast URL** — `Info.plist`'s `SUFeedURL` points at `https://interlinedlist.com/appcast.xml` (matching the publish step below), but the comment block inside `releases/appcast.xml` documents the feed as living at `…/downloads/apple/appcast.xml`. Harmless today; reconcile so the served path and the polled path can't drift apart.

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

> **Docs reconciliation 2026-09-05.** `docs/api-coverage.md` was walked row-by-row against the shipped code after its 2026-07-31 re-baseline rows were found never to have been rescored — **56 of 83 scoreable new rows were already shipped but still marked ☐/☐**. That pass also corrected eight endpoint paths the matrix had transcribed from OpenAPI rather than from the live-verified client (six Moderation, two GitHub), added six shipped `/invites` endpoints the matrix omitted entirely, rescored the removed G6 List Folders rows as non-targets, and recomputed the totals: the matrix is **187 rows**, not the "151 (~150)" previously carried here and in `docs/api-coverage.md`. **Any note in this file or elsewhere citing a "~151-endpoint API surface" is stale by that amount.** Details in footnote 14 of `docs/api-coverage.md`.



This file consolidates and replaces the following, now removed (recoverable via git history):

- `feature-gaps.md` — parity gap snapshot (2026-07-18 → refreshed 2026-08-15).
- `the-gaps.md` — the master parity gap list + wave plan + live-probe evidence (2026-07-31).
- `feature-blockages.md` — the backend-blocker index (2026-08-15).
- `blocker-prompts.md` — the paste-ready backend `P#` prompts (preserved in [§2](#2-blocked-work--backend-gated-or-spike-first)).
- `synch-plan.md` — the Document Sync Agent plan (built + tested; remaining validation in [§3b](#3b-document-sync-agent--on-device-validation); full architecture in `SyncAgent/` + git history).
- `v1-release-checklist.md` — the release/App Store checklist (folded into [§3](#3-final-work--release--app-store)).

Retained references: `App-Dmg-Pkg-Deployment.md` (deployment command detail), `README.md`, `docs/`.

## Re-measure log

- **2026-09-05 — live re-measure + parity sweep.** Authenticated against `https://interlinedlist.com` with the `.env` contract-test account (`POST /api/auth/sync-token` → Bearer), pulled `GET /api/openapi.json` (**226 paths / 294 operations**, OpenAPI 3.1, `InterlinedList API 0.1.0`) and diffed it against the 154 request builders in `Packages/InterlinedKit/Sources/InterlinedKit/Endpoints/*.swift`. Cross-read the published help docs at `/help` (18 topics) for the user-facing feature list. **Found:** (1) six shipping calls send a verb the server rejects — [§1c](#1c-live-verb-defects--fix-first), each confirmed by both the spec and an authenticated `OPTIONS` `Allow` header; (2) ~100 unimplemented live operations after excluding admin/cron/webhooks/Stripe/analytics, including whole new product areas — [§1d](#1d-new-feature-areas-2026-09-05-re-measure) G15–G29; (3) [P1-H2](#p1-h2-github-issue-update-comment-routes) and [P2-I](#p2-i-message-edit-method) are **resolved** — both were client-side path/verb errors, not backend gaps; (4) [P1-G](#p1-g-following-feed) re-verified **still broken**, and [G10](#2b-spike-first-native-gaps)'s `/api/auth/accounts` re-verified **still 401 under Bearer**; (5) the test account is now **GitHub-linked** (`/api/github/repos` → 200) but its repo list is empty, so G4 issue envelopes still cannot be exercised. All probes were read-only (`GET`/`OPTIONS`); no writes were made.

