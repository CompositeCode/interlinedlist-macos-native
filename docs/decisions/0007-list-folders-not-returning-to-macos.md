# 0007 — List folders do not return to macOS

- **Status:** Accepted (2026-09-13)
- **Date:** 2026-09-13
- **Decided by:** the repository owner, on [GitHub issue #49](https://github.com/CompositeCode/interlinedlist-macos-native/issues/49)
- **Context:** PR #19 (`refactor/lists-remove-list-folders`, merged 2026-09-06) removed the List Folders feature from the macOS client on the understanding that it had been retired platform-wide. The 2026-09-07 parity sweep established that it had **not** been.
- **Supersedes / superseded by:** re-opens and closes the old **G6**.

## Context

List folders are a **live, documented, current web feature**. Verified live on
2026-09-07:

```
GET    /api/folders   → 200  {"folders":[]}
POST   /api/folders          (subscribers only)
PUT    /api/folders/{id}
DELETE /api/folders/{id}
```

`/help/lists` documents them in detail — arbitrary nesting, 1–80 character names
unique among siblings, no-move-under-your-own-descendant, and a delete that
cascades to subfolders while re-parenting their lists to the root. Every list row
on the wire carries a `folderId`.

So after PR #19 the macOS client has a **one-way divergence**: lists organised
into folders on the web appear flat on the Mac, and a `folderId` set elsewhere is
invisible and uneditable here.

Two positions were defensible:

- **Rebuild it.** The web ships it and the API serves it; restore parity.
- **Keep the divergence deliberately.** macOS already has owned-list
  `parentID` parent/child nesting — untouched by PR #19 and still shipping —
  which covers much of the same organising need.

What was *not* defensible was the state as found, where the divergence was
undocumented and read as an oversight.

## Decision

**macOS does not rebuild list folders.** The divergence is deliberate. The web
keeps its folder tree; the Mac organises lists with parent/child nesting.

## Consequences

**The capability gate ships 11 cases, not 12.** The `fix/account-status-gating`
branch carried a `.listFolderCreation` case in both `GatedAction` and `Feature`,
written while the client still had the feature. It was dropped before that branch
merged as PR #83. A gate for a capability the client does not have is dead code
that reads like a promise.

**Parent/child list nesting is a different feature and is unaffected.** It was
never removed, it is not folders, and a future sweep should not conflate them.

**A list's `folderId` is preserved, not managed.** macOS neither reads nor writes
it, and must not clear it — a list filed into a folder on the web stays filed
there after a macOS edit. (`UpdateListRequest` carries no `folderId`, so this
holds by construction today; anything that adds one must keep it.)

**Issue #49 stays open on purpose**, labelled `wontfix`, as the standing product
record. Closing it would make the divergence look like an oversight again, which
is the exact failure this decision exists to prevent.

## Notes

GitHub issue **#28** ("New Folder still shows up in Lists") was closed as stale
against a pre-PR-#19 binary. That was correct and is unrelated: #28 was about a
*leftover control*, this is about the *absent feature*.
