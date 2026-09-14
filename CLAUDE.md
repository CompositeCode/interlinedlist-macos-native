# CLAUDE.md — InterlinedList (native macOS)

Native macOS **SwiftUI** client for InterlinedList: Xcode project `InterlinedList.xcodeproj` (scheme `InterlinedList`) + three SPM packages + a menu-bar `SyncAgent/`.

- `App/` — SwiftUI app target (features, navigation, composition root)
- `Packages/InterlinedKit` — API/network, DTOs, auth (Keychain)
- `Packages/InterlinedDomain` — domain models + services; DTO→domain mappers
- `Packages/InterlinedPersistence` — SwiftData stores + on-disk cache
- `SyncAgent/` — background menu-bar doc-sync utility

**Master planning doc: `work-consolidation.md` — THE single source of truth.** It owns the plan:
ordering, architecture, probe evidence, API shapes, the re-measure log, the release path, and a work
index (§1f) mapping every item to its GitHub issue. **GitHub issues own execution** — live status,
and what PRs link to. Epic #66 is a pointer to the doc, not a second backlog. When the doc and an
issue disagree, the issue wins and the doc gets corrected.

⚠️ **Same-PR doc-sync rule.** A PR that ships a `G`-item, closes a parity issue, or moves the test
baseline **must update `work-consolidation.md` in the same PR**. Seven PRs (#67–#73) once shipped
without it moving; it drifted ~330 tests and two API re-measures behind the code.

Detailed checklists live in `.claude/skills/*/assets/`. `docs/progress.md` is **archived** (M0–M7 build
journal, last updated 2026-06-25) — do not cite it as current.

## Non-negotiable rules

- **SwiftUI only in the App target.** No AppKit / `NSViewRepresentable` in `App/**` — ask first if you think you need it.
- **Decision 0003 — no Kit imports in features.** `App/Features/**`, `App/Navigation/**`, `App/MenuCommands/**` must never `import InterlinedKit`; only `App/Composition/AppEnvironment.swift` may. Missing a domain model is the real cause — add it to `InterlinedDomain` first.
- **Layered + protocol-driven.** Keep UI / domain / networking / persistence separated; inject protocol-typed dependencies; `async/await` for all I/O.
- **Xcode file hygiene.** Source folders use `PBXFileSystemSynchronizedRootGroup`; adding files must not touch `project.pbxproj`.

## Verification is mandatory — not optional

No change is "done" until the gate in `.claude/skills/swift-engineer/assets/e2e-gate-checklist.md` passes and the results are reported. Never claim a result you did not observe. Minimum, every change:

- `xcodebuild -scheme InterlinedList -destination 'platform=macOS' build` → `** BUILD SUCCEEDED **`
- `xcodebuild -scheme InterlinedList -destination 'platform=macOS' test` (App target)
- `swift test --package-path Packages/{InterlinedKit,InterlinedDomain,InterlinedPersistence}`
- `grep -rnE "^[[:space:]]*(@[A-Za-z]+ )?import InterlinedKit" App/Features App/Navigation App/MenuCommands` → zero hits *(anchored: the unanchored form matches prose comments and reports four false positives)*

Ship the BDD unit-test quartet (happy / invalid / upstream-failure / boundary) with every behavior change. Docs work has its own gate: `.claude/skills/doc-engineer/assets/docs-quality-checklist.md`.

## Git flow

- Feature branch → **`dev`** (integration) → **`main`** (downstream / release).
- **The user owns every push and merge to the remote.** Commit freely; never `git push` or merge to the remote without an explicit ask.
- Do non-trivial work in a git **worktree** (`.claude/worktrees/<task-id>`, already git-ignored) so a concurrent session's branch switch can't revert your tree.
- Commit/PR helpers: `/comment-and-commit`, `/comment-commit-and-pr`.

## Agents & skills (`.claude/`)

- `swift-engineer` (agent + skill) — macOS Swift features, SOLID, BDD tests, the E2E gate.
- `doc-engineer` (agent + skill) — engineering / user / repo docs, kept in separate tracks.
- Checklists (source of truth): `.claude/skills/*/assets/`.
