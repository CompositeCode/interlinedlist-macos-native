# Backend Blockages — macOS app parity work

**For:** the InterlinedList backend / API team · **From:** macOS native app · **Date:** 2026-07-18

> **Canonical tracker:** [`blocker-prompts.md`](blocker-prompts.md). The parity asks below were **folded into it** on 2026-07-18 under the `P#` scheme (with paste-ready prompts) — this file is now just a parity-focused index into that tracker. Everything was verified against current code, not memory.

## New parity asks (now tracked in `blocker-prompts.md`)

| Parity ask | Impact | Tracker ID |
| --- | --- | --- |
| Following / home feed endpoint (client UI wired, short-circuits to empty) | **High** | **P1-G** |
| GitHub issue create/comment + labels/assignees (largest gap; extends P3-C) | **High** | **P1-H** |
| Markdown export format / per-item export (client renders MD itself for now) | Medium | **P2-F** |
| Schema DSL `select`/`markdown` token spec (client shipped both; confirm tokens) | Medium | **P2-G** |
| Link-preview `fetchStatus` value docs | Low | **P3-F** |
| List "save to my lists" clone-with-rows | Low | **P3-G** |
| Message edit verb `PATCH` (docs) vs `PUT` (client) | Low | **P3-H** |

Already tracked and still open, relevant to parity: **P1-E** (native OAuth link callback — the one OAuth blocker), **P2-C** (notification `routePath` for deep-linking), **P2-D** (upload limits), **P2-E** (Privacy/Support pages for App Store).

**Hand-off priority: P1-G and P1-H unlock the most user-visible parity.**

## Corrections — thought blocked, actually already shipped

The first-draft blockages list (and the older project memory) wrongly flagged these as backend-gated. **They are shipped and wired** — verified in code, and `blocker-prompts.md` already marks the enabling endpoints resolved (NW-1…NW-6). Do **not** spend backend time here.

| Was flagged | Reality | Evidence |
| --- | --- | --- |
| Scheduled post cancel/reschedule | **Done** (P1-C / NW-3) | `ScheduledPostsViewModel.cancel()`/`.reschedule()` + UI; `MessagesService.cancelScheduled`/`reschedule` |
| Bluesky/Mastodon cross-post readiness | **Done** (P1-D / NW-4) | `ComposerViewModel.blueskyNotConfigured`/`mastodonNotConfigured` |
| Watcher-invite-by-handle | **Done** (P1-A / NW-6) | `WatchersViewModel.lookupAndAdd(handle:)` → `UserService.lookupUser` |
| Org-member-add-by-handle | **Done** (P1-A) | `OrgMembersViewModel.addMemberByHandle` |
| Cross-post per-platform result summary | **Done** (P1-B / NW-2) | `CrossPostResultsSheet` wired in `ComposerWindowView` |
