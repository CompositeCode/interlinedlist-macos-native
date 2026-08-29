# CLAUDE.md — InterlinedList (native macOS)

Native macOS **SwiftUI** client for InterlinedList: Xcode project `InterlinedList.xcodeproj` (scheme `InterlinedList`) + three SPM packages + a menu-bar `SyncAgent/`.

- `App/` — SwiftUI app target (features, navigation, composition root)
- `Packages/InterlinedKit` — API/network, DTOs, auth (Keychain)
- `Packages/InterlinedDomain` — domain models + services; DTO→domain mappers
- `Packages/InterlinedPersistence` — SwiftData stores + on-disk cache
- `SyncAgent/` — background menu-bar doc-sync utility

Master planning doc: `work-consolidation.md`. Detailed checklists live in `.claude/skills/*/assets/` (the single source of truth).

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
- `grep -rn "import InterlinedKit" App/Features App/Navigation App/MenuCommands` → zero hits

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
