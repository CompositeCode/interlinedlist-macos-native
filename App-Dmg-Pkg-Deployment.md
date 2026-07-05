# InterlinedList — Deployment Reference: App Store, DMG, and PKG

**Bundle ID:** `com.interlinedlist.macos`  
**Team ID:** `BJA9558E4B`  
**Minimum macOS:** 15.0 (Sequoia)  
**App category:** `public.app-category.social-networking`

---

## Table of Contents

1. [All Credentials, Keys, and Tokens](#1-all-credentials-keys-and-tokens)
2. [Current Feature Status and Remaining Work](#2-current-feature-status-and-remaining-work)
3. [Deployment: PKG Installer — Developer ID](#3-deployment-pkg-installer--developer-id)
4. [Deployment: DMG Disk Image — Developer ID](#4-deployment-dmg-disk-image--developer-id)
5. [Deployment: Mac App Store](#5-deployment-mac-app-store)
6. [Required App Store Assets](#6-required-app-store-assets)
7. [Technical Changes Required for App Store](#7-technical-changes-required-for-app-store)
8. [Cost Breakdown](#8-cost-breakdown)
9. [Phased Approach Recommendation](#9-phased-approach-recommendation)
10. [App Review Guidelines Considerations](#10-app-review-guidelines-considerations)

---

## 1. All Credentials, Keys, and Tokens

Every credential needed across all three distribution channels. Set up the shared secrets first, then the channel-specific ones.

### 1a. Shared — Required for All Channels

| Credential | What it is | Where to get it | Environment var / Secret name |
|-----------|-----------|----------------|-------------------------------|
| **Apple Developer Program membership** | $99/year paid membership required for all distribution | developer.apple.com/programs/enroll | N/A — account-level |
| **Apple ID email** | The Apple ID associated with the Developer account | Already known | `APPLE_ID` |
| **Team ID** | 10-character developer team identifier | Already known: `BJA9558E4B` | `APPLE_TEAM_ID` |

### 1b. Developer ID Distribution — PKG and DMG

These are all required for `scripts/notarize-and-package.sh` and the GitHub Actions `release.yml` workflow.

| Credential | What it is | Where to get it | Secret name (GitHub Actions) |
|-----------|-----------|----------------|------------------------------|
| **Developer ID Application certificate** | Signs the `.app` bundle | Xcode → Settings → Accounts → Manage Certificates → "+" → Developer ID Application | Used locally; export for CI |
| **Developer ID Installer certificate** | Signs the `.pkg` installer | Xcode → Settings → Accounts → Manage Certificates → "+" → Developer ID Installer | Used locally; export for CI |
| **`CERTIFICATES_P12`** | Base64-encoded `.p12` bundle containing both Developer ID certificates | Keychain Access → select both certs → Export → save as `.p12` → `base64 -i Certificates.p12 \| pbcopy` | `CERTIFICATES_P12` |
| **`CERTIFICATES_P12_PASSWORD`** | Passphrase set when exporting the `.p12` | Set during Keychain Access export | `CERTIFICATES_P12_PASSWORD` |
| **`CODESIGN_IDENTITY`** | Full common name of the Developer ID Application cert | Shown in Keychain Access, e.g. `"Developer ID Application: Your Name (BJA9558E4B)"` | `CODESIGN_IDENTITY` |
| **`INSTALLER_IDENTITY`** | Full common name of the Developer ID Installer cert | Shown in Keychain Access, e.g. `"Developer ID Installer: Your Name (BJA9558E4B)"` | `INSTALLER_IDENTITY` |
| **`NOTARIZATION_PASSWORD`** | App-specific password for `xcrun notarytool` | appleid.apple.com → Sign-In and Security → App-Specific Passwords | `NOTARIZATION_PASSWORD` |
| **Notarization keychain profile (local only)** | Stored keychain credential for `notarytool` — avoids passing credentials per invocation | Run `scripts/store-notarization-profile.sh` once with `APPLE_ID`, `APPLE_TEAM_ID`, `NOTARIZATION_PASSWORD` | `NOTARIZATION_KEYCHAIN_PROFILE` (default: `NotarizationProfile`) |
| **`GITHUB_TOKEN`** | Auto-provided by GitHub Actions — used by `gh` to create the draft release | Automatically injected by Actions; no setup required | Automatic |
| **Sparkle Ed25519 key pair** | Public key in `Info.plist`; private key used to sign each release's `sparkle:edSignature` in `appcast.xml` | Run `generate_keys` from Sparkle's tools | Private: local only. Public: `SUPublicEDKeyString` in `App/Resources/Info.plist` |
| **`SUFeedURL`** | Appcast URL Sparkle polls for updates | Set in `App/Resources/Info.plist` | Value: `https://interlinedlist.com/appcast.xml` (or the versioned path in `releases/appcast.xml`) |

**Local-only placeholders still needing values (blocking the first Developer ID release):**

| File | Key | Current value | What to replace it with |
|------|-----|--------------|------------------------|
| `App/Resources/Info.plist` | `SUPublicEDKeyString` | `TODO_REPLACE_WITH_ED25519_PUBLIC_KEY` | Ed25519 public key from `generate_keys` |
| `App/Resources/Info.plist` | `SUFeedURL` | `https://TODO_REPLACE_WITH_APPCAST_URL/appcast.xml` | `https://interlinedlist.com/appcast.xml` |
| `scripts/export-options.plist` | `teamID` | `REPLACE_WITH_YOUR_TEAM_ID` | `BJA9558E4B` |
| `releases/appcast.xml` | `sparkle:edSignature` | `TODO_REPLACE_WITH_SIGNATURE` | Signature from `sign_update` for each release artifact |
| `releases/appcast.xml` | `enclosure length` | `0` | Actual byte size of the signed artifact |

### 1c. Mac App Store

These are separate from the Developer ID secrets and must not overwrite them.

| Credential | What it is | Where to get it | Secret name (GitHub Actions) |
|-----------|-----------|----------------|------------------------------|
| **Apple Distribution certificate** | Signs the `.app` for App Store submission (different from Developer ID Application) | Xcode → Settings → Accounts → Manage Certificates → "+" → Apple Distribution | Used locally; export for CI |
| **`APPSTORE_CERTIFICATES_P12`** | Base64-encoded `.p12` of the Apple Distribution certificate | Keychain Access → export as `.p12` → `base64 -i AppStoreCert.p12 \| pbcopy` | `APPSTORE_CERTIFICATES_P12` |
| **`APPSTORE_CERTIFICATES_P12_PASSWORD`** | Passphrase protecting the App Store `.p12` | Set during export | `APPSTORE_CERTIFICATES_P12_PASSWORD` |
| **App Store Connect API Key** | Machine-to-machine auth for uploading builds and reading App Store Connect | appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API → Generate API Key → Role: App Manager | Download once as `.p8` |
| **`ASC_API_KEY_ID`** | 10-character key ID shown next to the API key | Same page as above | `ASC_API_KEY_ID` |
| **`ASC_API_ISSUER_ID`** | UUID shown at the top of the API keys page | Same page as above | `ASC_API_ISSUER_ID` |
| **`ASC_API_KEY_P8`** | Contents of the downloaded `.p8` file, base64-encoded | `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy` — downloaded once at key creation; not regeneratable | `ASC_API_KEY_P8` |

---

## 2. Current Feature Status and Remaining Work

### 2a. What Is Shipped — All Core Features Complete

All planned milestones M0 through M7 are **shipped** as of the Wave 8 release:

| Milestone | What it covers | Status |
|---|---|---|
| M0 — Foundation | Auth (email+password, Keychain token), onboarding, brand assets, CI | **Shipped** |
| M1 — Read-only core | Timeline (All/Mine/tag), message threads, public list browsing, profile header | **Shipped** |
| M2 — Posting | Composer (⌘N), Markdown, tags, visibility, replies, "I Dig!" reactions, reposts, edit/delete own messages | **Shipped** |
| M3 — Lists | CRUD, schema DSL editor, rows table, nested lists, connections graph, watchers/sharing, GitHub refresh | **Shipped** |
| M4 — Documents | Folder tree, Markdown editor + Textual preview, image upload, offline sync engine | **Shipped** |
| M5 — Social and notifications | Follow/unfollow, follower/following lists, private-account requests, notifications tray, system banners, Dock badge | **Shipped** |
| M6 — Subscriber and orgs | Media attachments (client-side resize), scheduled posts, cross-posting (Mastodon/Bluesky/LinkedIn), browser-handoff OAuth identity linking, organizations + member roles, entitlement gating | **Shipped** |
| M7 — Ship | CSV exports, Settings polish (email change, account deletion, avatar), sandboxing + hardened runtime, notarization pipeline, Sparkle updates, accessibility audit, brand QA pass | **Shipped** |

**Test suite totals at M7 ship (all passing, 0 failures):**

| Target | Tests |
|--------|------:|
| `InterlinedKitTests` | 190 |
| `InterlinedDomainTests` | 388 |
| `InterlinedPersistenceTests` | 120 |
| `InterlinedListTests` (App) | 278 |
| **Grand total** | **976** |

### 2b. Source Code TODOs — Remaining In-Code Work

Three TODOs remain in the Swift source. All are known, non-blocking, and deferred intentionally.

| File | TODO | What it means | Priority |
|------|------|--------------|----------|
| `App/Features/Lists/ListConnectionsViewModel.swift:16` | `TODO(M3.x)`: swap radial layout for force-directed | The list-connections graph uses a stable radial arrangement. Force-directed physics would make it feel more organic. **Visual polish only — no functional gap.** | Low |
| `App/Composition/AppEnvironment.swift:208` | `TODO: M4` — swap in-memory message store for persistent `InterlinedPersistence` container | Messages re-fetch from the network on every app launch. The persistence layer exists; the composition root uses the in-memory store because `InterlinedPersistence` schema types are package-internal. **Functional limitation: timeline is lost on quit.** | Medium |
| `App/Composition/AppDelegate.swift:25` | `TODO(M5.x)` — notification deep-link routing to specific content | Tapping a system notification banner brings the app to front but does not navigate to the relevant message, list, or profile. Typed `NotificationTarget` is available; routing layer is not yet written. **UX gap — navigation works via in-app tray.** | Medium |

### 2c. Backend-Blocked Features — All Still Blocked

These items were designed and are ready to implement on the macOS side, but each requires a backend API change that has not yet landed. All were verified as still blocked on **2026-07-03** against the live API at `https://interlinedlist.com`.

| ID | Feature | What's needed from the backend | macOS design status |
|----|---------|-------------------------------|---------------------|
| **NW-1** | Watcher invite by handle (Lists sharing) | `GET /api/users/lookup?handle=` or `GET /api/users/search?q=` — returns 404 today | `ListsService.setWatcher(listId:userId:role:)` is fully wired; only the user-lookup leg is missing. One new domain method + one SwiftUI sheet, ~6–8 tests. |
| **NW-2** | Cross-post per-platform status sheet (after publish) | `POST /api/messages` must return `crossPosts: [{ platform, status, externalUrl?, error? }]` envelope — currently returns `crossPostUrls: null` | Composer cross-post toggles already ship in M6; only the result-rendering sheet is missing. Decode `CrossPostResult` in `MessagesService.createPost` + post-publish sheet UI. |
| **NW-3** | Scheduled post cancel/reschedule | `DELETE /api/messages/[id]` or `PUT /api/messages/[id]` confirmed to work on a not-yet-published scheduled post | `ScheduledPostsRootView` is read-only. `MessagesService.delete` and `.update` already exist — need confirmation on semantics for scheduled posts only. |
| **NW-4** | Per-platform cross-post readiness (Bluesky/Mastodon) | `GET /api/auth/bluesky/status` and `GET /api/auth/mastodon/status?instance=` returning `{ "configured": boolean }` — both return 404 today | Kit already has `Auth.linkedinStatus()`; Bluesky/Mastodon status builders mirror it. Composer toggle disabled/hint state reused. |
| **NW-5** | Native in-app OAuth identity linking (GitHub, Mastodon, Bluesky, LinkedIn) | Backend needs either a custom-scheme/universal-link callback the app can register, or a bearer-authenticated `POST /api/auth/{provider}/link` | Browser-handoff fallback ships in M6 (Decision 0006). `ASWebAuthenticationSession` flow designed in spike 0002; ready to implement once callback contract lands. |
| **NW-6** | Org member-add by handle | Same blocker as NW-1 — `GET /api/users/lookup?handle=` needed | `OrgService.addMember(orgId:userId:role:)` fully wired; only the handle-to-userId lookup is missing. Reuses whichever shape NW-1 builds. |

**Status of retired planning documents:**

- **`PLAN.md`** — All M0–M7 milestones executed. Architecture decisions (Swift 6, SwiftUI-first, 3 SPM packages, macOS 15, hardened runtime, sandboxing) are baked into the codebase. The plan is fully realized and has been retired. Key deviation from the original plan: macOS 14 minimum bumped to 15 (Decision 0004, Textual Markdown library requirement).
- **`ORCHESTRATION.md`** — All Waves 0–8 complete. The orchestration prompt coordinated the build; all waves passed their gates. Retired along with the plan.
- **`NEXT-WORK.md`** — Content absorbed into §2c above. All 6 NW items confirmed still blocked as of 2026-07-03 live API probe.

---

## 3. Deployment: PKG Installer — Developer ID

The PKG installer is the recommended distribution format for users who prefer a macOS-native installer experience. It installs the app to `/Applications` via a standard macOS installer wizard.

### 3a. What needs to be done first (one-time setup)

**Step 1: Generate the Sparkle Ed25519 key pair.**

Install Sparkle's CLI tools (via the Sparkle release download), then:

```sh
# Run once; save the private key somewhere safe (never commit it)
./bin/generate_keys
```

The tool prints:
- A **private key** — store in your password manager or macOS Keychain, never in the repo
- A **public key** — paste this into `App/Resources/Info.plist` as `SUPublicEDKeyString`

**Step 2: Fill in the Info.plist placeholders.**

In `App/Resources/Info.plist`, replace:

```xml
<!-- Replace this -->
<key>SUPublicEDKeyString</key>
<string>TODO_REPLACE_WITH_ED25519_PUBLIC_KEY</string>

<!-- Replace this -->
<key>SUFeedURL</key>
<string>https://TODO_REPLACE_WITH_APPCAST_URL/appcast.xml</string>
```

With:

```xml
<key>SUPublicEDKeyString</key>
<string><!-- paste public key here --></string>

<key>SUFeedURL</key>
<string>https://interlinedlist.com/appcast.xml</string>
```

**Step 3: Fix the export-options.plist placeholder.**

In `scripts/export-options.plist`, replace `REPLACE_WITH_YOUR_TEAM_ID` with `BJA9558E4B`.

**Step 4: Store notarization credentials in the Keychain (once per machine).**

```sh
APPLE_ID=your@email.com \
APPLE_TEAM_ID=BJA9558E4B \
NOTARIZATION_PASSWORD=xxxx-xxxx-xxxx-xxxx \
    ./scripts/store-notarization-profile.sh
```

This stores a `NotarizationProfile` keychain item so subsequent notarization runs read credentials from Keychain rather than environment variables.

**Step 5: Add GitHub Actions secrets** (listed in §1b above).

### 3b. Building a PKG release locally

```sh
APPLE_ID=your@email.com \
APPLE_TEAM_ID=BJA9558E4B \
CODESIGN_IDENTITY="Developer ID Application: Your Name (BJA9558E4B)" \
INSTALLER_IDENTITY="Developer ID Installer: Your Name (BJA9558E4B)" \
RELEASE_LABEL=alpha \
    ./scripts/notarize-and-package.sh
```

**What the script does** (all steps automated):

1. Clean `build/` directory
2. `xcodebuild archive` → `InterlinedList.xcarchive`
3. `xcodebuild -exportArchive` with Developer ID, Automatic signing
4. `codesign --verify --deep --strict` on the exported `.app`
5. `ditto` zip → submit to Apple notarization via `xcrun notarytool`
6. `xcrun stapler staple` → validate notarization ticket on `.app`
7. `pkgbuild` (component pkg) + `productbuild` (signed final `.pkg`) → installs to `/Applications`
8. Notarize the `.pkg` → staple
9. Build `.dmg` (see §4)
10. Notarize the `.dmg` → staple
11. `shasum -a 256` checksums for both artifacts
12. Copy artifacts to `releases/`

**Output artifacts:**

```
releases/InterlinedList-<version>[-<label>].pkg
releases/InterlinedList-<version>[-<label>].pkg.sha256
```

### 3c. After each PKG release — sign for Sparkle

After the `.pkg` is notarized and copied to `releases/`, sign it with Sparkle's `sign_update` tool so the appcast entry is verifiable:

```sh
./bin/sign_update releases/InterlinedList-<version>.pkg
```

This prints an `edSignature` string and the file size in bytes. Copy both into `releases/appcast.xml`:

```xml
<item>
    <title>InterlinedList <version></title>
    <sparkle:version><build number></sparkle:version>
    <sparkle:shortVersionString><version></sparkle:shortVersionString>
    <pubDate><!-- RFC 2822 date --></pubDate>
    <enclosure
        url="https://interlinedlist.com/downloads/apple/InterlinedList-<version>.pkg"
        length="<byte size from sign_update>"
        type="application/octet-stream"
        sparkle:edSignature="<signature from sign_update>"
    />
</item>
```

### 3d. Automated PKG release via GitHub Actions

Push a semver tag to trigger the `release.yml` workflow:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The workflow:
- Imports the `CERTIFICATES_P12` Developer ID certificates into a short-lived keychain
- Runs `scripts/notarize-and-package.sh` (produces `.pkg`)
- Runs `scripts/create-dmg.sh` (produces `.dmg`)
- Creates a **draft** GitHub release with both artifacts attached

A human reviews and publishes the draft via the GitHub UI or `gh release edit`.

### 3e. After publish — update website

1. Upload `InterlinedList-<version>.pkg` and `.pkg.sha256` to `https://interlinedlist.com/downloads/apple/`
2. Publish the updated `releases/appcast.xml` to `https://interlinedlist.com/appcast.xml`
3. Sparkle checks the feed automatically; existing users receive the update prompt within 24 hours of their next check interval

---

## 4. Deployment: DMG Disk Image — Developer ID

The DMG provides a drag-to-install experience for users who prefer it over the PKG installer. Both artifacts are produced by the same `notarize-and-package.sh` pipeline — the DMG is built after the PKG in step 9 of the same script.

### 4a. DMG build process

The DMG is built automatically as part of `notarize-and-package.sh` (step 9 and 10). It can also be built standalone from an already-exported and notarized `.app`:

```sh
VERSION=1.0.0 \
CODESIGN_IDENTITY="Developer ID Application: Your Name (BJA9558E4B)" \
APPLE_ID=your@email.com \
APPLE_TEAM_ID=BJA9558E4B \
NOTARIZATION_PASSWORD=xxxx-xxxx-xxxx-xxxx \
    ./scripts/create-dmg.sh
```

**What the DMG script does:**

1. Creates a read-write staging DMG via `hdiutil create -format UDRW` from the notarized `.app`
2. Mounts the DMG and adds an `/Applications` symlink (drag-to-install target)
3. Detaches and converts to a compressed read-only DMG via `hdiutil convert -format UDZO`
4. Notarizes the DMG via `xcrun notarytool`
5. Staples the notarization ticket with `xcrun stapler`
6. Verifies with `spctl --assess --type install`

**Output artifact:**

```
releases/InterlinedList-<version>[-<label>].dmg
releases/InterlinedList-<version>[-<label>].dmg.sha256
```

### 4b. DMG vs. PKG — which to lead with

| Consideration | PKG | DMG |
|--------------|-----|-----|
| Install experience | Standard macOS installer wizard | Drag-and-drop to Applications |
| Install location control | Always `/Applications` | User can choose |
| Upgrade experience | Installer handles replacing old version | User drags new `.app` over old |
| Sparkle update delivery | Works — Sparkle can download and apply a PKG | Works — Sparkle can download and replace a `.app` |
| Enterprise/MDM | PKG preferred | DMG less common in MDM |

**Recommendation**: publish both. Link the PKG as the primary download; offer the DMG as the alternative. Both are produced by the same pipeline run.

### 4c. Signing the DMG for Sparkle (same as PKG)

If the Sparkle appcast entry points to the DMG instead of the PKG, sign it too:

```sh
./bin/sign_update releases/InterlinedList-<version>.dmg
```

Update `releases/appcast.xml` with the DMG URL, size, and signature. Or publish two appcast items — one per format — and let users pick.

---

## 5. Deployment: Mac App Store

The Mac App Store distribution channel requires significant changes to the current project because the entire pipeline is currently wired for Developer ID / Sparkle. The core experience is ready to ship; the technical changes below must be completed before submission.

### 5a. What must change (submission blockers)

| # | Blocker | Current state | Required state | File(s) |
|---|---------|--------------|---------------|---------|
| **B1** | Remove Sparkle | Sparkle 2.9.4 is a dependency; `SparkleController`, `UpdatesMenuCommands`, and `Info.plist` keys reference it | Removed entirely — App Store provides updates | `project.pbxproj`, `Package.resolved`, `SparkleController.swift` (delete), `UpdatesMenuCommands.swift` (delete), `InterlinedListApp.swift`, `Info.plist` |
| **B2** | Export method | `method = developer-id` | `method = app-store-connect` | Create `scripts/ExportOptions-AppStore.plist` |
| **B3** | Release signing identity | `"Apple Development"` in Release config | `"Apple Distribution"` | `project.pbxproj` Release config `BABD889F` |
| **B4** | Privacy manifest | Does not exist | `PrivacyInfo.xcprivacy` required for all submissions since spring 2024 | Create `App/Resources/PrivacyInfo.xcprivacy` |
| **B5** | Version inconsistency | `CFBundleShortVersionString = 0.0.1` in `Info.plist` vs. `MARKETING_VERSION = 0.1.0` in build settings | Align: change `CFBundleShortVersionString` to `$(MARKETING_VERSION)` | `App/Resources/Info.plist` |
| **B6** | Privacy policy URL | Does not exist | Publicly accessible URL required for Social Networking category | Publish at `https://interlinedlist.com/privacy` |
| **B7** | Support URL | Does not exist | Required by App Store Connect before submission form can be completed | Publish at `https://interlinedlist.com/support` |
| **B8** | UGC report mechanism | No in-app report action | App Review Guideline 1.2 requires a way to report objectionable content | Add "Report" to message context menu (if backend has endpoint) or provide URL in App Review notes |

### 5b. Should-fix before submission (quality)

| # | Item | Current state | Impact |
|---|------|--------------|--------|
| **S1** | Notification deep-link routing | Notification tap brings app to front only (TODO(M5.x)) | Reviewer tests notification tap; routing to the related content is expected |
| **S2** | Message store persistence | In-memory only (TODO: M4); messages re-fetch on every launch | Users notice extra network round-trip on every launch |
| **S3** | "Following" scope on timeline | Scope picker shows "Following" — not yet wired | Must show a graceful "Coming Soon" state, not an error or crash |
| **S4** | Browser OAuth linking explanation | Opens browser with no in-app context | Reviewer may flag; add inline explanation before the "Link account" action |

### 5c. Step-by-step submission process

**Phase A — Local preparation:**

1. Complete all blockers B1–B8
2. Verify Sparkle is fully removed:
   ```sh
   grep -rn "Sparkle\|SPU\|SUFeedURL\|SUPublicEDKeyString" \
     App/ InterlinedList.xcodeproj/project.pbxproj \
     InterlinedList.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
   # Must return zero results
   ```
3. Archive in Xcode: Product → Archive. Confirm signing identity in Organizer shows **Apple Distribution**, not Apple Development.
4. Validate: Organizer → select archive → Distribute App → App Store Connect → Next → **Validate App**. Fix any issues.
5. Upload: Distribute App → App Store Connect → Next → **Upload**. Processing takes 5–30 minutes.

**Phase B — App Store Connect:**

6. Register bundle ID `com.interlinedlist.macos` at developer.apple.com → Identifiers (if not already registered). Enable: App Sandbox, Hardened Runtime.
7. Create app record: appstoreconnect.apple.com → My Apps → "+" → New App → Platform: macOS → Bundle ID: `com.interlinedlist.macos` → SKU: `interlinedlist-macos-001`.
8. Fill in all metadata (see §6 for copy and character limits).
9. Upload screenshots (see §6a for dimensions).
10. Answer Privacy Nutrition Label questionnaire (see §10 for guidance).
11. Complete App Review Information:
    - **Demo account**: provide an email and password for a pre-created account provisioned with **subscriber access** (so reviewers can test subscriber-gated features: media attachments, cross-posting, scheduled posts, organizations).
    - **Notes**: "Settings > Linked Accounts opens the default browser for OAuth authorization — return to the Settings panel after authorizing. The 'Following' timeline scope shows a Coming Soon state. Watcher invite by handle and scheduled post cancel/reschedule are pending backend features; the UI reflects their unavailability."
    - **Contact**: phone number and email reachable during review.
12. Select the processed build on the Version page.
13. Submit for Review. First-time submissions typically take 2–5 business days. Budget for at least one rejection round-trip.

**Phase C — Post-approval:**

14. Release (recommend "Manually release this version" — gives control over timing). Propagation takes 1–24 hours.
15. Monitor Xcode Organizer → Crashes for the first 48 hours.
16. Plan v1.1 update within 2–4 weeks based on initial feedback.

---

## 6. Required App Store Assets

### 6a. Screenshots

The Mac App Store accepts screenshots at four pixel dimensions. At least 1 is required; up to 10 per localization.

| Size | Pixels | When to use |
|------|--------|-------------|
| Standard | 1280 × 800 | Minimum accepted |
| Standard | 1440 × 900 | Older non-Retina hardware |
| Retina (recommended) | 2560 × 1600 | MacBook Pro 13" Retina — most common submission |
| Retina | 2880 × 1800 | MacBook Pro 15"/16" Retina |

**Capture at 2560 × 1600** using a MacBook with a built-in Retina display. Use macOS Screenshot.app (Shift-Command-4, then Spacebar to select a window). Do not capture on a 4K external display.

**Suggested 10-screenshot sequence:**

| # | Screen | What to show |
|---|--------|-------------|
| 1 | Timeline | All scope, rich feed with tags, reactions, reposts visible |
| 2 | Compose | New post with Markdown preview visible and visibility toggle open |
| 3 | Lists | List table view with schema editor panel open |
| 4 | Documents | Split editor/preview with formatted Markdown document |
| 5 | Social | Profile page with follow counts and roster |
| 6 | Notifications | Notifications tray with unread items; Dock badge visible |
| 7 | Settings | Linked accounts pane showing connected social providers |
| 8 | Organizations | Organization detail with member list and role picker |
| 9 | Scheduled Posts | Scheduled sidebar section showing upcoming posts |
| 10 | Cross-post Compose | Composer with Mastodon + Bluesky toggles enabled |

Store files at `brand-kit/screenshots/appstore/` (add to `.gitignore` if sizes are large).

### 6b. App Icon

**Already complete.** All 10 macOS icon sizes are present in `App/Resources/Assets.xcassets/AppIcon.appiconset/`. No action needed.

### 6c. App Store Metadata

| Field | Limit | Suggested value |
|-------|-------|----------------|
| **App Name** | 30 chars | `InterlinedList` (14 chars) |
| **Subtitle** | 30 chars | `Notes, Lists & Documents` (24 chars) |
| **Promotional Text** | 170 chars | Can update without new app version. Suggested: `Write posts, build structured lists, and keep documents in sync — all in a fast native macOS app with full keyboard-first workflows.` |
| **Keywords** | 100 chars | `social,notes,lists,documents,markdown,structured,posts,timeline,organization,sync` (82 chars) |
| **Description** | 4000 chars | See draft below |
| **Privacy Policy URL** | URL | `https://interlinedlist.com/privacy` |
| **Support URL** | URL | `https://interlinedlist.com/support` |
| **Marketing URL** | URL (optional) | `https://interlinedlist.com` |
| **Copyright** | Text | `© 2026 InterlinedList` |
| **Primary Category** | Picker | Social Networking |
| **Secondary Category** | Picker (optional) | Productivity |
| **Age Rating** | Questionnaire | Expect 12+ for social + user-generated content — answer honestly |

### 6d. Description Draft

```
InterlinedList brings your feed, structured lists, and Markdown documents
together in one fast native macOS app — built for keyboard-first workflows
on macOS 15 Sequoia.

TIMELINE & POSTS
Write and publish posts with Markdown formatting, tags, and configurable
visibility. Reply to threads, react with "I Dig!", and repost. Schedule
posts for later. Cross-post to Mastodon, Bluesky, or LinkedIn with a toggle.

STRUCTURED LISTS
Build lists with a custom schema — choose columns, types, and constraints.
Connect lists to each other, manage watchers and roles, and refresh
GitHub-backed lists on demand.

DOCUMENTS
A Markdown editor with live preview, folder organization, and a sync engine
that keeps your documents consistent. Works offline; syncs when reconnected.

SOCIAL
Follow people, see who follows you, browse public profiles, and manage
follow requests from private accounts.

ORGANIZATIONS
Create and manage organizations, invite members, and assign roles — owner,
admin, or member.

NOTIFICATIONS
In-app tray plus native macOS notification banners, Dock badge, and
mark-all-read. All standard macOS notification controls apply.

DATA EXPORTS
Export messages, lists, list data, and social graph as CSV from File > Export.

LINKED ACCOUNTS
Connect GitHub, Mastodon, Bluesky, and LinkedIn from Settings > Linked
Accounts to enable cross-posting and social features.

macOS 15 Sequoia required.
```

### 6e. Privacy Policy

A privacy policy is required for Social Networking apps. Must be published at a stable URL before the submission form can be completed. At minimum it must address:

- What is collected: email address (authentication), user-generated content (posts, lists, documents)
- How data is stored and protected
- Third-party sharing: content is sent to Mastodon/Bluesky/LinkedIn only when the user explicitly triggers cross-posting
- User rights: account deletion is available in Settings → Account
- Contact information for privacy inquiries

---

## 7. Technical Changes Required for App Store

### 7a. Remove Sparkle (Blocker B1)

Sparkle is wired in six locations. All must be removed together.

**`InterlinedList.xcodeproj/project.pbxproj`** — Remove three entries:
- `XCRemoteSwiftPackageReference "Sparkle"` object + its `packageReferences` array entry on the project object
- `XCSwiftPackageProductDependency "Sparkle"` object + its `packageProductDependencies` array entry on the app target
- `PBXBuildFile "Sparkle in Frameworks"` object + its entry in the Frameworks build phase `files` array

**`Package.resolved`** — Remove the entire `"sparkle"` pin block (identity `"sparkle"`, version `"2.9.4"`).

**`App/Resources/Info.plist`** — Remove `SUFeedURL`, `SUPublicEDKeyString`, and the Sparkle checklist comment block.

**`App/Composition/SparkleController.swift`** — Delete this file entirely.

**`App/MenuCommands/UpdatesMenuCommands.swift`** — Delete this file entirely.

**`App/InterlinedListApp.swift`** — Remove two lines:
- `@StateObject private var sparkleController = SparkleController()`
- `UpdatesMenuCommands(sparkleController: sparkleController)` inside `.commands`

### 7b. Change Release Signing Identity (Blocker B3)

In `InterlinedList.xcodeproj/project.pbxproj`, Release config `BABD889F011D2EE21B755131`:

```
// Change this:
"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development";

// To this:
"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Distribution";
```

Debug config (`5FF8F565B0D584C9B40E9186`) stays `"Apple Development"`. `CODE_SIGN_STYLE = Automatic` and `DEVELOPMENT_TEAM = BJA9558E4B` stay unchanged.

### 7c. Create App Store Export Options Plist (Blocker B2)

Create `scripts/ExportOptions-AppStore.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>BJA9558E4B</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>uploadBitcode</key>
    <false/>
</dict>
</plist>
```

### 7d. Create PrivacyInfo.xcprivacy (Blocker B4)

Create `App/Resources/PrivacyInfo.xcprivacy`. The filesystem-synchronized group picks it up automatically — no `project.pbxproj` edit needed.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <!-- DocumentSyncEngine reads file modification dates for conflict detection -->
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeEmailAddress</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeOtherUserContent</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

After the first build, verify whether the `Textual` dependency ships its own manifest:

```sh
find ~/Library/Developer/Xcode/DerivedData -name "PrivacyInfo.xcprivacy" -path "*textual*"
```

If no result, audit Textual's source for required-reason API usage and add those to `PrivacyInfo.xcprivacy`.

### 7e. Fix Version Inconsistency (Blocker B5)

In `App/Resources/Info.plist`, change `CFBundleShortVersionString` from the hardcoded `0.0.1` to `$(MARKETING_VERSION)`.

For the App Store debut, update `MARKETING_VERSION` in `project.pbxproj` to `1.0` (both Debug and Release configs) and increment `CURRENT_PROJECT_VERSION` from `1` to `2`.

### 7f. App Store CI/CD Workflow

Create `.github/workflows/appstore.yml` (triggered by `workflow_dispatch` or `appstore-v*` tag). Secrets needed: `APPSTORE_CERTIFICATES_P12`, `APPSTORE_CERTIFICATES_P12_PASSWORD`, `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`, `ASC_API_KEY_P8`, `APPLE_TEAM_ID`.

The workflow mirrors `release.yml` but uses the App Store certificates and calls `xcodebuild -exportArchive` with `scripts/ExportOptions-AppStore.plist`. Upload via `xcrun altool` or the App Store Connect API.

---

## 8. Cost Breakdown

### All channels

| Item | Cost | Frequency |
|------|------|-----------|
| Apple Developer Program | $99 USD | Annual (required for all distribution; already needed for Developer ID) |
| macOS Screenshot.app | $0 | Built in |
| Privacy policy hosting | $0 | Page on existing `interlinedlist.com` |
| Sparkle CLI tools | $0 | Open source |
| Fastlane | $0 | Optional open-source automation, not currently configured |

### Developer ID (PKG + DMG only)

| Item | Cost |
|------|------|
| GitHub Actions compute | Free tier or standard minutes; each release run is approximately 15–20 minutes on macOS |
| Download hosting at `interlinedlist.com/downloads/apple/` | Hosting plan cost (already existing site) |

### Mac App Store only

| Item | Cost |
|------|------|
| App Store commission on IAP | **0%** — subscription is server-side; no StoreKit IAP exists. App Store commission does not apply. |
| Legal review of privacy policy | Variable — internal if team writes it |
| Screenshot design/polish | $0–$200 — raw captures are free; device frames/annotations are optional |

**Total hard Apple cost: $99/year** across all channels (one program membership covers everything).

**Important**: App Review Guideline 3.1.3(b) permits server-side subscriptions. Ensure no "Subscribe" button, link, or URL pointing to a payment page appears within the app. Safe phrasing on entitlement gates: "available for subscribers" — no link, no button, no external URL.

---

## 9. Phased Approach Recommendation

### Why phase

Six backend-blocked features (NW-1 through NW-6) cannot ship without upstream API changes. The core experience — timeline, compose, lists, documents, social, notifications, exports, and subscriber gating — is complete and worth shipping on all channels now. Waiting for NW items delays distribution indefinitely.

### Phase 1 — First release on all channels (ship now)

**Includes:** All M0–M7 features as shipped. See §2a for the full feature list.  
**Excludes:** NW-1 through NW-6 (all backend-blocked; documented in `docs/user/feature-status.md`).

**Version:** `1.0` (bump `MARKETING_VERSION` from `0.1.0`; `CURRENT_PROJECT_VERSION` → `2`).

For the Developer ID channel: this is the first public release. The existing `0.0.1 Alpha` label in the appcast was an internal test artifact.

For the App Store channel: `1.0` is the right number for a production-ready first submission. The alpha history is irrelevant to App Store users.

### Phase 2 — Source code TODOs (1–2 sprints)

| Work | Target | File |
|------|--------|------|
| Notification deep-link routing to specific content | v1.1 | `App/Composition/AppDelegate.swift` TODO(M5.x) |
| Message store persistence (swap in-memory for SwiftData on-disk) | v1.1 | `App/Composition/AppEnvironment.swift` TODO: M4 |
| Force-directed connections graph layout | v1.1 | `App/Features/Lists/ListConnectionsViewModel.swift` TODO(M3.x) |

### Phase 3 — Backend unlocks (as APIs land)

| NW | Feature | Trigger | Target version |
|----|---------|---------|---------------|
| NW-1 + NW-6 | Watcher invite by handle + Org member-add by handle | `GET /api/users/lookup?handle=` or `/search?q=` | v1.2 |
| NW-2 | Cross-post per-platform status sheet | `POST /api/messages` returns `crossPosts` envelope | v1.2 |
| NW-3 | Scheduled post cancel/reschedule | Cancel/reschedule API semantics confirmed | v1.3 |
| NW-4 | Bluesky/Mastodon readiness detection | Status endpoints available | v1.3 |
| NW-5 | Native in-app OAuth identity linking | Custom-scheme callback or bearer link endpoint | v1.4 |

### Maintaining both channels

The Developer ID pipeline (`scripts/notarize-and-package.sh`, Sparkle, `releases/appcast.xml`) must stay active for users who downloaded via PKG/DMG. These users cannot receive App Store updates automatically.

**Recommended migration strategy:**
1. Ship a final Developer ID release containing a visible in-app notice directing users to the Mac App Store
2. Update `releases/appcast.xml` to point to the App Store product page or a migration guide at `interlinedlist.com`
3. Retire the Sparkle feed after a reasonable window (e.g., 60 days)

**Branch strategy** (if patching Developer ID channel post-App Store launch):
- `main` — App Store build (no Sparkle, method = `app-store-connect`)
- `developer-id` — Sparkle build, cherry-pick critical fixes from `main`

The cleaner long-term approach: one final Developer ID release with migration notice, then converge to App Store only.

---

## 10. App Review Guidelines Considerations

InterlinedList is `public.app-category.social-networking`. Social networking apps receive additional scrutiny under several guidelines.

### Guideline 1.2 — User-Generated Content

**Applies.** The app allows users to post messages, create lists, and write documents. Apple requires:

1. **Report mechanism** — the most common first-submission rejection reason for social apps. If the backend has a report endpoint, add a "Report" option to the message context menu before submission. If not, include the reporting website URL in the App Review notes and explain the moderation process.
2. **Block mechanism** — follow/unfollow is already implemented. If a "block user" endpoint is added before submission, surfacing it strengthens the case.
3. **Age gate** — the responsibility falls on the backend's registration flow. Confirm the Terms of Service require users to be 13 or older.

### Guideline 4.8 — Sign In with Apple

**Does not apply** to InterlinedList's primary authentication. The primary account creation and sign-in uses email + password. OAuth linking for GitHub, Mastodon, Bluesky, and LinkedIn happens in Settings, after the user already has an authenticated session — these are post-authentication account links, not primary credentials.

If App Review asks: "Users sign in with their InterlinedList email and password. OAuth connections to third-party services are optional linked accounts for social features, not authentication credentials."

### Guideline 3.1.1 — In-App Purchases

**Server-side subscription — no StoreKit.** Under Guideline 3.1.3(b) ("Multiplatform Services"), server-side subscriptions are permitted provided the app does not link to or mention the external purchase mechanism from within the app.

Audit every subscriber-gated screen for:
- "Subscribe" buttons or links — **must not exist**
- "Upgrade your plan" buttons or links — **must not exist**
- Any URL pointing to a payment page — **must not exist**

Safe phrasing: "This feature is available for subscribers." No call to action. No link.

### Guideline 5.1.1 — Privacy

The Privacy Nutrition Label questionnaire must match what the app actually does:
- Email address — linked to user, not tracking — authentication
- User-generated content — linked to user, not tracking — app functionality
- Bearer token — stored in Keychain, not transmitted to third parties — not a collected data type for label purposes

Cross-posting sends content to Mastodon/Bluesky/LinkedIn only when the user explicitly triggers it. This is user-directed sharing, not passive collection or advertising tracking.

### Guideline 2.1 — App Completeness

Every visible control must either work correctly or show a clear, graceful unavailable state. Specifically before submission:

- **"Following" timeline scope**: must be disabled or show a "Coming Soon" empty state when selected — not a network error, not a crash
- **Watcher invite by handle**: if any UI element for this is visible, it must show "Coming Soon", be disabled, or be absent — not silently fail when tapped

Walk through the entire app using the demo account before submitting.

### Guideline 5.1.2 — Data Handling

- Bearer token in Keychain: appropriate secure storage
- `com.apple.security.network.client`: minimal, appropriate for an API-driven app
- `com.apple.security.files.user-selected.read-write`: appropriate for document import/export and CSV export

No entitlement changes are needed for App Store submission.
