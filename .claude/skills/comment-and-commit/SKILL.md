---
name: comment-and-commit
description: Add clear in-code comments to the files you changed this session, then commit ONLY those files (surgical — never `git add -A`) with a well-formed Conventional Commits message. Prefers working inside a git worktree. Does not push or open a PR. Use when the user wants to document and commit the current work.
allowed-tools: Bash, Read, Edit, Grep, Glob
---

# Comment and Commit

Document your pending changes in-code, then commit **only the files you changed this session**. Do not push and do not open a PR — that is `comment-commit-and-pr`.

## Work in a worktree

The durable protection against concurrent sessions is a git worktree. The primary checkout has one `HEAD` and one working tree, so another session switching branches can silently revert your files. If this task is more than a trivial edit, do it inside an isolated worktree and run this skill from there:

```bash
git worktree add .claude/worktrees/<task-id> -b feature/<short-topic> dev
```

`.claude/worktrees/` is git-ignored. (The harness `EnterWorktree` tool and `Agent(isolation:"worktree")` do the same thing natively — use either.) Inside your own worktree the branch is yours alone, and the surgical-staging dance below becomes a safety net rather than the primary defense.

## Steps

1. **Survey the changes.** Run `git status --porcelain` and `git diff HEAD` (and `git log --oneline -10` for message style). If nothing changed, stop and say so.

2. **Build your change set (`MINE`).** From your own actions this session, write the explicit list of files you created/modified — including side effects (formatters, generated files, lockfiles). If you are not confident you changed a file, it is **not** in your set.

3. **Reconcile against the working tree.** Let `DIRTY` = paths from `git status --porcelain`.
   - `TO_COMMIT = MINE ∩ DIRTY` — what you will stage.
   - `FOREIGN = DIRTY − MINE` — another session's or the user's work. Leave it completely untouched (its mere presence is **not** a conflict).
   - **Stop and ask** if: a `TO_COMMIT` file contains hunks you don't recognize; any tracked file has conflict markers (`<<<<<<<`); attribution is ambiguous; or `FOREIGN` files are already staged.

4. **Add comments where they add value.** Edit only the changed regions, and only where a comment earns its place:
   - Public declarations get doc comments (`///` for Swift, matching the file's existing style).
   - Non-obvious logic, workarounds, invariants, and "why" decisions get a brief inline comment.
   - Do **not** restate what the code plainly says or comment trivial accessors. Match existing comment density; under-comment rather than over-comment. Keep edits surgical — no reformatting.

5. **Verify before committing.** Don't commit unverified work. Run the relevant slice of `.claude/skills/swift-engineer/assets/e2e-gate-checklist.md` (at minimum the build + affected tests; the Decision-0003 grep if you touched `App/**`). If it can't pass, fix it or tell the user — don't commit red.

6. **Branch if needed.** If you're on `dev` or `main`, create a focused `feature/<short-topic>` branch before committing (skip if you're already on a feature branch or in a worktree whose branch is yours).

7. **Stage explicitly and commit.** `git add -- <file …>` for exactly `TO_COMMIT` (never `git add -A` / `.` / `commit -a`). Re-check `git status --porcelain` so the index holds only your files; unstage any stray foreign path. Commit with a [Conventional Commits](https://www.conventionalcommits.org/) message (imperative subject ≤72 chars, short body for "why") ending with:

   ```
   Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
   ```

   (The harness appends the `Claude-Session:` trailer automatically.)

8. **Report.** Print the commit hash, branch, one-line subject, the verification result, and — if any `FOREIGN` files were intentionally left uncommitted — name them so the user knows they were preserved, not lost.

## Constraints

- `git add -A`, `git add .`, and `git commit -a` are forbidden — stage explicit paths only.
- Never `git push`, merge to the remote, amend a published commit, or force-push from this skill. **The user owns pushes and merges.**
- Never use `--no-verify`; fix hook failures and make a new commit.
- Never commit secrets (`.env`, `*.secrets`, credentials) or build artifacts.
- Confirm first if your diff is very large (>500 lines) or touches CI/CD, entitlements, or signing.
