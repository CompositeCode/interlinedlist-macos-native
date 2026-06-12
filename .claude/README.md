# .claude — Project Customization

This folder contains project-specific Claude Code configuration: subagents and skills.

## Agents (`agents/`)

Subagents that Claude spawns via the Agent tool for delegated, focused work. Each file needs YAML frontmatter (`name`, `description`) so Claude Code registers it.

| File | Purpose |
|------|---------|
| `interlinedlist-macos-swift-engineer.md` | Native macOS Swift implementation, API integration, SOLID architecture, BDD tests |
| `interlinedlist-documentation-engineer.md` | Engineering, user, and repository documentation across audience tracks |

## Skills (`skills/`)

Slash commands invoked by the user or Claude via the Skill tool (e.g. `/interlinedlist-macos-swift-engineer`). Each skill has a `SKILL.md` with YAML frontmatter and an `assets/` folder for reference checklists and templates.

| Skill | Assets |
|-------|--------|
| `interlinedlist-macos-swift-engineer/` | `architecture-checklist.md`, `bdd-test-template.md` |
| `interlinedlist-documentation-engineer/` | `docs-track-matrix.md`, `docs-quality-checklist.md` |

## Agents vs Skills

- **Agents** are subagents Claude spawns to handle complex, delegated tasks autonomously.
- **Skills** are invocable workflows triggered explicitly by the user or Claude as a slash command.

Both serve the same two roles (Swift engineering, documentation) but at different invocation levels.

## InterlinedList References

- https://interlinedlist.com
- https://interlinedlist.com/api
- https://interlinedlist.com/help/api
