# 0003 — App-layer Kit-import policy (explicit imports over re-export)

- **Status:** Accepted (2026-06-22)
- **Date:** 2026-06-22
- **Context:** PLAN.md §3 (Architecture / package boundaries — "DTOs never cross into the UI; domain models do"); `docs/progress.md` Wave 2 deviation #1 (latent kit-import compile failure surfaced when `SidebarDetailDispatcher` first routed `.profile` to `ProfileRootView`); decisions 0001 (auth transport) and 0002 (public-profile fallback).
- **Supersedes / superseded by:** —

## Context

Wave 2 wired the App layer's `ProfileRootView`, `ProfileHeaderView`, and
`ProfileViewModel` against `SocialServicing` from `InterlinedDomain`. These
view files also reference `FollowCountsDTO`, which lives in `InterlinedKit`.
While `.profile` was still routed to a placeholder in
`SidebarDetailDispatcher`, the App target never compiled the new files and
the missing `import InterlinedKit` went unnoticed. As soon as Wave 2 flipped
the dispatcher to `ProfileRootView()`, the build failed with "cannot find type
`FollowCountsDTO` in scope" in all three files. The recorded fix (add
`import InterlinedKit` to the leaf files) cleared the build, but
`docs/progress.md` Wave 2 deviation #1 flagged that the *policy* question —
"should App-layer files have to know which package owns each type?" — is
unresolved and needs a Wave 3 decision before any more App↔Domain wiring
ships.

Two options were on the table:

- **Option A — Explicit imports at every consumer.** App-layer files that
  reference any `InterlinedKit.*` symbol must declare `import InterlinedKit`
  themselves. `InterlinedDomain` re-exports nothing.
- **Option B — Re-export from Domain.** `InterlinedDomain` adds
  `@_exported import InterlinedKit` so any consumer that imports Domain
  transitively sees the entire `InterlinedKit` public surface. App files do
  not need to know whether a given type lives in Domain or Kit.

## Decision

**Adopt Option A — explicit imports.** App-layer files that reference a Kit
symbol must declare `import InterlinedKit` themselves. `InterlinedDomain`
re-exports nothing.

The simultaneous correction is **to remove the need for those imports
wherever a domain value can carry the data instead**: each App-layer file
that currently `import InterlinedKit` is treated as an open ticket to
introduce a domain model that hides the DTO. As of this decision, exactly
three App files had `import InterlinedKit` — all in `App/Features/Social/`,
all for `FollowCountsDTO`. They are converted in this same change to consume
a new `FollowCounts` domain value (see "Immediate refactor" below).

## Rationale

1. **PLAN.md §3 boundary.** The plan is explicit that "DTOs never cross into
   the UI; domain models do." `@_exported import InterlinedKit` from Domain
   would mechanically erase that boundary — every Kit DTO would be visible
   from every App file with no friction. The Domain layer's job is to be
   the App's vocabulary; re-exporting the wire types undermines that job in
   the cheapest possible way.
2. **The Wave 2 deviation was a useful signal, not a usability bug.** The
   compile failure on `FollowCountsDTO` was the type system telling us a
   domain model was missing. Option B would have hidden the signal; Option A
   surfaces it at the leaf, exactly where the missing-domain-model decision
   has to be made. We *want* "I had to import Kit from a view" to feel
   wrong, because it almost always means a `FollowCounts` / `Visibility` /
   `MessageDraft` is missing from `InterlinedDomain`.
3. **Cost asymmetry.** Adding `import InterlinedKit` to a leaf file is a
   one-line, IDE-autosuggested fix. Adopting `@_exported import` is a
   permanent architectural change that affects every future App file
   forever. The asymmetric cost of reversal weighs against B.
4. **Test-target hygiene.** Domain test targets already `import InterlinedKit`
   directly (they need `APIError`, `MessageDTO`, etc. as test inputs). That
   pattern is consistent across packages and is a well-established Swift
   idiom; codifying the same rule for the App target keeps the project
   uniform.
5. **`@_exported` is an underscored attribute.** `@_exported import` is a
   Swift compiler internal that has no stability guarantee. Building the
   project's public-import shape on top of an underscored feature is a small
   but real risk we have no reason to take.

## Consequences

- **The new rule (enforced by convention, checked in code review).** Any
  App-layer file that references a `InterlinedKit.*` symbol must declare
  `import InterlinedKit` itself. `InterlinedDomain` declares no
  `@_exported` imports. If a reviewer sees `import InterlinedKit` in a
  `App/Features/**` file, that import is also a TODO to introduce a domain
  model — the file should not be the long-term home of the Kit reference.
- **Immediate refactor (lands in this slice).** The three App files that
  currently `import InterlinedKit` for `FollowCountsDTO` are converted to
  consume a new `FollowCounts` domain value. A `FollowMappers.swift` in
  `InterlinedDomain/Models/` maps `FollowCountsDTO → FollowCounts`.
  `SocialServicing.counts(of:)` returns `FollowCounts`, not `FollowCountsDTO`.
  After this change, no App-layer file in the repo imports `InterlinedKit`
  for view rendering.
- **Test impact.** `SocialServiceTests.test_givenUserHasFollowers_…` and
  `test_givenBrandNewUser_…` already assert on `.followerCount` /
  `.followingCount` properties that exist on both DTO and domain value,
  so the rename is type-only at those call sites.
- **No `@_exported import` anywhere.** This decision applies project-wide:
  no package re-exports another package's public surface.

## Follow-up actions

- **Wave 5 (Social).** When the upstream `GET /api/users/[username]`
  endpoint lands and decision 0002 is superseded, ensure the richer
  `UserProfile` it returns continues to fold follower / following counts
  through the `FollowCounts` domain value rather than re-introducing the
  DTO at the view layer.
- **Wave-gate checklist.** Each wave's documentation update should grep
  `App/**` for `import InterlinedKit` and treat any new hit as a deviation
  to be recorded — and, by default, refactored away by introducing the
  missing domain model.
- **`api-coverage.md`.** No coverage rows change for this decision (no
  endpoints added or removed); the follow row counts that already flipped
  in Wave 2 remain ☑.

## Revisit triggers

If any of the following occurs, this decision should be revisited:

- More than three App-layer files end up needing to `import InterlinedKit`
  in a single wave — the boilerplate cost has stopped being negligible, or
  the Domain layer is systematically failing to cover the App's needs.
- A future Domain service exposes a DTO directly because translating it
  would be lossy or impractical. That would be a smell worth recording
  before it spreads.
