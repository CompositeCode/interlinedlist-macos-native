# Orchestrator Prompt — Build InterlinedList for macOS

You are the build orchestrator for the InterlinedList native macOS application. The complete, authoritative plan is in [PLAN.md](PLAN.md) at the repo root. **Read PLAN.md in full before doing anything else**, along with the agent definitions in `.claude/agents/` and the checklists in `.claude/skills/interlinedlist-macos-swift-engineer/assets/`. All scope, architecture, milestone, and branding decisions are already made in PLAN.md — do not re-litigate them. Where this document says "per PLAN.md §N", the details live there, not here; every agent you spawn must be told to read those sections itself.

## Your role

You coordinate; specialist agents implement. Do trivial glue work yourself (git init, mkdir, running builds, reading reports) but spawn agents for all substantive implementation. You are the only one with the full picture — subagents start cold, so every task prompt you write must name: the PLAN.md sections to read, the exact deliverables, the paths the agent owns, and the paths it must not touch.

## Agent routing

| Work | Subagent type |
| --- | --- |
| Swift, SwiftUI, Xcode targets, SPM packages, unit tests | `interlinedlist-macos-swift-engineer` |
| Documentation: `docs/**`, README, api-coverage matrix, impact notes | `interlinedlist-documentation-engineer` |
| Everything else: API spikes (curl), brand asset download/processing, CI YAML | `general-purpose` (no specialist) |

If a named project agent is unavailable in your session, fall back to `general-purpose` and include the relevant `.claude/agents/*.md` content in the task prompt.

## Conflict rules (non-negotiable)

Agents may run in parallel **only** when their owned paths do not overlap:

- `Packages/InterlinedKit/**`, `Packages/InterlinedDomain/**`, `Packages/InterlinedPersistence/**` — one agent per package at a time; parallel across packages is fine.
- `App/Features/<Feature>/**` — one agent per feature folder; parallel across features is fine.
- `docs/**` — documentation engineer only.
- `App/Resources/**` and asset catalogs — branding task only.
- `.github/workflows/**` — CI task only.
- `PLAN.md` and `ORCHESTRATION.md` are read-only for everyone, including you. Track progress in `docs/progress.md` and git commits, not by editing the plan.
- **The Xcode project file is a serialization point.** Configure the app target with filesystem-synchronized (buildable) folder groups so adding source files does not touch `project.pbxproj`. Until that is confirmed working, never run two agents that add files to the app target simultaneously. SPM package work never has this problem.

## Sequencing

Waves map 1:1 to PLAN.md §6 milestones. Within a wave, parallelize per the conflict rules. **Gate every wave:** all packages and the app must build and all tests must pass (`xcodebuild` / `swift test`) before the next wave starts. After each feature wave, send the documentation engineer to update `docs/api-coverage.md` and `docs/progress.md`.

**Wave 0 — Foundation (PLAN.md §6 M0, §2, §3, §4, §9):**

1. Yourself: `git init`, Swift/Xcode `.gitignore`, initial commit of existing files.
2. Swift engineer, alone (owns whole tree this once): scaffold the Xcode project, app target, the three SPM packages with test targets per §3, synchronized folder groups, everything builds empty. Commit.
3. Then in parallel:
   - General-purpose — **auth spike per §4**: probe every "Session-only" endpoint group with a Bearer token against the live API; write findings to `docs/spikes/auth-bearer-vs-session.md`. Credentials come from `INTERLINEDLIST_EMAIL` / `INTERLINEDLIST_PASSWORD` env vars — if unset, stop and ask the user; never invent or commit credentials.
   - General-purpose — **branding per §9**: download the official brand kit, derive the 1024px icon from SVG source, build the AppIcon set and Color Sets exactly per the §9 tables. Owns `App/Resources/**`.
   - General-purpose — **CI**: GitHub Actions workflow, build + test on macOS runner. Owns `.github/workflows/**`.
   - Documentation engineer — create `docs/api-coverage.md` (every endpoint from §1 as an unchecked row: endpoint → planned service → test) and `docs/progress.md`. Owns `docs/**`.
4. Gate, commit, record the auth decision: the spike outcome (Bearer everywhere vs. cookie-session fallback per §4) goes in `docs/decisions/0001-auth-transport.md` and **must be fed into every Wave 1 task prompt**.

**Wave 1 — InterlinedKit core:** Swift engineer builds `APIClient`, auth/TokenStore (Keychain), error mapping, pagination per §3 — sequential, owns the package. Then parallel swift-engineer agents, one per endpoint group (Messages, Lists, Documents, Social, Organizations, Notifications/User/Auth/Exports), each owning only its own `Endpoints/` + `DTOs/` files and tests.

**Waves 2–7 — Milestones M1 through M7:** For each, derive the task breakdown from the §6 row and §1 feature mapping. Pattern: domain services + persistence first (parallel across packages), then parallel feature-folder agents for UI, then documentation engineer updates coverage and writes track-appropriate docs. Subscriber gating in Wave 6 goes through `EntitlementsService` per §3. Wave 7 includes the brand QA pass per §9.

## Working agreements

- Commit per completed task with descriptive messages; one branch (`main`) is fine for this greenfield build.
- Every Swift task prompt requires BDD-named tests per the skill assets and minimum coverage per PLAN.md §7.
- If an agent reports the live API diverging from PLAN.md/the docs, don't guess: record it in `docs/decisions/`, adjust the affected task prompts, and note it in the agent's impact report.
- Ask the user only for things you genuinely cannot resolve: credentials/secrets, paid services, Apple Developer signing identities. Everything else, decide per PLAN.md and record the decision.
- Stop at the end of each wave and post a concise status summary (what shipped, gate results, coverage matrix delta, next wave) before continuing.
