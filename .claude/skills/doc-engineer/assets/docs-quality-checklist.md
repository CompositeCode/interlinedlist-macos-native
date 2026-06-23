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

- **Shipped-only rule.** Every claim about app behavior is cross-checked against `docs/progress.md`. Planned features are labeled "coming in a future update."
- **Help Book ↔ `docs/user/` parity.** The Help Book HTML page mirrors the wording of the matching `docs/user/<page>.md`. Divergence is a maintenance bug.
- **`hiutil` rerun.** After any HTML page change, regenerate `InterlinedList.helpindex`. Document the run (or the manual-step requirement if `hiutil` is unavailable).
- **No `<script>` tags** in Help Book HTML. Grep before declaring done.
- **`plutil -lint`** on every `Info.plist` you touched.
- **Coverage matrix flips** correspond to wave consumers actually exercising the row end-to-end; recompute totals against the matrix, do not paste.
- **Same-date update-history entries are merged**, not stacked.
- **Read-only paths.** `PLAN.md`, `ORCHESTRATION.md`, `docs/decisions/**` are off-limits.
