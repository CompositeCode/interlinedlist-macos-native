# .claude — Project Customization

Project-specific Claude Code configuration: subagents and skills. Repo-wide rules and the verification gate live in the root [`CLAUDE.md`](../CLAUDE.md); the detailed checklists in `skills/*/assets/` are the single source of truth (agents and skills point to them rather than duplicating).

Only `README.md`, `agents/`, and `skills/` under `.claude/` are version-controlled (see `.gitignore`); everything else — including `worktrees/` — is local-only.

## Agents (`agents/`)

Subagents Claude spawns via the Agent tool for delegated, focused work. Each file needs YAML frontmatter (`name`, `description`).

| File | Registered name | Purpose |
|------|-----------------|---------|
| `swift-engineer.md` | `interlinedlist-macos-swift-engineer` | Native macOS Swift features, API integration, SOLID architecture, BDD tests |
| `doc-engineer.md` | `interlinedlist-documentation-engineer` | Engineering, user, and repository documentation across audience tracks |

## Skills (`skills/`)

Slash commands invoked by the user or Claude via the Skill tool. Each has a `SKILL.md` with YAML frontmatter; engineering/docs skills add an `assets/` folder of checklists and templates.

| Skill | Assets |
|-------|--------|
| `swift-engineer/` | `architecture-checklist.md`, `bdd-test-template.md`, `e2e-gate-checklist.md` |
| `doc-engineer/` | `docs-track-matrix.md`, `docs-quality-checklist.md` |
| `comment-and-commit/` | Surgical, worktree-aware commit of only the files you changed. No push. |
| `comment-commit-and-pr/` | Same, then push and open a PR **against `dev`** via `gh`. |

## Conventions baked into these

- **Verification is pivotal.** Every engineering change runs the E2E gate; every docs change runs the docs quality gate. Nothing is "done" until verified and reported.
- **Worktrees for non-trivial work.** Use `git worktree add .claude/worktrees/<task-id> …` (git-ignored) so concurrent sessions can't revert each other's trees. The commit/PR skills assume this.
- **Git flow.** feature → `dev` → `main`. The user owns every push and merge to the remote.

## InterlinedList references

- https://interlinedlist.com
- https://interlinedlist.com/api
- https://interlinedlist.com/help/api
