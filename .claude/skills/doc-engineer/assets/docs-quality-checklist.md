# Documentation Quality Checklist

- Audience is explicitly identified.
- Content matches the selected track (engineering, user, or repo).
- API behavior claims are cross-checked against InterlinedList references.
- Steps are actionable and ordered.
- Terminology is consistent across documents.
- Links are valid and relevant.
- Any assumptions are stated clearly.
- Changes include impact notes for downstream readers.

## Project-specific gates

- **Shipped-only rule.** Every claim about app behavior is cross-checked against the **Status snapshot** and shipped scoreboard in `work-consolidation.md` — the single source of truth since 2026-09-14. Planned features are labeled "coming in a future update." *(This rule pointed at `docs/progress.md` until 2026-09-14; that file is the M0–M7 build journal, was last updated 2026-06-25, and now lives in `docs/archive/`. Do not cite it as current.)*
- **Help Book ↔ `docs/user/` parity.** The Help Book HTML page mirrors the wording of the matching `docs/user/<page>.md`. Divergence is a maintenance bug.
- **`hiutil` rerun.** After any HTML page change, regenerate `InterlinedList.helpindex`. Document the run (or the manual-step requirement if `hiutil` is unavailable).
- **No `<script>` tags** in Help Book HTML. Grep before declaring done.
- **`plutil -lint`** on every `Info.plist` you touched.
- **Coverage matrix flips** correspond to wave consumers actually exercising the row end-to-end; recompute totals against the matrix, do not paste.
- **Same-date update-history entries are merged**, not stacked.
- **Read-only paths.** `docs/decisions/**` is off-limits — decision records are amended by superseding them, never edited in place. *(`PLAN.md` and `ORCHESTRATION.md` were also listed here until 2026-09-14; both were deleted from the repo in `f040954` and the rule no longer applies to them.)*
- **Same-PR doc sync — the anti-drift rule.** A PR that ships a `G`-item, closes a parity issue, or changes app behavior **must update `work-consolidation.md` in the same PR**: flip the scoreboard entry, and refresh the test baseline if it moved. Do not defer this to a later "docs pass."

  > **Why this rule exists.** Between 2026-09-07 and 2026-09-13, seven PRs (#67–#73) shipped without the master doc moving once. The doc drifted ~330 tests and two API re-measures behind the code, and six issues it described as open had already shipped. A doc updated only in dedicated docs passes will always drift; one updated by the PR that invalidates it cannot.
