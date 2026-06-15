# 0001 — Authentication transport for the macOS client

- **Status:** Accepted (provisional — empirical confirmation pending valid credentials)
- **Date:** 2026-06-15
- **Context:** PLAN.md §4 (Authentication Strategy), §3 (Architecture / APIClient)
- **Supersedes / superseded by:** —

## Context

PLAN.md §4 left one open question that gates the `APIClient` design: the API
docs (https://interlinedlist.com/help/api) mark some endpoint groups
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

**Empirical probe — BLOCKED.** The live probe could not run to completion:

1. Delegated subagent (task 0.3a) was denied Bash entirely in its session and
   correctly refused to fabricate a results table.
2. The orchestrator re-ran the probe directly. `POST /api/auth/sync-token`
   returned **HTTP 401 `{"error":"Invalid email or password"}`** using the
   `INTERLINEDLIST_EMAIL` / `INTERLINEDLIST_PASSWORD` environment variables.
   The endpoint itself is healthy (empty body → HTTP 400; the 401 is a genuine
   credential rejection, not a transport fault). The supplied credentials are
   therefore invalid/stale (the password variable is 6 characters).

No token was obtained, so **no Session-only endpoint was probed**. The
Bearer-vs-Session question remains empirically unresolved.

## Decision

Adopt the **conservative dual-transport design now**, unblocking Wave 1:

- `APIClient` treats **Bearer token as the primary transport** (per §4, the
  documented desktop path) and supports a **cookie-session fallback**
  (`POST /api/auth/login` + `URLSession`-managed `HttpOnly` cookie) as a
  first-class, switchable transport.
- A single seam (e.g. `AuthTransport` strategy) selects per-request transport.
  Default routing: Bearer for "Session or Bearer" groups; cookie-session for
  the nine Session-only groups until the probe proves Bearer also works there.
- On `401` for a Bearer request to a Session-only group at runtime, the client
  transparently retries via the session transport (and logs it, feeding the
  same question).

This is the safe superset: it is correct whether or not Bearer turns out to
work on Session-only endpoints. The spike could only ever have let us *remove*
the fallback, not add a requirement — so a blocked spike does not block Wave 1.

## Consequences

- **Wave 1 proceeds** with both transports. Every Wave 1 task prompt must cite
  this decision and build the `AuthTransport` seam.
- **Reversible:** once valid credentials exist, re-run the probe (the script is
  ready; see below). If Bearer works on all Session-only groups, open `0002`
  to simplify to single-transport and delete the fallback. If it confirms the
  docs, this decision becomes final as-is.
- **Token handling unchanged from §2:** Bearer token (`il_tok_…`, no auto
  expiry) stored in Keychain only.

## Action required from the user

Provide working credentials for a test account (or confirm the env-var values),
so the empirical probe can run and either confirm or simplify this decision.
Until then the fallback stays in by default — no functionality is lost, only
potential simplification is deferred.

## Re-running the spike

Orchestrator-held read-only probe: `POST /api/auth/sync-token` for the token,
then GET each Session-only read endpoint with `Authorization: Bearer …` plus
the `/api/user` and `/api/messages` controls; on any 401, repeat one endpoint
via a `POST /api/auth/login` cookie jar. Output is sanitized to HTTP status +
JSON key names; no credential or token value is ever printed or written. The
deliverable is `docs/spikes/auth-bearer-vs-session.md`.
