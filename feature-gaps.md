# Feature Parity Gaps — macOS app vs. interlinedlist.com

**Reviewed:** 2026-07-18 · **Branch:** `dev` · **Basis:** [interlinedlist.com/features](https://interlinedlist.com/features) cross-referenced against the App target, `InterlinedDomain`, `InterlinedKit`, and `InterlinedPersistence`.

> **2026-07-18 implementation update.** Most of the client-closable gaps in §1 were **built this session** (schema `select`/`markdown`, link previews, document templates, and the Markdown-export engine). The build is green: **App 375 tests / 0 failures, InterlinedDomain 475 / 0** (Kit 224, Persistence 120 unchanged). Backend-blocked items are tracked in **[`feature-blockages.md`](feature-blockages.md)**, which is reconciled against the canonical **[`blocker-prompts.md`](blocker-prompts.md)**. Several items the first draft called "blocked" turned out to be **already shipped** — see §2b.

## TL;DR

The native app is **at or very near full parity**. Every documented API endpoint is implemented (98/98 per [`docs/api-coverage.md`](docs/api-coverage.md)), and the NW-1…NW-6 backend items are done (per `blocker-prompts.md`). What remained were a handful of surface features; the client-closable ones are now largely done, and the genuine gaps are backend-gated (following feed, GitHub issue writes, OAuth callback).

### Parity scorecard

| Site feature area | Status |
| --- | --- |
| Compose: Markdown, images **+ video**, scheduling, threading, digs/reactions | ✅ Shipped |
| Cross-post Mastodon/Bluesky/LinkedIn, per-message targets, **result summary**, **pre-flight readiness** | ✅ Shipped |
| Structured lists: CRUD, nesting, connections graph, watchers (**invite by @handle**) | ✅ Shipped |
| Schema DSL field types (`text, number, date, select, boolean, url, markdown`) | ✅ **`select` + `markdown` added this session** (kept `email`) |
| List row views: cards / **grid** / ERD | ✅ Cards + **grid (real Table)** shipped; ERD = scope TBD |
| Documents: Markdown editor, folders, image upload, public/private, offline sync | ✅ Shipped |
| Document **templates** | ✅ **Added this session** (Blank / Meeting Notes / Daily Log / PRD) |
| Rich link previews on posts | ✅ **Added this session** (server metadata → preview card) |
| Exports: **Markdown** for lists / documents / threads | ✅ Engine + **My Lists → Markdown** UI shipped; per-doc/thread buttons = follow-up |
| Exports: CSV | ✅ Shipped |
| Scheduled post edit/cancel | ✅ Shipped (was mis-listed as blocked — see §2b) |
| Organizations & roles (**add member by @handle**) | ✅ Shipped |
| Feed filtering: all / mine / following | ⚠️ All/Mine shipped; **Following UI-wired but empty** — backend feed endpoint pending (§2) |
| GitHub sync: issue create/comment, labels/assignees | ❌ Backend-gated (§2 / `feature-blockages.md` NB-2) |
| Native OAuth account linking | ❌ Backend-gated (§2 / `blocker-prompts.md` P1-E) |
| AI writing assist | "Coming Soon" on site too — not a gap |

---

## 1. Client-closable gaps

**Project constraint for all work here:** the App target is **SwiftUI-only — no AppKit / `NSViewRepresentable`** without asking; follow the MVVM + `InterlinedDomain` service seam and add BDD-style tests (`AppTests/` conventions).

### 1.1 — Schema DSL: `select` + `markdown` field types  ✅ DONE (this session)

`SchemaFieldType` gained `.select` (ordered options via `SchemaField.enumValues`, DSL `Field:select(a|b|c)`) and `.markdown` (long text, Textual preview in `RowInspectorView`). Editor + row cells + DSL parser/serializer updated; 25 new tests. **Backend confirmation needed** on the exact `select` token/delimiter and `email` acceptance — see `feature-blockages.md` NB-4.

### 1.2 — List row views: grid, then ERD  ✅ GRID DONE (this session); ERD scoped separately

`ListRowsView.tableMode` (owned lists) now renders a **real SwiftUI `Table`** with one typed column per schema field via `TableColumnForEach` (valid at the macOS 15 target; the stale 14.4 fallback comment is removed). Pagination is a Load-More footer (Table has no per-row appearance hook); cards mode keeps scroll-to-load. Columns come from the schema, falling back to the sorted union of row keys.

**ERD remains open** — before building, confirm what "ERD" means in the web app (schema field graph vs. the existing list-to-list connection graph) so it's scoped correctly. The public `ListDetailView` (read-only browse) still shows cards only; a grid there is a smaller follow-up.

### 1.3 — Markdown export  ✅ DONE (this session)

`MarkdownExporter` (`InterlinedDomain`) renders documents, threads, and lists-as-tables (pipe/newline-escaped), 15 tests. The Export sheet now offers **"Export My Lists as Markdown"** — `ExportViewModel` paginates owned lists + rows and renders them into a `MarkdownFileDocument` (`.md`) via a second `fileExporter`; 4 view-model tests. The `/api/exports/*` endpoints are CSV-only, so this composes client-side (server-side ask = `blocker-prompts.md` P2-F).

**Follow-up (engine already supports it):** per-item "Export as Markdown" affordances — document editor toolbar (`markdown(for:)`) and message-thread menu (`markdown(forThreadRoot:replies:)`).

### 1.4 — Document templates  ✅ DONE (this session)

`DocumentTemplate.builtIn` catalog (Blank / Meeting Notes / Daily Log / PRD) + "New from Template…" command (⇧⌥⌘N) and picker sheet, seeding `DocumentBody.markdown` through the existing create path; 12 tests. Client-side (no templates endpoint).

### 1.5 — Rich link previews  ✅ DONE (this session)

**Was not blocked** — the server already returned `linkMetadata`. Added `Message.linkPreviews` + mapper (drops unparseable URLs) + a tappable `LinkPreviewCardView` in the timeline; 16 tests. Render gate is forward-compatible pending `fetchStatus` docs (`feature-blockages.md` NB-5).

---

## 2. Genuinely backend-blocked (cannot close from the client)

Full asks + prompts in **[`feature-blockages.md`](feature-blockages.md)** (reconciled with `blocker-prompts.md`). Summary:

- **Following feed** (NB-1 · HIGH) — `TimelineScope.following` is UI-wired but `MessagesService.timeline` short-circuits to empty; no endpoint exists.
- **GitHub issue create/comment + labels/assignees** (NB-2 · HIGH) — the largest genuine gap. `blocker-prompts.md` P3-C tracks only refresh *metadata*; issue writes are net-new.
- **Native OAuth account linking** (`blocker-prompts.md` P1-E) — linking opens the browser; no native callback/scheme or bearer link endpoint.
- **Markdown export format** (NB-3 · med) — client works around it; server format negotiation would be more efficient.
- **List "save to my lists" row cloning** (NB-6 · low) — copies metadata+schema only.

## 2b. Corrections — thought blocked, actually already shipped

The first draft (and the older project memory) listed these as blocked. They are **done** — verified in code. The user-facing `docs/user/feature-status.md` still described some as pending; that staleness is being corrected in a parallel docs pass.

| Feature | Evidence it's shipped |
| --- | --- |
| Scheduled post cancel/reschedule | `ScheduledPostsViewModel.cancel()`/`reschedule()` + UI (P1-C / NW-3) |
| Cross-post pre-flight readiness (Bluesky/Mastodon) | `ComposerViewModel.blueskyNotConfigured`/`mastodonNotConfigured` (P1-D / NW-4) |
| Watcher invite by @handle | `WatchersViewModel.lookupAndAdd` → `UserService.lookupUser` (P1-A / NW-6) |
| Org member add by @handle | `OrgMembersViewModel.addMemberByHandle` (P1-A) |
| Cross-post per-platform result summary | `CrossPostResultsSheet` wired in `ComposerWindowView` (P1-B / NW-2) |

---

## 3. Already at parity (do not re-implement)

Composer (Markdown, image+video, scheduling incl. cancel/reschedule, per-message cross-post + result sheet + readiness); digs/reposts/threads; Documents (editor, folders, image upload, public/private, offline sync, templates); link previews; Social (follow/unfollow, requests, mutuals, notifications, dock badge); Organizations (CRUD, members incl. by-handle, roles); Lists (CRUD, schema DSL incl. select/markdown, nesting, connections graph, watchers incl. invite-by-handle); CSV export; feed All/Mine.

---

## 4. Ship (M7) — gates release, not parity

- **Sparkle** — `SparkleController` + SPM dep in place; verify update-check call, `SUFeedURL`, `SUPublicEDKey`, key generation.
- **Appcast hosting** — needs distribution infra on interlinedlist.com.
- **Notarization** — `scripts/notarize.sh`/`package-pkg.sh` need Developer ID certs.
- Target: notarized **`.pkg`** (closed-source private repo; no `LICENSE`).
- App Store extras tracked in `blocker-prompts.md`: **P2-E** (Privacy/Support pages), **P2-D** (limits endpoint).

---

## Suggested order of remaining work

1. **Backend:** hand `blocker-prompts.md` **P1-G** (following feed) and **P1-H** (GitHub issue writes) to the API team — they unlock the most parity.
2. **ERD view** — confirm what "ERD" means in the web app, then build (grid is done).
3. **Follow-ups:** per-document / per-thread "Export as Markdown" buttons (engine ready); grid on the public `ListDetailView`.
4. **§4 ship** — Sparkle finalization + notarization.

_Done this session: §1.1 schema select/markdown, §1.2 grid, §1.3 Markdown export (engine + UI), §1.4 templates, §1.5 link previews._
