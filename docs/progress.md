# Orchestration Progress Log

**Audience:** engineering (orchestrator, implementing agents, maintainers).

This is the running progress log required by [ORCHESTRATION.md](../ORCHESTRATION.md). [PLAN.md](../PLAN.md) and ORCHESTRATION.md are **read-only** for everyone, including the orchestrator — all progress, wave gates, and deviations are recorded here and in git commits, never by editing the plan. Waves map 1:1 to PLAN.md §6 milestones. Append entries per wave; do not rewrite history in this file — correct earlier entries with a dated note.

Companion documents: endpoint status lives in [api-coverage.md](api-coverage.md) (updated at the end of each wave); recorded decisions live in `docs/decisions/`; spike findings live in `docs/spikes/`.

---

## Wave 0 — Foundation (PLAN.md §6 M0)

### 0.1 — Repository initialization — DONE
- `git init`, Swift/Xcode `.gitignore`, initial commit of plan, orchestration prompt, Claude agents and skills.
- Commit: `cc0c8f1`.

### 0.2 — Project scaffold — DONE
- Xcode 16 project using filesystem-synchronized (buildable) folder groups, so adding source files does not touch `project.pbxproj` (the serialization-point mitigation from ORCHESTRATION.md).
- App target: macOS 14 minimum, Swift 6 toolchain.
- Three SPM packages per PLAN.md §3: `InterlinedKit`, `InterlinedDomain`, `InterlinedPersistence`, each with a test target.
- 9 BDD-named tests passing across the packages; everything builds.
- Commit: `059606f`.

### 0.3 — Parallel foundation tasks — IN FLIGHT
Launched in parallel per ORCHESTRATION.md Wave 0 step 3 (non-overlapping path ownership):

| Task | Owner paths | Deliverable | Status |
| --- | --- | --- | --- |
| 0.3a — Auth spike (PLAN.md §4): probe Session-only endpoint groups with a Bearer token against the live API | `docs/spikes/` | `docs/spikes/auth-bearer-vs-session.md` | **BLOCKED** — invalid credentials (see below); no deliverable written (refused to fabricate) |
| 0.3b — Branding (PLAN.md §9): brand kit download, 1024px icon from SVG, AppIcon set, Color Sets | `App/Resources/**`, `Brand/` | Asset catalogs per §9 tables | DONE — build-verified; 4 deviations flagged below |
| 0.3c — CI: GitHub Actions build + test on macOS runner | `.github/workflows/**` | `.github/workflows/ci.yml` | DONE — YAML validated by orchestrator (`python3 -c yaml.safe_load` → valid); first real run pending push |
| 0.3d — Docs scaffolding | `docs/**` | `docs/api-coverage.md` (98-endpoint matrix, all unchecked) + `docs/progress.md` | DONE (2026-06-11) |

**0.3b branding deviations** (from PLAN.md §9, full detail in agent report): (1) the `interlinedlist-logo-only.png` named on the branding page is absent from the kit zip and 404s on the site — the site favicon `logo-icon.png` (321×321) was curated into `Brand/icon/` as the mark; PLAN.md §9's "canonical icon mark" line should be amended. (2) Solid-bg icon variants ship only at 64–512; missing sizes (16, 32, 1024) rasterized from the official SVG onto white via CoreGraphics (no PNG upscaled). (3) `ATSApplicationFontsPath` set to `.` not `Fonts` because the synchronized folder group flattens `Fonts/` into `Contents/Resources/`. (4) `SurfaceNested` light analog chosen as `#F5F5F5` (spec defines dark only).

### Wave 0 gate — PASSED (2026-06-15)

- App build: `xcodebuild … -scheme InterlinedList -destination 'platform=macOS' build` → **BUILD SUCCEEDED** (brand asset catalog validates via actool).
- Package tests: InterlinedKit 4/4, InterlinedDomain 3/3, InterlinedPersistence 2/2 — **9/9 passing**.
- Path-ownership check: untracked top-level paths limited to `.github`, `App`, `Brand`, `docs` — no overlaps; conflict rules held.
- Commit: `<recorded in this commit>`.
- Coverage matrix delta: baseline created (98 endpoints, 0 implemented, 0 tested).

### Auth transport decision — RECORDED (provisional)
See [decisions/0001-auth-transport.md](decisions/0001-auth-transport.md).

- **Decision:** conservative **dual-transport** — Bearer primary + cookie-session fallback; per-request `AuthTransport` seam. Correct whether or not Bearer works on Session-only groups, so Wave 1 is unblocked.
- **Empirical status:** spike BLOCKED — `POST /api/auth/sync-token` returns 401 `Invalid email or password` with the provided env-var credentials (endpoint healthy: empty body → 400). Probe ready to re-run once valid credentials are supplied; if Bearer proves universal, open `0002` to drop the fallback.
- **Wave 1 carry-in:** every Wave 1 task prompt must cite decision 0001 and build the `AuthTransport` seam.

---

_Wave 1 (InterlinedKit core) and later entries are appended below this line as waves complete._
