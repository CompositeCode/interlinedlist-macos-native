# 0002 — Public user profile fallback via embedded author

- **Status:** Accepted (2026-06-21)
- **Date:** 2026-06-21
- **Context:** PLAN.md §1 (Profile / Follow-system rows), §6 M1 (user profiles), §7 (coverage matrix discipline); decision 0001 (auth transport)
- **Supersedes / superseded by:** —

## Context

PLAN.md §1 commits M1 to "user profiles" as part of the read-only core,
implying a `SocialService.profile(username:)` call that resolves a
`UserProfile` for any public handle. The natural backing endpoint would be
`GET /api/users/[username]` — but neither the [API reference][api] nor any
read-only probe finds it. Wave 1 shipped the three `/api/users/[username]/lists*`
rows and `/api/user/[username]/messages` against the live API; the public
profile read was the only Profile-row gap.

The 2026-06-21 kit-gap spike was run to settle whether the endpoint exists
under a different shape, so M1 can either implement against it or commit to a
documented fallback before the Domain agent wires `SocialService`.

[api]: https://interlinedlist.com/help/api

## Evidence

**Live-API probes (read-only, no creds), 2026-06-21.** All of the following
returned `404 Not Found`:

- `GET /api/users/[username]`
- `GET /api/user/[username]`
- `GET /api/users/[username]/profile`
- `GET /api/users/[username]/public`
- `GET /api/profile/[username]`
- `GET /api/u/[username]`
- `GET /api/public/users/[username]`
- `GET /api/users/[username]/followers`
- `GET /api/users/[username]/following`

**Control probes (same run, same username) returned `200 OK`:**

- `GET /api/users/[username]/lists`
- `GET /api/user/[username]/messages`

The username path segment is therefore valid; the public profile route
genuinely does not exist.

**Docs review.** [https://interlinedlist.com/help/api][api] documents no public
profile read endpoint. The only routes under `/api/users/[username]*` or
`/api/user/[username]*` are: the three public-list reads (already shipped
in Wave 1), `/api/user/[username]/messages` (public messages), and the
unrelated `/api/auth/linkedin/status`. Follower/following enumeration is
session-only via `/api/follow/[userId]/{followers,following}` and requires a
user ID, not a username.

**Embedded-author shape.** `GET /api/user/[username]/messages` embeds the
author user object on every message, matching `MessageAuthorDTO` already in
`InterlinedKit`:

```
{ "id": "...", "username": "...", "displayName": "...", "avatar": "..." }
```

No `bio`, `joinedAt`, `isPrivate`, or follower counts are present. (See
`Packages/InterlinedKit/Sources/InterlinedKit/DTOs/MessageDTO.swift` —
`MessageAuthorDTO`.)

## Decision

`SocialService.profile(username:)` is implemented for M1 against the embedded
author of a public message, not a direct profile read:

- Implementation calls `Messages.publicUserMessages(username:, limit: 1)` and
  extracts the embedded `MessageAuthorDTO` from the first message.
- The returned `UserProfile` populates only `{ id, username, displayName,
  avatar }`. All other fields (`bio`, `joinedAt`, `isPrivate`, follower
  counts) are explicitly `nil`. This nil-ness is documented on the model and
  pinned by a BDD test in the Domain suite.
- A user with zero public messages cannot be resolved this way. The service
  throws a typed domain error in that case — name owned by the Domain agent
  (e.g. `SocialError.profileUnavailable(username:)`).
- A `UserProfile.init(fromEmbeddedAuthorOf: MessageDTO)` mapper is provided on
  the Domain side so the same reduction is reusable from any timeline / detail
  surface that already holds a message — no extra network round-trip when the
  caller has a message in hand.

## Consequences

- **M1 profile UI is a thin header.** Avatar + display name + handle is the
  full set of fields the service can return. Richer profile chrome (bio, join
  date, lock icon for private accounts, follower / following counts) is
  deferred. The view model and SwiftUI view must be designed to render the
  reduced field set without empty-cell placeholders.
- **Zero-public-messages users are a dead end in M1.** A friendly empty
  state ("This profile has no public messages yet") is the M1 UX. This is
  not a defect to fix in M1; it is the documented limit of the fallback.
- **Upstream API request to file.** A feature request for
  `GET /api/users/[username]` (public, returns the full profile shape
  including `bio`, `joinedAt`, `isPrivate`, follower counts) should be filed
  against the InterlinedList API. Tracking issue and link to be added here
  when filed.
- **M5 (Social & notifications) inherits a dependency.** Follower / following
  list screens at M5 still go through `/api/follow/[userId]/*` (which takes a
  user ID), so they need a username → userId resolution. The M1 fallback
  satisfies that resolution path (embedded author carries `id`), so M5 is not
  blocked — but if the upstream profile endpoint lands first, M5 should adopt
  it for the cleaner shape (richer header + the same `id`).
- **Coverage matrix.** No row exists today for `GET /api/users/[username]`
  because the endpoint is not in the live reference. A footnote on
  `docs/api-coverage.md` records the missing endpoint, points to this
  decision, and notes the M1 fallback. If the endpoint later lands, add the
  row at that wave's matrix update and check it off against the new direct
  implementation.

## Revival path

When `GET /api/users/[username]` lands upstream:

1. Add the row to `docs/api-coverage.md` (User or Public group; auth = None).
2. Add the request builder + DTO to `InterlinedKit.User` (or
   `InterlinedKit.Public` if the live group is `Public`).
3. Swap `SocialService.profile(username:)` to call the direct endpoint and
   populate the full `UserProfile`.
4. Keep `UserProfile.init(fromEmbeddedAuthorOf:)` as a degraded-mode mapper
   for offline / cache scenarios where only an embedded author is on hand.
5. Update this decision's status to "Superseded by 000N" and add the link.
