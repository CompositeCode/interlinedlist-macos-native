# Backend Blockages — macOS app parity work

**For:** the InterlinedList backend / API team · **From:** macOS native app · **Date:** 2026-07-18

> **Read this first.** The repo already has a canonical, maintained backend tracker:
> **[`blocker-prompts.md`](blocker-prompts.md)** (last updated 2026-07-08, with a `P1-A…P3-E`
> ID scheme and paste-ready prompts). **That file is the source of truth.** This file is a
> *parity-driven supplement*: it captures backend asks surfaced by the 2026-07-18 feature-parity
> pass that are **not yet in** `blocker-prompts.md`, plus corrections to it. These should be
> folded into `blocker-prompts.md` — I did not edit that file unilaterally.

Verified against current code, not memory. Ordered by impact.

---

## A. New backend asks (not yet tracked in `blocker-prompts.md`)

### NB-1 — Following / home feed endpoint  · impact: **HIGH**

- **Site promise:** feed filtering "all public, followed-only, or mixed."
- **Today:** `TimelineScope.following` is fully wired through the UI (All / Mine / **Following** segmented picker), but `MessagesService.timeline` (`MessagesService.swift:348`) **short-circuits `.following` to an empty page** — "The Following feed has no API endpoint yet" — so it renders a "coming soon" empty state instead of a spinner or error.
- **API ask:** a followed-accounts timeline, e.g. `GET /api/messages?scope=following` (or `GET /api/feed/following`), same paginated envelope as `GET /api/messages`. The client then flips one `if` and it works.

### NB-2 — GitHub issue create / comment + labels / assignees  · impact: **HIGH** (largest genuine gap)

- **Site promise:** "GitHub repository issue syncing," "create and comment on issues within platform," "automatic label and assignee pulling."
- **Today:** the client has only a read-only `GitHubListSource` projection refreshed manually. Note **`blocker-prompts.md` P3-C already tracks the refresh *metadata*** (`lastRefreshedAt`, `refreshStatus`, `githubSource` on POST) — but P3-C does **not** cover issue **writes** or **labels/assignees**. Those are net-new.
- **API ask (extends P3-C — needs a contract):**
  1. Expose issue **labels and assignees** as fields on GitHub-sourced list rows.
  2. Endpoints to **create an issue** and **comment on an issue** from a synced list.
  3. (P3-C already covers) auto/scheduled refresh + `githubSource` on create.
- The single largest user-visible feature the app can't offer; entirely backend-gated.

### NB-3 — Markdown export format / per-item export  · impact: medium

- **Site promise:** "Markdown export for lists, documents, and message threads" + full data portability.
- **Today:** `/api/exports/*` is **CSV only** (4 endpoints), no format negotiation, no per-document/thread export. The client now renders Markdown **itself** from domain models (`MarkdownExporter` in `InterlinedDomain`), so this is a nice-to-have, not a hard blocker.
- **API ask:** (1) a format param, e.g. `GET /api/exports/lists?format=md` (or `Accept: text/markdown`); (2) per-resource export: `GET /api/documents/[id]/export?format=md`, `GET /api/messages/[id]/thread/export?format=md`, `GET /api/lists/[id]/export?format=md`. Server-side rendering avoids the client's N+1 refetch for large accounts.

### NB-4 — Schema DSL token spec for `select` and `markdown`  · impact: medium (verification)

- **Context:** the client just added `select` and `markdown` schema field types (shipped, 25 tests green). The API has never enumerated the DSL type taxonomy (pre-existing `API-backend-prompts-to-build.md` item 2.2). The schema crosses the wire as a DSL string round-tripping through the client's `SchemaDSL` only, so these are **unverified against the server:**
  1. **`select` token + option grammar.** Client chose `Field:select(a|b|c)` (token `select`, `(...)` wrapper, `|` delimiter). Confirm the token, the delimiter, and whether the server **persists and re-emits the option list verbatim** on `GET .../schema` (or normalizes/strips it).
  2. **`markdown` cell wire shape.** Client assumes a plain JSON string of raw Markdown (existing `ListJSONValue` string case, no codec change). Confirm.
  3. **`email` acceptance.** The site's advertised set is `text, number, date, select, boolean, url, markdown` (no `email`), but the client keeps an `email` token. Confirm the server accepts `email` on `PUT .../schema`.
- If tokens/delimiter differ, the single client change-point is `SchemaDSL.serialize`/`splitTypeSpec` + `SchemaFieldType`.

### NB-5 — Link-preview `fetchStatus` semantics  · impact: low (verification)

- **Context:** the server already returns link-preview metadata (`MessageDTO.linkMetadata.links[]` with `title`, `description`, `imageUrl`, `platform`, `fetchStatus`); the client now renders preview cards from it (this was **not** blocked). The client's render gate is forward-compatible (renders when a ready-ish `fetchStatus` OR a title/image is present).
- **API ask:** document the `fetchStatus` value set — which string means "ready" vs "pending" vs "failed" — so the client can tighten its gate to the authoritative token(s).

### NB-6 — List "Save to my lists" row cloning  · impact: low

- **Site promise:** save/copy public lists.
- **Today:** `ListDetailViewModel.saveToMyLists` copies **metadata + schema only** (documented "deliberate degradation — no clone endpoint"). Not in `blocker-prompts.md`.
- **API ask:** `POST /api/lists/[id]/clone` (or a rows-copy on save) that duplicates rows into the new owned list.

---

## B. Already tracked in `blocker-prompts.md` — still open, relevant to parity

Pointers only; prompts already exist in that file.

- **P1-E — Native OAuth identity-linking callback** (⛔ still the reason linking opens the browser). This is the one OAuth blocker; the client is fully designed for `ASWebAuthenticationSession` once a custom-scheme callback or bearer `…/link` endpoint exists.
- **P2-C — Typed notification kinds + `routePath`** — unblocks richer notification deep-linking (today deep-linking just brings the app forward).
- **P2-D — Machine-readable upload limits** (`GET /api/limits`) — client has limits hard-coded.
- **P2-E — Privacy Policy + Support pages** — required for any future App Store submission.
- **P3-A/B/D/E** — sync ETag, `folderId` on sync, token revocation, universal rate-limit headers (internal robustness, not user-facing parity).

---

## C. Corrections — previously suspected blocked, actually DONE

The 2026-07-18 first-pass draft of this file (and `feature-gaps.md`) flagged these as backend-blocked. **They are already implemented and wired** — do NOT spend backend time on them. Root cause of the error: the older project memory predated the NW-1…NW-6 completion recorded in `blocker-prompts.md` (2026-07-08), and the user-facing `docs/user/feature-status.md` still describes them as pending (that doc is stale — see the parity report).

| Was flagged | Reality | Evidence |
| --- | --- | --- |
| Scheduled post cancel/reschedule blocked | **Done** (P1-C / NW-3) | `ScheduledPostsViewModel.cancel()` + `.reschedule()`, "Cancel Post"/"Reschedule…" UI, `MessagesService.cancelScheduled`/`reschedule` |
| Bluesky/Mastodon cross-post pre-flight readiness blocked | **Done** (P1-D / NW-4) | `ComposerViewModel.blueskyNotConfigured` / `mastodonNotConfigured` |
| Watcher-invite-by-handle blocked | **Done** (P1-A / NW-6) | `WatchersViewModel.lookupAndAdd(handle:)` → `UserService.lookupUser` |
| Org-member-add-by-handle blocked | **Done** (P1-A) | `OrgMembersViewModel.addMemberByHandle` / `foundUser` |
| Cross-post per-platform result summary blocked | **Done** (P1-B / NW-2) | `CrossPostResultsSheet` wired in `ComposerWindowView` |

---

### Triage summary (new asks only)

| ID | Ask | Impact |
| --- | --- | --- |
| NB-1 | Following feed endpoint | **High** |
| NB-2 | GitHub issue write + labels/assignees (extends P3-C) | **High** |
| NB-3 | Markdown export format / per-item | Medium |
| NB-4 | Schema DSL `select`/`markdown` token spec | Medium |
| NB-5 | Link-preview `fetchStatus` doc | Low |
| NB-6 | List clone-with-rows | Low |

**NB-1 and NB-2 unlock the most parity.** Everything else is smaller or documentation-only. Recommend merging NB-1…NB-6 into `blocker-prompts.md` under the `P#` scheme.
