# The Gaps — Feature-Parity Backlog & Plan (macOS native ↔ interlinedlist.com)

**This is the working document** for what to build next to reach parity with the live web app. It consolidates and supersedes the parity content previously split across `feature-gaps.md` (2026-07-18) and `docs/api-coverage.md` (verified 2026-06-11). Those two files remain as historical/detailed references — `api-coverage.md` is still the place for the per-endpoint ☑/◐ test matrix once it is re-baselined (see §8) — but **this file is the source of truth for the gap list and the plan.**

- **Reviewed:** 2026-07-31 · **Branch:** `feature/web-parity-batch-2026-07`
- **Basis (should-have):** live [`GET /api/openapi.json`](https://interlinedlist.com/api/openapi.json) (~150 endpoints) + `/help/api/*` section docs.
- **Basis (has):** grep + `Explore` over `Packages/` and `App/` on this branch.
- **Basis (live truth):** **logged into the production API** with the `.env` test account `messenger@interlinedlist.com` (`customerStatus: "subscriber"`, email-verified) via `POST /api/auth/sync-token` and probed endpoints read-only. Findings are in §2 and the appendix.

## Contents
- §1 — **The gap list** (prioritized, what to build)
- §2 — Live verification evidence (2026-07-31)
- §3 — Already at parity (do **not** re-implement)
- §4 — Architecture & conventions (the build seam)
- §5 — The plan, wave by wave (per-gap specs)
- §6 — API-drift / migration pass (corrected against live)
- §7 — Ship gating (M7) — release, not parity
- §8 — Coverage tracking (re-baseline `api-coverage.md`)
- §9 — Sequencing & rationale
- §10 — Open questions / spikes (resolved vs. remaining)
- Appendix — raw live probe log

---

## 1. The gap list

The prior docs declared "near-full parity, 98/98 endpoints." That was true **for the API as of 2026-06-11.** The live API has since grown to ~150 endpoints across whole new feature areas the app has never implemented. Real coverage today is **~98 of ~150.**

Legend — **Status:** ❌ absent · ◑ partial · **Tier:** free / **Sub** (subscriber-gated server-side) · **Size:** S / M / L · **Backend:** ✅ live & verified this session · ⚠️ live but constrained · ❔ unverified.

| # | Gap | Status | Tier | Priority | Size | Backend | Notes from live probe (§2) |
|---|---|---|---|---|---|---|---|
| **G1** | **Direct Messages** — 1:1 DMs (mutual followers), inbox/sent/deleted folders, threads, read state, unread badge, ≤8 image attachments, trash/restore | ❌ | free | **P0** | L | ✅ | `/api/dm` 200; `/api/dm/recipients` returns eligible users; `/api/dm/unread-count` 200. Actively promoted by the product. |
| **G2** | **Moderation** — block/unblock, mute/unmute, report user, report message | ❌ | free | **P0** | M | ✅ | `/api/user/blocks` & `/api/user/mutes` 200 (paginated). |
| **G3** | **Share Links & Collaborators** — tokenized viewer/editor/admin links + per-person grants for **lists & documents**, claim/revoke, read-only shared data, "shared-with-me" | ❌ | **Sub** (create) | **P1** | L | ✅ | `/api/lists/{id}/share-links`, `/api/documents/{id}/share-links`, `…/collaborators` all 200; **`/api/lists/watching` returns real "shared-with-me" data.** |
| **G4** | **GitHub issue integration** — list repos, list/create/edit issues, comment, labels, assignees, next-issue-number, "create issue from message/list" | ❌ | Sub | **P1** | M | ✅ | `/api/github/repos` → 400 "GitHub account not linked" — endpoint live, needs OAuth link (already have native linking, G-resolved). |
| **G5** | **Search** — messages, lists, documents (server-side) | ❌ | free | **P1** | M | ✅ | `GET /api/{lists,documents}/search` 200; **messages search is `GET /api/messages/search?q=` (POST → 405).** |
| **G6** | **List Folders** — hierarchical folders for lists (distinct from doc folders), attach/detach, cycle-safe move | ❌ | **Sub** (create) | **P1** | M | ✅ | `/api/folders` 200 `{folders:[]}`; **lists already carry a `folderId` field** → clean hook. |
| **G7** | **X / Twitter cross-posting** — OAuth link + per-message target + readiness, extending the existing Mastodon/Bluesky/LinkedIn composer | ❌ | Sub | **P2** | S | ✅ | `/api/auth/twitter/status` → `{configured:true, redirectUri:…/twitter/callback}`. |
| **G8** | **In-app billing** — subscribe/manage via Stripe checkout + customer portal; show plan & quotas | ◑ | — | **P2** | M | ❔ | `stripeCustomerId` + `EntitlementsService` exist; **no purchase UI.** `/api/limits` live (see §2 for exact quota shape). Stripe endpoints not probed (avoided live writes). |
| **G9** | **Push notifications (APNs)** — register/unregister device token for native pushes (replaces tray polling) | ❌ | free | **P2** | M | ✅ | `POST /api/push/register` → 400 "token is required" (route live). `unregister` is not POST (405) — likely DELETE, confirm. |
| **G10** | **Multi-account switching** — list accounts, switch active, add/remove | ❌ | free | **P3** | M | ⚠️ | **`/api/auth/accounts` → 401 with Bearer — session-cookie-only.** Native bearer clients can't switch server-side without a session or a bearer variant. Spike first. |
| **G11a** | **LinkedIn personal posting targets** — choose target(s) in composer | ❌ | Sub | **P3** | S | ✅ | `/api/linkedin/{targets,posting-targets}` 200 with a real personal target. |
| **G11b** | **LinkedIn org pages** — org-scoped posting / `orgs/{id}/linkedin-page` | ❌ | Sub | **P4** | M | ⚠️ | `orgScopesEnabled:false`; `…/linkedin-page` → 404. Not deployed for this tenant — treat as upstream-blocked. |
| **G12** | **Server-side document templates** — `templates`, `from-template`, `tree` (app has *client-side* templates only) | ◑ | Sub | **P3** | S | ✅ | `/api/documents/templates` returns real seeded templates; `/api/documents/tree` returns one-call sidebar payload. |
| **G13** | **Document presence / live cursors** — real-time co-editing heartbeat | ❌ | Sub | **P4** | M | ❔ | Not probed. Highest complexity, lowest parity urgency — confirm demand before building. |
| **G14** | **Utility surfaces** — `/api/limits` quota card, weather/geolocation/image-proxy helpers | ❌ | free | **P4** | S | ✅ | Quota card folds into G8. |

### Still-open items carried forward from the old `feature-gaps.md`
- **Following feed** (old NB-1) — `TimelineScope.following` is UI-wired but returned empty; a `scope=following` feed endpoint was pending. **Re-verify against live** (`GET /api/messages` scope params) — may now be closable. **P1.**
- **Per-document / per-thread "Export as Markdown"** buttons — the `MarkdownExporter` engine already supports them; only the toolbar/menu affordances are missing. **P3, S.**
- **ERD list view** — the third documented list view mode (cards ✅, grid ✅, ERD ❌). Confirm whether "ERD" means the schema-field graph or the existing list-to-list connection graph before building. **P3.**
- **Public grid on read-only `ListDetailView`** — owned lists render a real `Table`; the public browse view still shows cards only. **P4, S.**

---

## 1b. Implementation progress (2026-07-31)

Build has started, backend-first (each gap's layers: Kit → Domain → Persistence → App).

| Gap | Kit + DTOs | Domain + tests | Persistence | App UI | Notes |
|---|---|---|---|---|---|
| **G5 Search** | ✅ | ✅ 17 tests | n/a | ⏳ agent | `Search` endpoint + `SearchService`; reuses `Message`/`ListSummary`/`Document` mappers |
| **G2 Moderation** | ✅ | ✅ 19 tests | n/a | ⏳ agent | `Moderation` endpoint + `ModerationService` (block/mute/report/isBlocking); fire-and-forget via `sendVoid` |
| **G6 List Folders** | ✅ | ✅ 17 tests | ⏳ | ✅ agent | `ListFolders` endpoint + `ListFoldersService` (subscriber gate + cycle-safe tree builder); sidebar folder tree wired |
| **G1 Direct Messages** | ✅ | ✅ 20 tests | ⏭ deferred | ✅ agent | Wire shape captured via one authorized recon DM (trashed). Full UI: folder/conversation/thread panes, `threadUpdates` polling, composer + recipient picker, profile "Message" action, `UnreadBadgeAggregator` (DM + notifications sum). Persistence needs a domain-side store seam (follow-up). |
| **G3 Share Links** | ✅ | ✅ 18 tests | n/a | ✅ agent | Share Links panel (create/list/revoke + role picker + subscriber upsell) on Lists + Documents toolbars; `ResolveShareView` landing via `ShareURLParser` (`interlinedlist://` + pasted URLs) with claim. Collaborator per-person grants = follow-up. |
| **D2 Public profile** | ⏳ | — | — | — | Shape verified live (`{id,username,displayName,avatar,headerImage,bio,joinedAt,isPrivate,follower/following/publicMessage/publicListCount}`); ready to add `Users.profile` + replace decision-0002 fallback. |
| G4, G7–G14 | — | — | — | — | not started |

**Test delta (all green):** InterlinedKit 224 → **250** (+26); InterlinedDomain 475 → **522** (+47); App target 379 → **452** (+73: Search/Moderation/ListFolders/DirectMessages UI). **+146 new passing tests, 0 regressions.** (`swift test` for the packages; `xcodebuild test` with `CODE_SIGNING_ALLOWED=NO` for the App target.)

**Follow-ups noted during the build:** (1) G1 SwiftData cache needs a store port added to `DirectMessagesService` first; (2) confirm `threadUpdates` `since`-token semantics (currently newest message id); (3) project-level test-target code-signing so a plain `xcodebuild test` passes.

**Wire-shape verification note (G1):** the DM object shape was confirmed live on 2026-07-31 by sending one clearly-labeled recon DM from the test account to the owner's account and reading it back, then trashing it — `{ id, pairKey, senderId, recipientId, body, imageUrls[], createdAt, readAt?, sender/recipient:UserSummary, preview }`; `POST /api/dm` → `{message:…}`; thread → `{items, olderCursor, isMutual, isBlocked, otherUser}`.

**Verified-shape build order rationale:** features are being built in order of wire-shape certainty. Search reuses existing DTOs (zero risk); Moderation/List-Folders envelopes were verified live. G1 DMs and G3 Sharing are deferred until their object shapes can be confirmed against live data, to avoid shipping an unverified decode path.

---

## 2. Live verification evidence (2026-07-31)

Logged in as `messenger` (subscriber) and probed read-only. This is why the gap list above is trustworthy and corrects two mistakes in the first draft.

**Confirmed live & Bearer-reachable (feature backends exist):** `/api/dm*`, `/api/user/blocks`, `/api/user/mutes`, `/api/lists/{id}/share-links`, `/api/documents/{id}/share-links`, `/api/documents/{id}/collaborators`, `/api/lists/watching`, `/api/folders`, `/api/lists/search`, `/api/documents/search`, `/api/messages/search` (GET), `/api/documents/templates`, `/api/documents/tree`, `/api/linkedin/targets`, `/api/linkedin/posting-targets`, `/api/github/repos` (needs link), `/api/push/register`, `/api/users/{username}` (public profile), `/api/limits`.

**`/api/limits` exact shape** (drives G8/G14 and composer validation):
```json
{ "media": { "image": { "maxBytes": 1468006, "maxPixels": 1200,
                         "acceptedFormats": ["jpeg","png","gif","webp"] },
              "video": { "maxBytes": 3145728, "acceptedFormats": ["mp4","mov"] } },
  "message": { "maxContentLength": 5000 } }
```

**Corrections to the earlier draft (verified against live):**
| Claim in first draft | Live reality | Consequence |
|---|---|---|
| "Orgs drifted to `/api/orgs`" | `/api/orgs` → **404 HTML shell**; `/api/organizations` → **200** | App's current path is **correct**. Dropped from drift list. |
| "User endpoints drifted to `/api/users/current`" | `/api/users/current` → **404 `user_not_found`** (parsed as username) | App's `/api/user` is **correct**. Dropped from drift list. |
| "`GET /api/users/{username}` now exists" | `/api/users/messenger` → **200 real profile** | ✅ Valid → adopt it (D2), replace the decision-0002 fallback. |
| Multi-account is a straightforward gap | `/api/auth/accounts` → **401 with Bearer** | Session-only → G10 needs a spike, not just a builder. |
| LinkedIn org pages are buildable | `orgScopesEnabled:false`, `…/linkedin-page` 404 | Org pages (G11b) are upstream-blocked; personal targets (G11a) are fine. |

---

## 3. Already at parity — do **not** re-implement

The app implements **98 endpoints** across the 2026-06-11 surface (Auth 12 · User 8 · Messages 11 · Lists 21 incl. 3 public · List Connections 3 · Documents & Sync 14 · Follow 11 · Organizations 9 · Exports 4 · Notifications 3 · Public 2). Test coverage per the last `api-coverage.md` update: **74/98 fully tested (☑), 18 partial (◐), 6 untested**. Feature areas already shipped:

- **Composer:** Markdown, image **+ video** upload, scheduling (incl. cancel/reschedule), threading, digs/reactions; cross-post **Mastodon / Bluesky / LinkedIn** with per-message targets, a result-summary sheet, and pre-flight readiness.
- **Lists:** CRUD, schema DSL (`text, number, date, select, boolean, url, markdown`, kept `email`), nesting, connections graph, watchers (invite by @handle), **cards + real-`Table` grid** views. *(ERD view still open — §1.)*
- **Documents:** Markdown editor, folders, image upload, public/private, offline delta sync, **client-side** templates, rich link previews.
- **Social:** follow/unfollow, requests, mutuals, notifications, dock badge.
- **Organizations:** CRUD, members (incl. by @handle), roles.
- **Exports:** CSV (messages/lists/rows/follows) + **Markdown** export for lists (engine also covers docs/threads — buttons pending, §1).
- **Feed:** All / Mine. *(Following pending — §1.)*

### Resolved since the old docs (the old files still mislabel these as blocked)
| Item | Old label | Reality on this branch |
|---|---|---|
| **Native OAuth account linking** | "backend-gated / browser-handoff only" | ✅ **Built & tested.** `Auth.linkIdentity` → `POST /api/auth/{provider}/link`, `UserService.linkIdentityNative`, `interlinedlist://oauth/callback` scheme, `ASWebAuthenticationSession`. Directly unblocks G4/G7 linking. |
| **GitHub issue writes** | "largest genuine gap, backend-blocked (NB-2)" | Backend **live** → buildable gap **G4**. |
| **Public profile read** | "no endpoint; decision-0002 fallback" | Endpoint **live** → migration **D2**. |
| Scheduled cancel/reschedule, cross-post readiness, watcher/org add-by-handle, cross-post result sheet | listed "blocked" in an even older draft | Already shipped (verified in code by the prior review). |

---

## 4. Architecture & conventions — the build seam

Every gap follows the same layered seam the codebase already uses, so the work is mechanical:

1. **`InterlinedKit`** — one `Request<T>` builder file per endpoint group + `Codable` DTOs; add `…EndpointTests` (builder shape). Send **Bearer** (sync-token); `LiveSessionEstablisher` handles the session-cookie fallback.
2. **`InterlinedDomain`** — a `…Service` with domain models + DTO→model mappers; **gate subscriber-only create-paths through `EntitlementsService`** (`customerStatus`) and surface server `403`s as an upsell rather than an error. BDD-named service tests: happy / invalid / failure / empty.
3. **`InterlinedPersistence`** — `…Record` + `SwiftData…Store` for anything wanting offline cache / optimistic UI (DMs, folders, share grants, unread counts). Store tests.
4. **`App`** — SwiftUI MVVM view models + views + sidebar/menu wiring. **SwiftUI-only — no AppKit / `NSViewRepresentable` without asking.** `AppTests/` view-model tests.
5. **Docs** — add rows to `docs/api-coverage.md` (§8) and update `docs/user/feature-status.md`.

---

## 5. The plan — waves

Each wave is independently shippable, ordered by value ÷ effort and dependency.

### Wave 1 — Social safety & messaging (P0)

**G1 · Direct Messages** *(free, self-contained, highest daily value)*
- **Kit** `DirectMessagesEndpoint.swift`: `list(folder:cursor:)` `GET /api/dm` (folders inbox/sent/deleted, cursor paginated — confirmed); `send(recipientId:body:imageUrls:)` `POST /api/dm` (≤8 images); `thread(username:)`, `threadUpdates(username:since:)` (polling), `unreadCount()`, `recipients()`, `get(id:)`, `markRead(id:)`, `trash(id:)`, `restore(id:)`, `uploadImage(...)`. DTOs: `DirectMessageDTO`, `DMThreadDTO`, `DMFolder`, `DMRecipientDTO`.
- **Domain** `DirectMessagesService`: eligibility (self/blocked/non-mutual → typed error), thread hydration, unread rollup, per-side soft-delete.
- **Persistence** `SwiftDataDMStore` (thread cache + outbox) + unread-count cache for the badge.
- **App** `DirectMessagesRootView` (folder switcher → conversation list → thread) + `DMThreadViewModel` polling `…/updates`; composer with image attachments; unread badge into the existing dock/notification coordinator; "Message" action on profile headers gated to mutual followers (`recipients()`).
- **Tests** eligibility matrix, read-state transitions, independent per-side trash/restore, unread rollup. **L.**

**G2 · Moderation** *(safety table-stakes; interlocks with G1 eligibility)*
- **Kit** `ModerationEndpoint.swift`: `blocks(limit:offset:)`, `isBlocking/block/unblock(username:)`, the `mute` trio, `reportUser(username:reason:detail:)`, `reportMessage(id:reason:detail:)`. `ReportReason` enum (`harassment|spam|misinformation|inappropriate|other`).
- **Domain** `ModerationService` exposing `isBlocked`/`isMuted` so timeline / thread / DM view models filter locally + reconcile.
- **App** overflow-menu block/mute/report (reason sheet) on profiles, timeline rows, DM threads; **Settings → Blocked & Muted** management pane.
- **Tests** block hides author + blocks DM eligibility, report validation, idempotent block/unblock. **M.**

### Wave 2 — Collaboration (P1)

**G3 · Share Links & Collaborators** *(subscriber create-gate; lists + documents)*
- **Kit** extend `ListsEndpoint` + `DocumentsEndpoint`: `shareLinks`, `createShareLink(role:expiresAt:)`, `revokeShareLink(token:)`, `resolveShared(token:)`, `claimShared(token:)`; lists add `sharedData(token:)` and adopt `listsWatching()` `GET /api/lists/watching`; documents add the `collaborators` CRUD quartet + `searchCollaboratorUsers`. DTOs: `ShareLinkDTO{token,url,role,expiresAt}`, `ShareRole` enum (`watcher`/`collaborator`/`manager` ↔ Viewer/Editor/Admin), `ResolvedShareDTO{role,canClaim,needsAuth,resource}`.
- **Domain** `SharingService`: create/list/revoke (subscriber-gated → upsell on 403), resolve+claim (free recipients), collaborator roles; unify existing list "watchers" with the new role model (see spike S3).
- **App** reusable **Share sheet** (People tab: add by @handle + role + remove · Links tab: create with role + optional expiry, copy, revoke); a shared-resource landing view driven by `interlinedlist://…/shared/{token}` and pasted share URLs; a **"Shared with me"** list section backed by `/api/lists/watching`.
- **Tests** subscriber gate on create, free-recipient claim, expired/revoked → 404, role capability matrix. **L.**

**G5 · Search** *(free; quick, high utility)*
- **Kit** `search(query:)` on Messages (**GET** `/api/messages/search?q=`), Lists (`GET /api/lists/search`), Documents (`GET /api/documents/search`).
- **App** global `⌘F` search field in the sidebar fanning out to all three (grouped results) + per-surface in-context search. **M.**

**G4 · GitHub issue integration** *(backend live; dev-audience value; linking already built)*
- **Kit** `GitHubEndpoint.swift`: `repos`, `issues(repo:state:)`, `createIssue`, `updateIssue`(PATCH labels/assignees), `comment`, `assignees`, `labels`, `nextIssueNumber`. DTOs `GitHubRepo/Issue/Label/User`.
- **Domain** `GitHubService` requiring a linked identity (reuse `UserService.identities()`; if unlinked, deep-link the **already-built** native OAuth flow — the 400 "not linked" is the exact state to handle).
- **App** "Create issue from message" (timeline overflow → repo/labels/assignees picker); issue browse/create/comment inside GitHub-backed Lists (which already `refresh`); inline "Link GitHub" CTA.
- **Tests** unlinked → guided link, create/comment happy + validation, picker hydration. **M.**

### Wave 3 — Organization, reach & the purchase path (P2–P3)

**G6 · List Folders** *(subscriber create-gate; lists already have `folderId`)*
- **Kit** `ListFoldersEndpoint.swift`: `folders` `GET /api/folders`, `create(name:parentId:)`, `renameOrMove(id:name?:parentId?:)` `PUT`, `delete(id:)` (detaches lists to root). Reuse the document-folder flat-array + `parentId` tree builder.
- **App** folder tree in the Lists sidebar, drag-to-move (client-side cycle guard; server also rejects), assign a list's `folderId`. **M.**

**G7 · X / Twitter cross-posting** *(OAuth `configured:true`; small composer extension)*
- **Kit** add `.twitter` to `OAuthProvider` (authorize/status generalize already); add the X cross-post flag to `CreateMessageRequest` (**confirm field name — spike S1**).
- **App** X toggle + readiness alongside the existing three; include X in the cross-post result sheet. **S.**

**G8 · In-app billing** *(non-App-Store `.pkg` → Stripe web checkout is compliant)*
- **Kit** `createCheckoutSession()` `POST /api/stripe/checkout-session`, `customerPortalSession()` `GET /api/stripe/customer-portal-session`, `limits()` `GET /api/limits`.
- **App** **Upgrade / Manage subscription** pane opening the returned Stripe URL via `openURL` (same handoff as OAuth), refreshing `customerStatus` on return; render a plan/quota card from `/api/limits` (shape in §2). Wire `maxContentLength`/media limits into composer validation. **M.**

**G9 · Push notifications (APNs)** *(route live; needs entitlement — spike S2 first)*
- **Kit** `registerPush(token:platform:)` `POST /api/push/register`; `unregisterPush(...)` (confirm verb — POST → 405, likely DELETE).
- **App** register device token on launch/sign-in, unregister on sign-out; real pushes replace/augment tray polling (keep polling fallback). **M.**

**G10 · Multi-account switching** *(session-only — spike S4)*
- Resolve the Bearer-vs-session constraint (`/api/auth/accounts` 401 under Bearer) before building. Options: drive a cookie session for these routes, or request a bearer variant upstream. Then: account switcher UI + per-account `KeychainCredentialStore` + cache reset on switch. **M.**

### Wave 4 — Long-tail parity (P3–P4)

- **G11a · LinkedIn personal targets** — target picker in the composer from `/api/linkedin/{posting-targets}`; `POST /api/linkedin/sync-pages` to refresh. **S.**
- **G12 · Server-side document templates** — migrate the client template catalog onto `/api/documents/templates` + `/api/documents/from-template`; adopt `/api/documents/tree` for one-call sidebar hydration. **S.**
- **G14 · `/api/limits` quota card** — folds into G8. **S.**
- **Follow-ups from §1:** per-doc/per-thread Markdown-export buttons (engine ready) · ERD list view (scope first) · public `ListDetailView` grid.
- **Deferred pending demand:** **G11b** LinkedIn org pages (upstream `orgScopesEnabled:false`), **G13** document presence / live cursors.

---

## 6. API-drift / migration pass (corrected against live; do alongside Wave 1)

Only two drift items survived live verification — the orgs/users-current "drift" was a false alarm (§2).

- **D1 — Scheduling:** add `POST /api/messages/{id}/schedule`; keep the working `scheduledAt`-on-create as fallback. *(low risk; verify which the live server prefers)*
- **D2 — Public profile:** add `Users.profile(username:)` `GET /api/users/{username}` (live, returns a real profile) and **replace the decision-0002 fallback** in `SocialService.profile` — real bios/counts instead of projecting from the first public message. Keep the fallback only for pre-migration servers.
- **D3 — Replies verb (verify):** OpenAPI shows `POST /api/messages/{id}/replies`; the app uses `GET`. Confirm and align.
- **Not drift (keep as-is):** `/api/user*` and `/api/organizations*` — the live server serves these, not `/api/users/current` or `/api/orgs`.

---

## 7. Ship gating (M7) — gates *release*, orthogonal to parity

Carried from `feature-gaps.md` §4 — can proceed in parallel with any wave:
- **Sparkle** — `SparkleController` + SPM dep in place; verify the update-check call, `SUFeedURL`, `SUPublicEDKey`, key generation.
- **Appcast hosting** — needs distribution infra on interlinedlist.com.
- **Notarization** — `scripts/notarize.sh` / `package-pkg.sh` need the Developer ID certs (`CODESIGN_IDENTITY` / `INSTALLER_IDENTITY` in `.env` are placeholders).
- **Target:** notarized **`.pkg`** (closed-source private repo; no `LICENSE`). Not App Store (yet) — which is *why* Stripe web checkout (G8) is the correct billing path.
- App Store extras (if pursued later): Privacy/Support pages, and now-satisfiable `/api/limits`.

---

## 8. Coverage tracking — re-baseline `api-coverage.md`

**First task of this whole effort:** `docs/api-coverage.md` is stale at 98 endpoints against the 2026-06-11 surface. Re-baseline it to the current `openapi.json` so coverage stays *verified, not assumed*:
1. Regenerate the endpoint inventory from `openapi.json` (~150 rows).
2. Mark the existing 98 as ☑/◐ per their current state (unchanged).
3. Add **new rows** for every gap here (DM ×11, moderation ×10, share-links/collaborators ×~16, list-folders ×4, github ×8, search ×3, push ×2, stripe ×2, twitter-auth ×3, linkedin ×4, limits ×1, templates ×4, presence ×2) — all starting ☐/☐.
4. Resolve the now-obsolete footnotes: **fn 8** (public profile — endpoint now exists, D2), **fn 12** (OAuth linking — now built).
5. Keep the maintenance rule: a row flips ◐→☑ only when a tested App-layer view model drives it end-to-end.

---

## 9. Sequencing & rationale

1. **Re-baseline `api-coverage.md`** (§8) — half-day; makes all tracking honest.
2. **Wave 1 — G1 DMs + G2 Moderation** — highest daily value, both free-tier, and they interlock (block/mute gate DM eligibility). Ship together.
3. **Wave 2 — G3 Sharing + G5 Search + G4 GitHub** — the collaboration story; G3 is the biggest single feature, G5 a fast win, G4 cashes in the already-built OAuth linking.
4. **Wave 3 — G6/G7/G8/G9/(G10)** — organization, reach, and the purchase path that makes the subscriber gates actually convertible.
5. **Wave 4 — G11a/G12/G14 + follow-ups** — long-tail; re-confirm demand before G11b/G13.
6. **Migration pass (§6)** rides alongside Wave 1. **Ship gating (§7)** runs in parallel throughout.

---

## 10. Open questions / spikes

**Resolved this session (no spike needed):** DM/moderation/share-links/list-folders/search/push/github/templates backends are live (§2); `/api/limits` shape known; X OAuth configured; public-profile endpoint live; orgs/users paths confirmed unchanged.

**Remaining, do before the dependent wave:**
- **S1 (G7):** exact `CreateMessageRequest` field for X/Twitter cross-post — read the `POST /api/messages` request schema in `openapi.json`.
- **S2 (G9):** does the notarized non-sandboxed `.pkg` support APNs, and what provisioning is needed? Also confirm `unregister` verb (POST→405).
- **S3 (G3):** does the list "watchers" model unify cleanly with the new `watcher`/`collaborator`/`manager` roles, or are they two systems?
- **S4 (G10):** how do native Bearer clients use `/api/auth/accounts` + `/api/auth/switch` given the 401-under-Bearer? Session bridge or upstream bearer variant.
- **S5 (Following feed):** re-verify whether `GET /api/messages` now serves a `scope=following` feed (old NB-1) — may already be closable.
- **S6 (G8):** confirm Stripe checkout can round-trip through `interlinedlist://` or must land on a web success page (not probed to avoid live writes).

---

## Appendix — live probe log (2026-07-31, account `messenger`, tier `subscriber`)

Read-only `Authorization: Bearer` probes. `[404 HTML]` = no API route (Next.js shell).

```
POST /api/auth/sync-token                         200  (token acquired)
GET  /api/user                                    200  customerStatus:"subscriber", emailVerified:true
GET  /api/limits                                  200  image maxBytes 1468006 / 1200px jpeg,png,gif,webp; video 3145728 mp4,mov; message 5000
GET  /api/dm                                      200  {items:[], nextCursor:null}
GET  /api/dm?folder=sent                          200  ok
GET  /api/dm/recipients                           200  1 eligible recipient (mutual follower)
GET  /api/dm/unread-count                         200  {count:0}
GET  /api/user/blocks                             200  {blockedUsers:[], pagination}
GET  /api/user/mutes                              200  {mutedUsers:[], pagination}
GET  /api/lists/{id}/share-links                  200  {shareLinks:[]}
GET  /api/lists/{id}/watchers                     200  {watchers:[], pagination}
GET  /api/lists/watching                          200  real "shared-with-me" list
GET  /api/documents/{id}/share-links              200  {shareLinks:[]}
GET  /api/documents/{id}/collaborators            200  {collaborators:[], pagination}
GET  /api/folders                                 200  {folders:[]}   (list folders)
GET  /api/lists?limit=2                           200  rows carry folderId, parentId, source, githubRepo
GET  /api/lists/search?q=a                        200  ok
GET  /api/documents/search?q=a                    200  real docs
GET  /api/messages/search?q=a                     200  (POST → 405; search is GET)
GET  /api/documents/templates                     200  seeded server templates + _templates folder
GET  /api/documents/tree                          200  folders+documents in one payload
GET  /api/linkedin/targets                        200  personal target
GET  /api/linkedin/posting-targets                200  enabled:true, orgScopeMissing:true
GET  /api/github/repos                            400  "GitHub account not linked" (route live)
GET  /api/orgs                                    404  [404 HTML]  → app uses /api/organizations (200)
GET  /api/organizations                           200  real org "Bikey Life"
GET  /api/organizations/{id}/linkedin-page       404  [404 HTML]
GET  /api/orgs/{id}/linkedin-page                404  [404 HTML]  (org LinkedIn not deployed)
GET  /api/users/current                          404  user_not_found  → app uses /api/user (200)
GET  /api/users/messenger                         200  real public profile (endpoint exists → D2)
GET  /api/users/messenger/lists                   200  ok
GET  /api/auth/accounts                           401  Unauthorized under Bearer (session-only → G10)
GET  /api/auth/twitter/status                     200  configured:true
GET  /api/auth/linkedin/status                    200  configured:true, orgScopesEnabled:false
GET  /api/auth/bluesky/status                     200  configured:true
POST /api/push/register  {}                       400  "token is required" (route live)
POST /api/push/unregister {}                      405  (not POST — likely DELETE)
GET  /api/notifications                            200  unreadCount:5
```
```
Auth: POST /api/auth/sync-token {email,password} → {token:"il_tok_…"} (64-char); then Authorization: Bearer <token>.
No live writes were performed (no DMs sent, no data created/modified/deleted).
```
