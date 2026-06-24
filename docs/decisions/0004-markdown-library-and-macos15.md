# Decision 0004 — Markdown library: Textual, with a macOS 15 deployment-target bump

- **Status:** Accepted (2026-06-23)
- **Wave:** Locked in ahead of Wave 5.3 (M4 Documents UI). Recorded by the orchestrator after the Wave 5.1 swift-engineer subagent began running and the user (in auto mode) directed: "pick the top one that is Swift compliant and use it."
- **Supersedes:** PLAN.md §2 "macOS 14 (Sonoma) minimum." PLAN.md is read-only; this decision is the source of truth for the new minimum.

## Context

PLAN.md §1 Documents row and §6 M4 call for a Markdown editor + preview pane. The user confirmed in Phase 5 planning (2026-06-23): "use a third-party SwiftUI-only Markdown editor library." The user also has a load-bearing constraint, captured in user-feedback memory `feedback_swiftui_only.md`: no `import AppKit` anywhere in the App target, and "ask the user before reaching for AppKit when SwiftUI feels insufficient."

The Wave 5.1 agent was launched with the assumption that the App target would gain its **first third-party SPM dependency** in Wave 5.3. Picking it correctly is high-stakes because there has been no precedent and the bar for adding a dependency is high.

## Options considered

Inspected on 2026-06-23 via `gh api` against the live GitHub repositories.

| Library | License | Last release | Last commit | Min macOS | Pure SwiftUI? | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `gonzalezreal/swift-markdown-ui` (`MarkdownUI`) | MIT | 2.4.1 (Oct 2024) | Dec 2025 | macOS 12 | Yes (uses `swift-cmark` C library) | **Disqualified.** Repo description: "Maintenance mode — new development in Textual." |
| `gonzalezreal/textual` (`Textual`) | MIT | 0.5.0 (Jun 15, 2026) | 6 days ago | **macOS 15** | Yes — dependency tree (`swift-concurrency-extras`, `swiftui-math`) has zero AppKit references | **Chosen.** Best architectural fit. |
| `LiYanan2004/MarkdownView` | MIT | 2.7.0 (Jun 2, 2026) | 2 days ago | macOS 12 | **No** — transitively depends on `Highlightr`, which contains `import AppKit` in `Shims.swift`, `Theme.swift`, `Highlightr.swift` | Disqualified on the SwiftUI-only bar even though the App's own files would never `import AppKit`. |
| `JohnSundell/Splash` | MIT | 0.16.0 (Jun 2021) | May 2024 | — | — | Disqualified — stale (5 years since last release) and is a syntax-highlight library, not a Markdown renderer. |
| `apple/swift-markdown` | Apache-2.0 | 0.8.0 (May 2026) | 1 day ago | macOS 13 | N/A — parser only; would require a custom SwiftUI renderer | Disqualified — meaningful sub-project of work, not a drop-in. |

## Decision

Adopt **`gonzalezreal/textual`** (the `Textual` SwiftUI library) as the App target's first third-party SPM dependency, and bump the project's macOS deployment target from **14 (Sonoma) to 15 (Sequoia)**.

## Rationale

1. **The SwiftUI-only constraint is load-bearing** (per user-feedback memory `feedback_swiftui_only.md` and decision 0003's broader "App-target stays in its lane" philosophy). Textual is the only candidate that respects it both at the App's own import surface AND throughout the dependency tree. Allowing `MarkdownView` would require either accepting Highlightr's `import AppKit` in the dep tree, or contorting the build to exclude its syntax highlighting — neither is a clean position.
2. **Textual is the maintainer's own successor to MarkdownUI.** The author put MarkdownUI into maintenance mode explicitly to focus on Textual; choosing the successor avoids being stuck on a library whose own author no longer prioritizes it.
3. **macOS 15 (Sequoia) shipped September 2024 and is over 2 years old** as of this decision (2026-06-23). The user base on Sonoma at this point is small and shrinking. The bump is acceptable for a v1 desktop client.
4. **macOS 15 unlocks platform features we'll want regardless** — newer SwiftUI APIs (improved `Table`, `TextEditor` enhancements, refined `NavigationSplitView` behaviors), better `@Observable` ergonomics, additional Swift 6 strict-concurrency polish.

## Consequences

### Required edits (deferred to Wave 5.3 to avoid clashing with the in-flight Wave 5.1 agent)

1. **App target.** `InterlinedList.xcodeproj/project.pbxproj` — `MACOSX_DEPLOYMENT_TARGET = 15.0` for both Debug and Release configurations of the `InterlinedList` and `InterlinedListTests` targets.
2. **All three SPM packages.** `Packages/InterlinedKit/Package.swift`, `Packages/InterlinedDomain/Package.swift`, `Packages/InterlinedPersistence/Package.swift` — `platforms: [.macOS(.v15)]`.
3. **SPM package dependency added to App target.** Add `https://github.com/gonzalezreal/textual` at the pinned semver range `from: "0.5.0"`. Product: `Textual`. Linked only to the `InterlinedList` app target (not to the SPM packages — they remain zero-dep).
4. **CI workflow.** `.github/workflows/ci.yml` already uses Xcode 16.2 on `macos-15` runners. No change required.
5. **README.md.** Update the badge from "macOS 14+" to "macOS 15+" and adjust the prose in the About / Building sections.
6. **docs/progress.md.** The Wave 5 entry should note the deployment-target bump under "decisions" with a back-reference to this file.

### Risk register

- **Textual is on 0.5.0**, not 1.0. Public API may move. Mitigation: pin to a semver range that disallows minor-version bumps (`.upToNextMinor(from: "0.5.0")`) and treat any upgrade as a deliberate change.
- **Macros / private SwiftUI APIs.** Textual uses `swiftui-math` (also gonzalezreal). Both libraries' public surface is pure SwiftUI; if a build-time error arises from a private API change, fall back to Textual `<=0.5.0` and revisit.
- **No `feedback_swiftui_only.md` violation expected**, but the `App/**` AppKit grep at every wave gate still applies as the safety net.

### Out of scope of this decision

- App Store distribution implications. None — distribution is `.pkg` per `project_distribution_model.md` memory, and the deployment-target bump doesn't change that path.
- iOS support. The project is macOS-only; no iOS deployment target exists.
- Reverting if Textual fails. Documented fallback: build a custom SwiftUI renderer on `apple/swift-markdown` (the "option C" from the original evaluation). Significant work but cleanly possible. Not in scope unless Textual is actually rejected during Wave 5.3 implementation.

## Implementation plan

Wave 5.3 task prompt to the swift-engineer subagent **must** include this decision file as required reading, plus explicit steps:

1. Bump all four deployment-target locations atomically (xcodeproj + three Package.swift files) as the first commit-able unit, with `xcodebuild build` verified green before moving on.
2. Add the Textual SPM dependency to the App target via pbxproj edit. Verify with `xcodebuild -resolvePackageDependencies`.
3. Use Textual's `Textual(_:)` view (or whatever the current public entry point is named) for the document-preview pane. Editor pane stays as a vanilla SwiftUI `TextEditor`.
4. Update README badges + the Building section in the same wave.
5. Update `feature-status.md` Limits section under "What's coming" to drop any "macOS 14" assumption.
