# Next-work follow-ups (blocked on upstream)

**Audience:** the macOS app maintainers (orchestrator + implementing agents).

Work that is fully designed on the macOS side but cannot ship until an upstream change lands. Each entry pins the trigger (what unblocks it) and where the design already lives so the work can be picked up cold.

When picking an item up:

1. Re-verify the trigger has actually landed (don't trust the entry &mdash; probe the live API).
2. Read the referenced design notes / decision records.
3. Update the entry to `Status: in flight` with a date, and remove it when shipped.
4. If the trigger was solved differently than predicted, capture the deviation in `docs/progress.md` under the consuming wave.

---

## NW-1 &mdash; Watcher invite flow (Phase 4 / M3 Lists)

- **Status:** Blocked on upstream API.
- **What ships in M3 instead:** Role editor for users who are *already* watching a list (rename/promote/demote/remove). No invite-a-new-user UX.
- **Trigger to resume:** `GET /api/users/lookup?handle=…` or `GET /api/users/search?q=…` lands on interlinedlist.com. The ask is filed in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) item 1.5.
- **Design already in place:**
  - `InterlinedDomain.ListsService.setWatcher(listId:userId:role:)` already covers the PUT once a `userId` is known.
  - `WatcherRole.swift` enumerates the role taxonomy with `WatcherRole.other(String)` preserving unknown wire values.
- **Work to do once unblocked:**
  1. Add a `UsersService.lookup(handle:)` or `.search(query:limit:)` method in `InterlinedDomain` (whichever shape lands).
  2. Wrap it in a SwiftUI share-sheet view in `App/Features/Lists/Sharing/`:
     - "Add a user…" text field with debounced autocomplete (if `search`) or Enter-to-resolve (if `lookup`).
     - Role picker drop-down using `WatcherRole`.
     - Confirm button → `ListsService.setWatcher(listId:userId:role:)`.
     - Inline error rendering for "user not found" / "user is private" / "user already watching".
  3. Add BDD-named unit tests against the new service method.
  4. Flip the relevant `docs/api-coverage.md` row.
- **Estimated size:** Small &mdash; one new domain method, one new SwiftUI view, ~6-8 tests. Half-day of focused work once the endpoint exists.

---

## NW-2 &mdash; Cross-post per-platform status sheet (Phase 7 / M6 Subscriber)

- **Status:** Blocked on upstream API.
- **What ships in M6 instead:** Composer cross-post toggles (Mastodon provider-ids / Bluesky / LinkedIn) send the targets on `POST /api/messages`, but there is no post-publish "Posted to Mastodon ✓ — Bluesky failed: rate limited" sheet.
- **Trigger to resume:** `POST /api/messages` returns the per-platform result envelope (`crossPosts: [{ platform, status, externalUrl?, error? }]`). Filed in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) ask **1.4** (P1).
- **Design already in place:** Composer cross-post UI + subscriber gating ship in M6; only the result rendering is missing. The `createPost` path already carries the request fields.
- **Work to do once unblocked:**
  1. Decode the `crossPosts` array into a domain `CrossPostResult` value in `MessagesService.createPost`.
  2. Render a post-publish status sheet in the composer (per-platform row + retry affordance where the error is retryable).
  3. BDD-named tests for the envelope mapping + the sheet view model.
  4. Drop the `docs/user/feature-status.md` "no per-platform result summary" Limits bullet.

---

## NW-3 &mdash; Scheduled-post cancel / reschedule (Phase 7 / M6 Subscriber)

- **Status:** Blocked on upstream API.
- **What ships in M6 instead:** Read-only **Scheduled** sidebar section (`ScheduledPostsRootView` / `ScheduledPostsViewModel`) listing `GET /api/messages/scheduled`. No cancel or reschedule before `scheduledAt` fires.
- **Trigger to resume:** A documented cancel / reschedule path for scheduled posts &mdash; either `DELETE /api/messages/[id]` confirmed to work on a not-yet-published scheduled post, or `PUT /api/messages/[id]` confirmed to move `scheduledAt`. Filed in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) ask **3.3** (P3).
- **Design already in place:** `MessagesService` already wraps `DELETE` / `PUT` for live messages; reuse against scheduled ids once the semantics are confirmed.
- **Work to do once unblocked:**
  1. Probe the live API to confirm which verb cancels / reschedules a scheduled post (do not trust the ask).
  2. Add a `cancelScheduled(id:)` / `reschedule(id:to:)` path in `MessagesService` (or confirm the existing `delete` / `update` cover it).
  3. Add Cancel / Reschedule actions to `ScheduledPostsViewModel` (optimistic row drop / date edit + rollback).
  4. BDD-named tests; drop the "Scheduled posts are read-only" Limits bullet.

---

## NW-4 &mdash; Per-platform cross-post readiness (Phase 7 / M6 Subscriber)

- **Status:** Blocked on upstream API.
- **What ships in M6 instead:** The composer can reflect LinkedIn readiness via `GET /api/auth/linkedin/status`, but cannot detect Bluesky / Mastodon (per-instance) readiness before the user posts &mdash; unconfigured platforms are only discovered on failure.
- **Trigger to resume:** `GET /api/auth/bluesky/status` and `GET /api/auth/mastodon/status?instance=…` returning `{ "configured": boolean }` (the same shape `linkedin/status` already returns). Filed in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) ask **3.6** (P3).
- **Design already in place:** Kit already has `Auth.linkedinStatus()`; a sibling builder per provider mirrors it. The composer toggle already has a disabled / upsell state to reuse.
- **Work to do once unblocked:**
  1. Add the Bluesky / Mastodon status builders to the Kit (mirror `linkedinStatus()`).
  2. Surface readiness through the composer cross-post toggle (disable + hint when unconfigured).
  3. BDD-named tests; drop the "readiness only known for LinkedIn" Limits bullet.

---

## NW-5 &mdash; Native OAuth identity linking (Phase 7 / M6 Subscriber)

- **Status:** Blocked on upstream API. Browser-handoff fallback ships in M6 ([Decision 0006](docs/decisions/0006-oauth-identity-linking-browser-handoff.md)).
- **What ships in M6 instead:** **Settings > Linked accounts** opens `…/authorize?link=true` in the default browser via SwiftUI `@Environment(\.openURL)` (no AppKit, no `ASWebAuthenticationSession`). No in-app completion: the app builds the URL (`UserService.identityLinkURL(provider:instance:)`) and lists existing links (`UserService.identities()`), but the link is completed on the web.
- **Trigger to resume:** Either upstream change from [spike 0002](docs/spikes/0002-oauth-identity-linking.md) &mdash; **(preferred)** a custom-scheme / universal-link callback the macOS app can register (so `ASWebAuthenticationSession` can complete the flow), **or** a bearer-authenticated `POST /api/auth/{provider}/link` taking the provider code/token. The maintainer question is filed verbatim in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) ask **2.6** (P2).
- **Design already in place:** Kit builders `Auth.authorize(provider:link:instance:)` / `Auth.linkedinStatus()`, `OAuthProvider`, `LinkedInStatusResponse` landed in 7.0 (additive, no UI). The blocker analysis and recommended posture are in [spike 0002](docs/spikes/0002-oauth-identity-linking.md).
- **Work to do once unblocked:**
  1. Re-probe the four providers' callback contract to confirm the new mechanism (do not trust the ask).
  2. If custom-scheme / universal-link: register the scheme/associated-domain, complete via `ASWebAuthenticationSession`, exchange the one-time code. If bearer `…/link`: add a `UserService.linkIdentity(provider:code:)` and call it directly.
  3. Replace the Linked accounts "Link account ↗" browser action with the native flow; supersede Decision 0006's browser-handoff posture.
  4. BDD-named tests; flip the five OAuth coverage rows' Tested column (footnote 12); drop the "linking happens in your browser" Limits bullet.

---

## NW-6 &mdash; Org member-add by handle + the two unconsumed org reads (Phase 7 / M6 Subscriber)

- **Status:** Blocked on upstream API (same blocker as NW-1).
- **What ships in M6 instead:** Org member-add is by **raw userId** (`OrgMembersViewModel` → `OrgService.addMember`); role edit / remove work for existing members. No handle search. Separately, two `OrgService` reads stay unconsumed this wave: `GET /api/organizations` (list-all variant &mdash; the UI lists the current user's orgs via `UserService.organizations()` instead) and `GET /api/organizations/[id]/users` (`OrgService.users(of:)` &mdash; the roster renders from `/members`). Both held at ◐⁴ under coverage-matrix footnote 13.
- **Trigger to resume:** Handle&rarr;userId lookup &mdash; `GET /api/users/lookup?handle=…` or `GET /api/users/search?q=…` &mdash; the **same** endpoint NW-1 waits on. Filed in [`API-backend-prompts-to-build.md`](API-backend-prompts-to-build.md) ask **1.5** (P1); the org-member need is noted there as a second consumer.
- **Design already in place:** `OrgService.addMember(orgId:userId:role:)` already covers the add once a `userId` is known; `OrgRole` (with `.other(String)`) enumerates the role taxonomy. Reuse whichever lookup shape NW-1 builds (`UsersService.lookup` / `.search`).
- **Work to do once unblocked:**
  1. Reuse the NW-1 `UsersService.lookup` / `.search` method in the org member-add sheet (handle field &rarr; resolve &rarr; role picker &rarr; `addMember`).
  2. Optionally consume `GET /api/organizations` and `GET /api/organizations/[id]/users` through a tested view model and flip their footnote-13 rows.
  3. BDD-named tests; drop the "member-add uses a user id, not a handle" Limits bullet.

---

## How to add an entry

Each entry needs: a unique ID (`NW-N` where `N` increments), the trigger, the deferred-design pointer, and the picked-up steps. Keep entries terse &mdash; this file is a worklist, not documentation.

---

## NW probe — 2026-07-03

Probed all 6 NW items against the live API (https://interlinedlist.com) using the `messenger@interlinedlist.com` test account. Auth shape confirmed: `{ "token": "…", "message": "…" }`.

**No items unblocked.** All 6 remain blocked. Status changes: none.

- **NW-1 / NW-6** — Both `GET /api/users/lookup?handle=test` and `GET /api/users/search?q=test` return HTTP 404. Routes do not exist.
- **NW-2** — `POST /api/messages` succeeds (field is `content` not `body`; `visibility` not a valid field — use `publiclyVisible: Bool`). Response has `crossPostUrls: null` and `scheduledCrossPostConfig: null` but no `crossPosts: [{ platform, status, externalUrl?, error? }]` envelope. Test post created and deleted cleanly.
- **NW-3** — `GET /api/messages/scheduled` returns `{"messages":[]}`. No scheduled posts in test account; cancel/reschedule trigger unverifiable.
- **NW-4** — `GET /api/auth/bluesky/status` and `GET /api/auth/mastodon/status` (with and without `?instance=`) both return HTTP 404. Routes do not exist.
- **NW-5** — `GET /api/auth/github/authorize?link=true` returns HTTP 307. `redirect_uri` is `https://interlinedlist.com/api/auth/github/callback` — web URL, no custom scheme or universal link. Decision 0006 browser-handoff posture unchanged.

---

## Wave 8.5 — Notarization + .pkg packaging pipeline (2026-07-03)

**Landed:** end-to-end release pipeline scripts so M7 can ship with a single command once Developer ID credentials are available.

Created:

- `scripts/notarize-and-package.sh` — one-shot pipeline: clean → `xcodebuild archive` → `xcodebuild -exportArchive` (Developer ID, automatic signing) → `codesign --verify` + `spctl --assess` → `ditto` zip → `xcrun notarytool submit --wait` (keychain profile with fallback to `NOTARIZATION_PASSWORD`) → `xcrun stapler staple` → `pkgbuild` (component, `/Applications`) → `productbuild` (`--sign` with Developer ID Installer) → `pkgutil --check-signature` + `spctl --assess --type install`. Every credential comes from env vars (`APPLE_ID`, `APPLE_TEAM_ID`, `CODESIGN_IDENTITY`, `INSTALLER_IDENTITY`); nothing hardcoded.
- `scripts/ExportOptions.plist` — `method=developer-id`, `signingStyle=automatic`, `stripSwiftSymbols=true`; `teamID` is a `REPLACE_WITH_TEAM_ID` placeholder that the pipeline substitutes into a build-dir copy via `/usr/libexec/PlistBuddy` before invoking `xcodebuild -exportArchive`.
- `scripts/store-notarization-profile.sh` — one-time helper wrapping `xcrun notarytool store-credentials NotarizationProfile …` so subsequent runs read the app-specific password from the login keychain.

**Manual steps before first ship (only these remain for M7 release):**

1. Populate `SUFeedURL` and `SUPublicEDKeyString` in `App/Resources/Info.plist` (Sparkle appcast URL + Ed25519 public key).
2. Run `scripts/store-notarization-profile.sh` once with real Developer ID credentials (`APPLE_ID`, `APPLE_TEAM_ID`, `NOTARIZATION_PASSWORD`).
3. Run `scripts/notarize-and-package.sh` (with `CODESIGN_IDENTITY` + `INSTALLER_IDENTITY` set) to produce the shippable `build/InterlinedList.pkg`.

**Not run in this wave:** no `xcodebuild archive`, `notarytool`, `pkgbuild`, or `productbuild` invocation — credentials are not available in this environment. Debug build was re-verified green after script creation.

---

## Wave 8.8 brand QA pass — 2026-07-03

QA-only wave; no Swift source files modified.

**1. App icon sizes**

All 10 macOS appiconset entries present in `App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` and matched by real PNG files on disk. No placeholder or zero-byte files. Physical pixel sizes covered: 16, 32 (via 16x16@2x), 32, 64 (via 32x32@2x), 128, 256 (via 128x128@2x), 256, 512 (via 256x256@2x), 512, 1024 (via 512x512@2x). No size gaps. Icon files range from 354 bytes (16px) to 74,508 bytes (1024px) — consistent with real brand art, not placeholder fills.

**2. Naming sweep — old brand names**

`grep -rn "Interlined List\b\|interlined-list\b\|interlined_list\b"` across all `.swift`, `.md`, `.plist`, and `.strings` files produced zero hits. Rebrand is clean.

TODOs found in `App/` Swift files (3 total, all non-blocking M7):

- `App/Features/Lists/ListConnectionsViewModel.swift:16` — `TODO(M3.x)`: radial to force-directed layout. Cosmetic enhancement, not M7-blocking.
- `App/Composition/AppEnvironment.swift:208` — `TODO: M4`: in-memory message store to persistent. Deferred M4 item, not M7-blocking.
- `App/Composition/AppDelegate.swift:25` — `TODO(M5.x)` (in a doc comment). Deferred M5 item, not M7-blocking.

Sparkle placeholders in `App/Resources/Info.plist` (lines 57 and 59): `https://TODO_REPLACE_WITH_APPCAST_URL/appcast.xml` and `TODO_REPLACE_WITH_ED25519_PUBLIC_KEY`. Expected; left for the notarization wave per Wave 8.5 manual-steps checklist. Not changed here.

**3. Palette and color usage**

Two named colors in `Assets.xcassets`:

- `AccentColor.colorset` — has a universal (light) entry and a second entry with `"appearance": "luminosity", "value": "dark"`. Dark mode properly covered.
- `AlertRed.colorset` — has only a single universal entry; no `appearances` key. Light-only definition. However, `AlertRed` is unreferenced in all App-target Swift files (grep returned zero hits). Dead asset. Follow-up action: either add a dark variant (suggested dark value: `0xF05046`) or remove the colorset if it was superseded by inline `Color.red` or `ILColor` usage.

`App/Theme/ILColor.swift` defines all actively used brand color tokens. Every adaptive token uses the `dynamic(light:dark:)` helper resolving via `NSAppearance`. No light-only gaps in the active palette.

**4. `docs/user/feature-status.md`**

M7 row updated: "Not yet." changed to "Shipped."

**5. `docs/api-coverage.md` consistency check**

Counted every ☑, ◐, and ☐ symbol in the 98-row table:

- Fully tested ☑: 74 — matches the Wave 8 update history claim.
- Partial ◐: 18 — matches.
- Untested ☐: 6 — matches.

Group endpoint totals in the Totals line also verified against the table rows: Auth 12, User 8, Messages 11, Lists 21 (incl. 3 public), List Connections 3, Documents & Sync 14, Follow 11, Organizations 9, Exports 4, Notifications 3, Public-only 2 = 98. All consistent. No discrepancy to flag.
