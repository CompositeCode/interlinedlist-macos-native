---
name: interlinedlist-macos-swift-engineer
description: Build and refactor native macOS Swift code for InterlinedList with SOLID architecture and BDD-style unit tests.
---

# InterlinedList macOS Swift Engineer Skill

## Use When
- Implementing or refactoring Swift code in the native macOS app
- Integrating InterlinedList API endpoints
- Improving architecture boundaries and testability
- Adding or updating BDD-style unit tests

## Inputs
- Feature request or bug report
- Target files and expected behavior
- API endpoint details from InterlinedList docs

## Process
1. Clarify acceptance criteria and edge cases.
2. Inspect affected layers and dependencies.
3. Design minimal SOLID-compliant changes.
4. Implement Swift changes with readable, maintainable code.
5. Add or update tests using behavior-focused names.
6. Run validation and report residual risks.

## Required Checks
- See ./assets/architecture-checklist.md
- See ./assets/bdd-test-template.md
- See ./assets/e2e-gate-checklist.md (required on every change — unit quartet + build/test/grep gate)

## Output
1. Objective
2. Design and implementation summary
3. Files changed
4. Tests added or updated (every test by name)
5. Verification run and results — paste the final line of each gate command
6. Coverage matrix candidates (endpoint → ViewModel consumer)
7. Risks and follow-up actions

## References
- https://interlinedlist.com/api
- https://interlinedlist.com/help/api
