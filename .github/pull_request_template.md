## Summary

<!-- One or two sentences. What changed and why. -->

## Plan / wave reference

<!-- Cite the PLAN.md milestone or ORCHESTRATION.md wave this PR lands work for. -->

- PLAN.md §
- Wave / milestone:

## Path ownership

<!-- Which top-level paths does this PR touch? Confirm conflict rules from ORCHESTRATION.md held. -->

- [ ] Touches only one of `Packages/InterlinedKit/**`, `Packages/InterlinedDomain/**`, `Packages/InterlinedPersistence/**` per agent (or one App feature folder)
- [ ] No edits to `PLAN.md` or `ORCHESTRATION.md` (read-only)

## Tests

- [ ] Unit tests added/updated with BDD-style names (`test_givenX_whenY_thenZ`)
- [ ] `swift test --package-path Packages/<pkg>` passes locally
- [ ] `xcodebuild -scheme InterlinedList -destination 'platform=macOS' build test` passes locally

## Docs

- [ ] `docs/api-coverage.md` updated if endpoint coverage changed
- [ ] `docs/progress.md` updated if a wave gate moved
- [ ] New decision recorded under `docs/decisions/` if architecture changed
