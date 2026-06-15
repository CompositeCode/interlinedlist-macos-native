# 0001 — Authentication transport for the macOS client

- **Status:** Accepted (empirically confirmed 2026-06-15; fallback scope narrowed)
- **Date:** 2026-06-15
- **Context:** PLAN.md §4 (Authentication Strategy), §3 (Architecture / APIClient)
- **Supersedes / superseded by:** —

## Context

PLAN.md §4 left one open question that gates the `APIClient` design: the
[API docs](https://interlinedlist.com/help/api) mark some endpoint groups
**"Session or Bearer"** and others **"Session"-only**. If the Session-only
groups genuinely reject the desktop-oriented Bearer token from
`POST /api/auth/sync-token`, the client must also maintain an `HttpOnly`
session cookie. The Wave 0 spike (task 0.3a) was meant to settle this
empirically before Wave 1 builds the client.

## Evidence

**Documentation (authoritative for now).** Nine groups are marked
Session-only: Notifications, Follow, Organizations, Documents (non-sync),
Document folders, Exports, plus the `/api/user/identities` and
`/api/user/organizations` subgroups and `/api/messages/[id]/replies`
(and digs/uploads). "Session or Bearer" covers `/api/user`, `/api/messages`,
and Lists. This is captured per-endpoint in [api-coverage.md](../api-coverage.md).

**Empirical probe — COMPLETED 2026-06-15.** Initially blocked (delegated
subagent denied Bash; then `sync-token` returned 401 on stale env-var
credentials). After the user supplied working credentials, the read-only probe
ran in full — see [spikes/auth-bearer-vs-session.md](../spikes/auth-bearer-vs-session.md).

Result: **Bearer works on nearly the entire surface**, including most groups the
docs mark Session-only (Notifications, Follow, Organizations, Documents,
document folders, message replies — all 200). Bearer is genuinely **rejected
(401) on only ~6 endpoints**: `GET /api/user/identities`,
`GET /api/user/organizations`, and the four Exports CSV endpoints.

## Decision

`APIClient` uses an `AuthTransport` seam with **Bearer as the primary,
near-universal transport** and a **lazy cookie-session fallback** scoped to a
small explicit allowlist (now confirmed by the spike rather than assumed):

- **Bearer (default) for everything** — token from `POST /api/auth/sync-token`,
  stored in Keychain (§2), no auto expiry.
- **Cookie-session** (`POST /api/auth/login` + `URLSession`-managed `HttpOnly`
  cookie) only for the confirmed session-only allowlist:
  - `GET /api/user/identities`
  - `GET /api/user/organizations`
  - `GET /api/exports/*` (all four CSV endpoints)
- The cookie transport is **lazy** — established only when the user first hits
  one of those endpoints (linked identities, org membership detail, or an
  export). Bearer-only users who never export never establish a session.
- **Runtime safety net:** on an unexpected `401` to a Bearer request, retry once
  via the session transport and log it — catches future API drift in either
  direction.

## Consequences

- **Wave 1 proceeds** with the `AuthTransport` seam. Every Wave 1 task prompt
  must cite this decision: Bearer default, lazy session fallback for the
  allowlist only.
- **Simpler than the conservative fallback** the docs implied — only ~6
  endpoints need cookies, so the linked-identities, org-membership, and export
  screens are the only ones that establish a session.
- **Token handling unchanged from §2:** Bearer token (`il_tok_…`, no auto
  expiry) stored in Keychain only.
- **Drift watch:** if the API later accepts Bearer on the allowlisted endpoints
  (or rejects it on currently-working ones), the runtime safety net surfaces it;
  re-run the probe (see below) and amend here.

## Re-running the spike (drift check)

Orchestrator-held read-only probe: `POST /api/auth/sync-token` for the token,
then GET each Session-only read endpoint with `Authorization: Bearer …` plus
the `/api/user` and `/api/messages` controls; on any 401, repeat one endpoint
via a `POST /api/auth/login` cookie jar. Output is sanitized to HTTP status +
JSON key names; no credential or token value is ever printed or written. The
deliverable is [spikes/auth-bearer-vs-session.md](../spikes/auth-bearer-vs-session.md).
