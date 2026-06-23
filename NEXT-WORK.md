# Next-work follow-ups (blocked on upstream)

**Audience:** the macOS app maintainers (orchestrator + implementing agents).

Work that is fully designed on the macOS side but cannot ship until an upstream change lands. Each entry pins the trigger (what unblocks it) and where the design already lives so the work can be picked up cold.

When picking an item up:

1. Re-verify the trigger has actually landed (don't trust the entry &mdash; probe the live API).
2. Read the referenced design notes / decision records.
3. Update the entry to `Status: in flight` with a date, and remove it when shipped.
4. If the trigger was solved differently than predicted, capture the deviation in `docs/progress.md` under the consuming wave.

---

## NW-1 &mdash; Watcher invite flow (Phase 4 / M3 Lists)

- **Status:** Blocked on upstream API.
- **What ships in M3 instead:** Role editor for users who are *already* watching a list (rename/promote/demote/remove). No invite-a-new-user UX.
- **Trigger to resume:** `GET /api/users/lookup?handle=…` or `GET /api/users/search?q=…` lands on interlinedlist.com. The ask is filed in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) item 1.5.
- **Design already in place:**
  - `InterlinedDomain.ListsService.setWatcher(listId:userId:role:)` already covers the PUT once a `userId` is known.
  - `WatcherRole.swift` enumerates the role taxonomy with `WatcherRole.other(String)` preserving unknown wire values.
- **Work to do once unblocked:**
  1. Add a `UsersService.lookup(handle:)` or `.search(query:limit:)` method in `InterlinedDomain` (whichever shape lands).
  2. Wrap it in a SwiftUI share-sheet view in `App/Features/Lists/Sharing/`:
     - "Add a user…" text field with debounced autocomplete (if `search`) or Enter-to-resolve (if `lookup`).
     - Role picker drop-down using `WatcherRole`.
     - Confirm button → `ListsService.setWatcher(listId:userId:role:)`.
     - Inline error rendering for "user not found" / "user is private" / "user already watching".
  3. Add BDD-named unit tests against the new service method.
  4. Flip the relevant `docs/api-coverage.md` row.
- **Estimated size:** Small &mdash; one new domain method, one new SwiftUI view, ~6-8 tests. Half-day of focused work once the endpoint exists.

---

## How to add an entry

Each entry needs: a unique ID (`NW-N` where `N` increments), the trigger, the deferred-design pointer, and the picked-up steps. Keep entries terse &mdash; this file is a worklist, not documentation.
