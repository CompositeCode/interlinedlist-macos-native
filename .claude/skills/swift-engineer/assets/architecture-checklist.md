# Architecture Checklist

Use this checklist before finalizing code changes.

- Responsibilities are separated by layer: UI, domain, networking, persistence.
- Protocol boundaries exist for dependencies that require mocking or substitution.
- No view type owns business rules that should live in domain services.
- Networking logic is isolated from rendering logic.
- Concurrency is explicit and safe (async/await with clear task ownership).
- Error paths are handled and surfaced predictably.
- New code avoids speculative abstractions.
- Naming is clear and behavior-focused.

## Project-specific invariants

- **Decision 0003 — Kit import policy.** `App/Features/**`, `App/Navigation/**`, `App/MenuCommands/**` must not `import InterlinedKit`. Only `App/Composition/AppEnvironment.swift` may. Missing domain models are the cause when the urge arises — add the type to `InterlinedDomain` first.
- **Composition root only.** Service construction lives in `AppEnvironment`. View models receive protocol-typed dependencies; they never construct services.
- **Synchronized folder groups.** App and test targets use `PBXFileSystemSynchronizedRootGroup` so source-file additions stay out of `project.pbxproj`. Preserve this when adding new targets.
- **Optimistic UI rule.** Snapshot → mutate locally → call service → on success replace with server response, on failure restore. Always include a `pendingOperations` debounce set keyed by entity id.
- **Ownership-gated UI.** Hide ownership-gated actions when the current user is unknown; do not render them as disabled.
- **Event bus over refetch.** Cross-window mutation refresh uses an actor-backed pub/sub bus; subscribers apply pure local mutations. `[weak self]` in subscriber tasks; do not rely on `deinit` cancellation under Swift 6 Observation semantics.
- **No SwiftUI view rendering tests.** Test view models; verify views by build + hand-check.
