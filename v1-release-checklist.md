# InterlinedList macOS — v1 Release Checklist

Work through this file top-to-bottom. Check each item when done.
Sections are ordered by dependency: complete earlier sections before starting later ones.

**Test baseline:** 354 App · 223 Kit · 432 Domain · 120 Persistence — all passing.  
**Build:** clean as of 2026-07-08.

---

## 1. Code — App Features

All macOS-side feature work. These run against `dev` branch.

### Core milestones
- [x] M0 — Auth, onboarding, brand, CI
- [x] M1 — Timeline (All / Mine), threads, public list browsing, profile header
- [x] M2 — Composer, Markdown, tags, visibility, replies, reactions, reposts, edit/delete
- [x] M3 — Lists CRUD, schema editor, rows table, nested lists, connections graph, watchers/sharing, GitHub refresh
- [x] M4 — Documents: folder tree, Markdown editor, image upload, offline sync engine
- [x] M5 — Follow/unfollow, follower/following lists, follow requests, notifications tray, system banners, Dock badge
- [x] M6 — Media attachments, scheduled posts, cross-posting, browser-handoff OAuth linking, organizations + roles, entitlement gating
- [x] M7 — CSV exports, Settings polish, sandboxing, hardened runtime, notarization pipeline, Sparkle updates, accessibility, brand QA

### Post-milestone features (now complete)
- [x] NW-1 — Watcher invite by @handle on Lists share sheet
- [x] NW-2 — Cross-post per-platform status sheet after publish
- [x] NW-3 — Scheduled post cancel and reschedule
- [x] NW-4 — Bluesky and Mastodon cross-post readiness detection in composer
- [x] NW-6 — Org member-add by @handle
- [x] S1 — Notification deep-link routing (tap banner → navigate to content)
- [x] S3 — "Following" timeline scope with Coming Soon empty state (App Review Guideline 2.1)
- [x] S4 — Browser-open explanation in Settings → Linked Accounts
- [x] B8 — Report mechanism: "Report…" context menu item on every message (App Review Guideline 1.2)
- [x] P2-B — Follow action response shape mapping (`{ follow: { status } }`)
- [x] P3-E — Rate-limit header nil-guard in sync transport

### Deployment file fixes (complete)
- [x] B4 — `App/Resources/PrivacyInfo.xcprivacy` created
- [x] B5 — `CFBundleShortVersionString` → `$(MARKETING_VERSION)` in Info.plist
- [x] `scripts/export-options.plist` — Team ID filled in (`BJA9558E4B`)
- [x] `scripts/ExportOptions-AppStore.plist` — created for App Store export path

### Remaining code items
- [ ] S2 — Message store persistence: swap in-memory message store for SwiftData on-disk container (`AppEnvironment.swift:208` TODO M4). Users see a network round-trip on every launch without this. *Not a hard blocker for v1 PKG/DMG.*
- [ ] NW-5 — Native in-app OAuth identity linking via `ASWebAuthenticationSession`. *Blocked on backend P1-E — browser-handoff fallback already ships.*
- [ ] M3.x — Force-directed connections graph layout (`ListConnectionsViewModel.swift:16`). *Visual polish, non-blocking.*
- [ ] SUPublicEDKeyString — paste the Ed25519 public key into `App/Resources/Info.plist` once generated (see Section 2).

---

## 2. Infrastructure — Developer ID (PKG + DMG)

One-time setup required on the build machine. Run in order.

- [ ] **Generate Sparkle key pair.** Run `./bin/generate_keys` (from Sparkle CLI tools). Output: a private key (store in password manager — never commit) and a public key.
- [ ] **Paste public key.** Copy the public key from above into `App/Resources/Info.plist` → `SUPublicEDKeyString` (currently `TODO_REPLACE_WITH_ED25519_PUBLIC_KEY`).
- [ ] **Store notarization credentials.** Run `scripts/store-notarization-profile.sh` with your Apple ID, Team ID (`BJA9558E4B`), and app-specific password. Creates a `NotarizationProfile` Keychain item.
- [ ] **GitHub Actions secrets.** Add all secrets listed in `App-Dmg-Pkg-Deployment.md` §1b:
  - [ ] `CERTIFICATES_P12` (base64 of Developer ID Application + Installer .p12)
  - [ ] `CERTIFICATES_P12_PASSWORD`
  - [ ] `CODESIGN_IDENTITY` (e.g. `"Developer ID Application: Your Name (BJA9558E4B)"`)
  - [ ] `INSTALLER_IDENTITY` (e.g. `"Developer ID Installer: Your Name (BJA9558E4B)"`)
  - [ ] `NOTARIZATION_PASSWORD` (app-specific password)
- [ ] **Test local build.** Run `scripts/notarize-and-package.sh` with the required env vars (§3b in `App-Dmg-Pkg-Deployment.md`). Produces `.pkg` and `.dmg` in `releases/`.
- [ ] **Sign with Sparkle.** Run `./bin/sign_update releases/InterlinedList-<version>.pkg`. Copy the `edSignature` and byte count into `releases/appcast.xml` (replace `TODO_REPLACE_WITH_SIGNATURE` and `length="0"`).
- [ ] **Upload artifacts.** Copy `.pkg`, `.dmg`, and `.sha256` files to `https://interlinedlist.com/downloads/apple/`.
- [ ] **Publish appcast.** Upload `releases/appcast.xml` to `https://interlinedlist.com/appcast.xml`.
- [ ] **Tag and push release.** `git tag v1.0.0 && git push origin v1.0.0` — triggers `release.yml` workflow which creates a draft GitHub release.
- [ ] **Publish GitHub release.** Review and publish the draft via GitHub UI or `gh release edit`.

---

## 3. Infrastructure — App Store (additional steps)

Do these on an `app-store` branch. Removing Sparkle breaks the PKG/DMG channel.

### Code changes (on `app-store` branch)
- [ ] **B1 — Remove Sparkle.** Six locations (see `App-Dmg-Pkg-Deployment.md` §7a):
  - [ ] `project.pbxproj` — remove XCRemoteSwiftPackageReference, XCSwiftPackageProductDependency, PBXBuildFile for Sparkle
  - [ ] `Package.resolved` — remove the `"sparkle"` pin block
  - [ ] `App/Resources/Info.plist` — remove `SUFeedURL`, `SUPublicEDKeyString`, and the Sparkle comment block
  - [ ] `App/Composition/SparkleController.swift` — delete file
  - [ ] `App/MenuCommands/UpdatesMenuCommands.swift` — delete file
  - [ ] `App/InterlinedListApp.swift` — remove `@StateObject var sparkleController` and `UpdatesMenuCommands(…)` from `.commands`
- [ ] **B3 — Change Release signing identity.** In `project.pbxproj` Release config `BABD889F`: change `CODE_SIGN_IDENTITY[sdk=macosx*]` from `"Apple Development"` to `"Apple Distribution"`.
- [ ] **Version bump.** In `project.pbxproj`, set `MARKETING_VERSION` to `1.0` and `CURRENT_PROJECT_VERSION` to `2` in both Debug and Release configs.

### GitHub Actions secrets (App Store)
- [ ] `APPSTORE_CERTIFICATES_P12` (base64 of Apple Distribution .p12)
- [ ] `APPSTORE_CERTIFICATES_P12_PASSWORD`
- [ ] `ASC_API_KEY_ID`
- [ ] `ASC_API_ISSUER_ID`
- [ ] `ASC_API_KEY_P8` (base64 of the .p8 file — downloadable only once at creation)

### App Store Connect setup
- [ ] Register bundle ID `com.interlinedlist.macos` at developer.apple.com → Identifiers (enable App Sandbox, Hardened Runtime).
- [ ] Create app record: appstoreconnect.apple.com → My Apps → New App → macOS → Bundle ID: `com.interlinedlist.macos` → SKU: `interlinedlist-macos-001`.
- [ ] Fill in metadata (see `App-Dmg-Pkg-Deployment.md` §6c for copy + character limits): App Name, Subtitle, Promotional Text, Keywords, Description, Copyright, Categories.
- [ ] Upload screenshots — minimum 1, recommend 10 at 2560×1600 (see §6a for suggested sequence). Store in `brand-kit/screenshots/appstore/`.
- [ ] Complete Privacy Nutrition Label questionnaire (§10 in deployment doc).
- [ ] Archive in Xcode → Product → Archive. Confirm Organizer shows **Apple Distribution** signing.
- [ ] Validate archive in Organizer → Distribute App → App Store Connect → Validate App.
- [ ] Upload archive → Distribute App → App Store Connect → Upload.
- [ ] Select uploaded build on Version page in App Store Connect.
- [ ] Fill in App Review Information: demo account credentials (email + password with subscriber access), review notes, contact phone and email.
- [ ] Submit for Review.

---

## 4. Website

Required before App Store submission; B6 and B7 are hard blockers for the submission form.

- [ ] **B6 — Publish Privacy Policy** at `https://interlinedlist.com/privacy`. Must cover: data collected, storage, third-party sharing (cross-posting is user-triggered only), user rights (account deletion in Settings), contact info, effective date.
- [ ] **B7 — Publish Support page** at `https://interlinedlist.com/support`. Must provide: contact method, help docs links, how to report bugs.
- [ ] Verify both URLs return 200 without login (Apple checks during review).

---

## 5. Backend

- [ ] **Run migrations.** On the production database: `npm run db:migrate:deploy`. Two pending migrations: `add_moderation_tables`, `add_moderation_versioning_sessions`.
- [ ] **P1-F — Auth decision.** `GET /api/messages` returns 200 unauthenticated. Confirm this is intentional (public timeline) or lock it down (see `blocker-prompts.md` P1-F prompt).

### Nice-to-have before v1 (not blocking)
- [ ] P2-B — Add `followedBy` to follow action response (eliminates one round-trip per follow).
- [ ] P2-C — Document notification type enum + add `routePath` field (enables APNs push deep-linking).
- [ ] P2-D — `GET /api/limits` endpoint (removes hard-coded upload limit constants in macOS).
- [ ] P3-E — Extend `RateLimit-*` headers to all authenticated routes (macOS already handles absent headers correctly).

### Future (unblock NW-5)
- [ ] P1-E — Native OAuth callback (`interlinedlist://` scheme or `POST /api/auth/{provider}/link`). See `blocker-prompts.md` P1-E prompt.

---

## 6. Demo Account

Required for App Store submission (App Review step).

- [ ] Create a dedicated reviewer account on `interlinedlist.com` with:
  - A recognizable display name (e.g. "App Review Demo")
  - Subscriber access enabled (so reviewers can test media attachments, cross-posting, scheduled posts, organizations)
  - At least a few sample posts, one list with rows, and one document
- [ ] Record the email address and password for App Review Information in App Store Connect (§5c step 11).
- [ ] Note in App Review notes: "Settings → Linked Accounts opens the default browser for OAuth — return to InterlinedList when done. The 'Following' timeline scope shows a Coming Soon state (backend feed not yet available). NW-5 native OAuth linking is pending a backend API change."

---

## Completion Criteria for v1

**PKG/DMG release:** Sections 1 (all ✅ plus SUPublicEDKeyString) and 2 fully checked.  
**App Store release:** All six sections fully checked.
