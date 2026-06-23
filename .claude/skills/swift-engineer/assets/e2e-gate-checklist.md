# E2E Gate Checklist

Run on every change before declaring done. Not optional. Paste the final line of each command into the report.

## Unit-test quartet (per behavior)

Every changed behavior ships with at least four BDD-named cases:

1. **Happy path** — canonical success.
2. **Invalid input** — rejected before the service is called; assert no service call was made.
3. **Upstream API failure** — service throws; assert the error surface matches what the UI expects (and any optimistic UI state was rolled back).
4. **Empty / boundary** — empty input, empty response, whitespace-only string, zero-element list.

### Pattern-specific additions

- **Optimistic UI** → rollback test that asserts snapshot restoration on failure.
- **Cache fallback** → empty-cache (throws) + populated-cache (returns cached) cases.
- **Pagination** → assert `hasMore` / `nextOffset` surfaced; assert zero-item-page boundary.
- **AsyncStream consumers** → cancellation test (consumer drops; producer stops within a bounded turn).
- **Event-bus subscribers** → routing test (event for matching id mutates; event for non-matching id is a no-op).

## End-to-end gate (run all; report each result)

1. `xcodebuild -scheme InterlinedList -destination 'platform=macOS' build`
   → must end `** BUILD SUCCEEDED **`.

2. `xcodebuild -scheme InterlinedList -destination 'platform=macOS' test`
   → all App-target tests pass; report count.

3. `swift test --package-path Packages/InterlinedKit`
   → report count; confirm no regression vs. last wave.

4. `swift test --package-path Packages/InterlinedDomain`
   → report count; confirm no regression.

5. `swift test --package-path Packages/InterlinedPersistence`
   → report count; confirm no regression.

6. `grep -rn "import InterlinedKit" App/Features App/Navigation App/MenuCommands 2>/dev/null`
   → must produce zero hits (Decision 0003). Report the result line explicitly even when empty.

7. **Contract tests** (env-gated): if `INTERLINEDLIST_EMAIL` / `INTERLINEDLIST_PASSWORD` are set, the kit's `ContractTests` exercise the live API. State whether they ran or were skipped; never invent credentials.

## View-layer rule

Do not write tests that render SwiftUI views. Test view models against `*Servicing` stubs and an isolated event bus. View correctness is verified by the build and by hand.

## When the gate fails

- Build failure → fix the build before reporting.
- Test regression in a package you did not touch → investigate; do not paper over.
- New `import InterlinedKit` hit in `App/Features/**` → add the missing domain model in `InterlinedDomain` and re-route the feature through it (Decision 0003).
- pbxproj had to be edited → warn the user that Xcode's SourceKit indexer may need **File → Packages → Reset Package Caches**; xcodebuild is unaffected.
