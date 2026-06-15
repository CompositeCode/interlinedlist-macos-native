# Spike: Bearer vs Session transport

- **Date:** 2026-06-15
- **Question (PLAN.md §4):** Do the endpoint groups the API docs mark
  "Session"-only actually reject a Bearer token from
  `POST /api/auth/sync-token`, forcing a cookie-session fallback in `APIClient`?
- **Method:** Acquired a Bearer token, then issued **read-only** `GET` requests
  to one representative endpoint per Session-only group with
  `Authorization: Bearer …`, plus two documented "Session-or-Bearer" controls.
  Output sanitized to HTTP status + top-level JSON keys; no credential or token
  value was printed or stored. No write requests were made (the only `POST` was
  the token exchange itself). Production account.

## Results

| Endpoint | Group | Doc auth | Bearer status | Body shape |
| --- | --- | --- | --- | --- |
| `GET /api/user` | User (control) | Session or Bearer | **200** | `{user}` |
| `GET /api/messages?limit=1&onlyMine=true` | Messages (control) | Session or Bearer | **200** | `{messages,pagination}` |
| `GET /api/messages/[id]/replies` | Messages | Session | **200** | `{replies,total}` |
| `GET /api/messages/scheduled?range=week` | Messages | Session or Bearer | **200** | `{messages}` |
| `GET /api/lists?limit=1` | Lists | Session or Bearer | **200** | `{lists,pagination}` |
| `GET /api/notifications?scope=tray` | Notifications | Session | **200** | `{items,unreadCount}` |
| `GET /api/follow/requests` | Follow | Session | **200** | `{requests}` |
| `GET /api/organizations` | Organizations | Session | **200** | `{organizations,pagination}` |
| `GET /api/documents` | Documents | Session | **200** | `{documents}` |
| `GET /api/documents/folders` | Documents folders | Session | **200** | `{folders}` |
| `GET /api/user/identities` | User subgroup | Session | **401** | `error: Unauthorized` |
| `GET /api/user/organizations` | User subgroup | Session | **401** | `error: Unauthorized` |
| `GET /api/exports/messages` | Exports | Session | **401** | `error: Unauthorized` |
| `GET /api/exports/lists` | Exports | Session | **401** | `error: Unauthorized` |

The three 401s were re-probed and are stable, not transient.

## Findings

1. **Bearer works for nearly the entire feature surface.** Every Session-only
   group that backs a primary app feature — Notifications, Follow,
   Organizations, Documents, document folders, message replies — accepts the
   Bearer token. The docs understate Bearer support for these.
2. **Three places genuinely require a session cookie** (Bearer → 401):
   - `GET /api/user/identities`
   - `GET /api/user/organizations`
   - the **Exports** group (all four CSV endpoints: `messages`, `lists`,
     `list-data-rows`, `follows` — two probed, both 401; treated as a group).
3. So the cookie-session fallback is needed for **~6 endpoints**, not the nine
   groups the documentation's Session-only labels implied.

## Recommendation

**Bearer is the primary and near-universal transport.** Keep the
`AuthTransport` seam from [decision 0001](../decisions/0001-auth-transport.md),
but default it to **Bearer for everything** and maintain a small explicit
**session-only allowlist** that triggers the `POST /api/auth/login` cookie flow:

```
/api/user/identities
/api/user/organizations
/api/exports/*
```

Implementation notes for Wave 1:
- The cookie transport is lazy — only established when the user first hits a
  session-only endpoint (linked-identities screen, org-membership detail, or an
  export). Free/Bearer-only users who never export never pay for it.
- Keep a runtime safety net: on an unexpected `401` to a Bearer request, retry
  once via the session transport and log it (detects future API changes in
  either direction).
- Re-run this probe if the API docs or behavior change; it doubles as a
  drift check.
