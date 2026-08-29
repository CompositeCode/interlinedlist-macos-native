---
name: comment-commit-and-pr
description: Add in-code comments to the files you changed this session, commit ONLY those files (surgical — never `git add -A`), push the branch, and open a GitHub PR against `dev` via the gh CLI. Prefers working inside a git worktree. Use when the user wants to document, commit, and raise a PR for the current work.
allowed-tools: Bash, Read, Edit, Grep, Glob
---

# Comment, Commit, and PR

This is `comment-and-commit` followed by a push and a `gh` pull request. **PRs target `dev`** (the integration branch), never `main` — `main` is downstream and only advances when `dev` is merged into it.

> Pushing and opening a PR are outward-facing actions. Because the user owns pushes and merges, only run this skill when the user explicitly asked to raise a PR (that is the authorization). Make sure the commit and branch are correct first.

## Work in a worktree

Do non-trivial work inside an isolated worktree so a concurrent session can't revert your tree or move `HEAD` out from under a push:

```bash
git worktree add .claude/worktrees/<task-id> -b feature/<short-topic> dev
```

`.claude/worktrees/` is git-ignored. (`EnterWorktree` / `Agent(isolation:"worktree")` do this natively.) A worktree also removes the "am I on the right branch, did someone switch it?" hazard entirely.

## Prerequisites

```bash
which gh && gh auth status
```

If `gh` is missing or unauthenticated, stop and tell the user (`brew install gh`, `gh auth login`, ensure `repo` scope). Confirm an `origin` remote exists (`git remote -v`).

## Steps

1. **Comment and commit.** Perform the full `comment-and-commit` workflow: survey, build `MINE`, reconcile against `DIRTY` (stop on any conflict with work you didn't make), add comments where they add value, stage explicit paths only, and commit with a Conventional Commits message ending in:

   ```
   Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
   ```

2. **Verify — required before shipping.** Run the E2E gate in `.claude/skills/swift-engineer/assets/e2e-gate-checklist.md` (build + App-target test + the three package suites + Decision-0003 grep) and capture the result lines for the PR body. If the gate fails, stop and report — do not open a PR on red. For a large change, you may delegate this to the `swift-engineer` agent.

3. **Confirm the branch.** Never PR from `dev` or `main`. If the commit landed on either, move it to a `feature/<short-topic>` branch first.

4. **Sync feature branch onto `dev`.** `git fetch origin`, then if the branch is behind `origin/dev`, `git merge --no-edit origin/dev`. On conflicts: stop, list them, ask the user.

5. **Push.** If the branch has an upstream, `git push`; otherwise `git push -u origin <branch>`. Never force-push. If rejected for divergence, stop and ask — do not rebase or reset.

6. **Check for an existing PR.** `gh pr view --json number,url,state` — if one exists, report it and don't duplicate.

7. **Open the PR against `dev`.**

   ```bash
   gh pr create --base dev --head <branch> \
     --title "<subject ≤72 chars>" \
     --body "$(cat <<'EOF'
   ## Summary
   <2–4 sentences: what changed and why>

   ## Changes
   - <area>: <what changed and why>

   ## Verification
   - <paste the final line of each E2E gate command run in step 2>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )"
   ```

   Only fall back to `main` if `origin/dev` does not exist on the remote, and say so explicitly in the report.

8. **Report.** Print the commit hash & subject, push result, PR URL, and the verification summary.

## Constraints

- Always PR against `dev` (fall back to `main` only if `dev` is absent from the remote — call it out).
- `git add -A` / `git add .` / `git commit -a` are forbidden — stage explicit paths only.
- Never force-push, amend a published commit, rebase/reset to resolve divergence, or use `--no-verify` — stop and ask instead.
- **Never merge the remote `dev`/`main` yourself.** The PR is the mechanism that updates the remote; the user owns the merge. (A *local-only* merge-back of your feature branch into local `dev` to unblock the next branch is fine only if the user asks — never push it.)
- Never commit secrets or open a duplicate PR. Confirm first if the diff is >500 lines or touches CI/CD, entitlements, or signing.
