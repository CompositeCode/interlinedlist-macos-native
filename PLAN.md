# InterlinedList for macOS — Implementation Plan

A native macOS client implementing the full [InterlinedList API](https://interlinedlist.com/help/api) with feature parity to the web application, built with Swift, SwiftUI, and platform-native conventions.

---

## 1. Product Scope

Mirror every capability the web app exposes, organized as native macOS features:

| Web Feature | API Surface | macOS Treatment |
| --- | --- | --- |
| Timeline / feed | `GET /api/messages` (+ `onlyMine`, `tag` filters) | Main window content list, infinite scroll, feed scope picker (All / Following / Mine) |
| Compose posts | `POST /api/messages` | Dedicated compose window (⌘N), Markdown, tag tokens, visibility toggle |
| Replies & threads | `/api/messages/[id]/replies`, `parentId` | Threaded detail view, inline reply |
| "I Dig!" reactions | `POST/DELETE /api/messages/[id]/dig` | One-click toggle, optimistic UI |
| Reposts | `pushedMessageId` | Repost action in message context menu |
| Media attachments | `images/upload`, `videos/upload` | Drag-and-drop + file picker; client-side pre-resize to meet limits (images ≤1.4 MB/1200px, video ≤3 MB) |
| Scheduled posts | `scheduledAt`, `GET /api/messages/scheduled` | Date picker in composer; "Scheduled" sidebar section (today/week/month) |
| Cross-posting | `mastodonProviderIds`, `crossPostToBluesky`, `crossPostToLinkedIn` | Per-message platform checkboxes; per-platform result status after publish |
| Structured lists | `/api/lists/*` + schema DSL | SwiftUI `Table` grid view, card view, schema editor, row inspector panel |
| List connections | `/api/lists/connections` | Graph/ERD canvas view of connected lists |
| Nested lists | `parentId` on lists | Disclosure hierarchy in sidebar |
| List sharing | `/api/lists/[id]/watchers/*` | Share sheet–style access panel with role management |
| GitHub-backed lists | `POST /api/lists/[id]/refresh` | Refresh toolbar button + auto-refresh option |
| Public list browsing | `GET /api/users/[username]/lists*` (no auth) | "Browse user" — view any user's public lists without auth |
| Documents | `/api/documents/*`, folders | Folder source list + split Markdown editor/preview; offline-first |
| Document sync | `GET/POST /api/documents/sync` (delta) | Background sync engine; this is the app's offline backbone |
| Follow system | `/api/follow/*` | Follow/unfollow on profiles, follower/following lists, request approval for private accounts |
| Organizations | `/api/organizations/*` | Org switcher, member management with roles (owner/admin/member) |
| Notifications | `/api/notifications*` | Sidebar badge + native `UNUserNotification` delivery; mark read / mark all |
| Profile & account | `/api/user/*` | Native Settings window: profile, avatar, linked identities, email change, account deletion |
| Exports | `/api/exports/*` (CSV) | File → Export menu with `NSSavePanel` |
| Auth | login, register, sync-token, password reset, email verification, OAuth | Onboarding window; Bearer token in Keychain; OAuth via `ASWebAuthenticationSession` |
| Subscriber gating | `customerStatus` | Feature-flag layer: hide/disable subscriber UI for free accounts, friendly 403 handling |

Every documented endpoint maps to a feature above — full API coverage is a tracked deliverable (see §7 coverage matrix discipline).

---

## 2. Platform & Tooling Decisions

- **macOS 14 (Sonoma) minimum** — unlocks `@Observable`, SwiftData, mature `NavigationSplitView` and `Table`.
- **Swift 6 toolchain** with strict concurrency checking.
- **SwiftUI-first**, AppKit interop where SwiftUI falls short (rich Markdown editing via `NSTextView`, the connections graph canvas).
- **SwiftData** for the local cache and document store.
- **Keychain** for the bearer token (`il_tok_…` does not expire — protect it accordingly; never UserDefaults).
- **URLSession + async/await** — no third-party networking dependency.
- **XCTest** with BDD naming (`test_givenX_whenY_thenZ`) per project standards.
- Distribution target: **Developer ID + notarization** first (Sparkle for updates), App Store evaluated later (sandbox entitlements planned from day one so the door stays open).

---

## 3. Architecture

Three local Swift packages plus the app target — protocol boundaries at every seam, dependencies point inward:

```text
interlinedlist-macos-native/
├── InterlinedList.xcodeproj
├── App/                              # App target — UI only
│   ├── InterlinedListApp.swift       # @main, Scenes: MainWindow, Compose, Settings
│   ├── Navigation/                   # Sidebar model, deep-link routing
│   └── Features/
│       ├── Timeline/                 # Feed, message cards, thread detail
│       ├── Compose/                  # Composer window, media, scheduling, cross-post
│       ├── Lists/                    # Grid/card views, schema editor, watchers, graph
│       ├── Documents/                # Folder tree, editor, preview
│       ├── Social/                   # Profiles, follow lists, requests
│       ├── Organizations/
│       ├── Notifications/
│       ├── Settings/                 # Account, identities, subscription status
│       └── Onboarding/               # Login, register, OAuth, password reset
├── Packages/
│   ├── InterlinedKit/                # API layer (no app dependencies)
│   │   ├── APIClient                 # protocol + URLSession implementation
│   │   ├── Endpoints/                # One enum case / request builder per endpoint group
│   │   ├── DTOs/                     # Codable types mirroring API objects exactly
│   │   ├── Auth/                     # TokenStore (Keychain), AuthService, OAuth flows
│   │   ├── Pagination/               # limit/offset page iterator
│   │   └── Errors/                   # APIError mapping ({error} body + status codes)
│   ├── InterlinedDomain/             # Business logic (depends on InterlinedKit protocols)
│   │   ├── Models/                   # App-facing models (separate from DTOs)
│   │   └── Services/                 # MessagesService, ListsService, DocumentsService,
│   │                                 #   SocialService, OrgService, NotificationsService…
│   └── InterlinedPersistence/        # SwiftData schemas, cache policy, DocumentSyncEngine
└── Tests/                            # Unit tests per package + integration suite
```

**Key boundaries:**

- DTOs never cross into the UI; domain models do. Schema DSL parsing (`"Title:text, Year:number"`) lives in Domain with exhaustive tests.
- Every service takes its `APIClient` as a protocol — all unit tests run against stubs.
- `DocumentSyncEngine` is the one place that touches `/api/documents/sync`; it owns `lastSyncAt`, applies the `deleted` flag, queues local edits for batch `POST`, and resolves conflicts (server-wins with local-copy preservation, v1).
- `EntitlementsService` wraps `customerStatus` so feature gating is one switch, not scattered `if` checks.

---

## 4. Authentication Strategy (and the one open risk)

The app authenticates via `POST /api/auth/sync-token` → Bearer token, the documented path for desktop apps.

**⚠️ Open question to resolve in M0:** the API docs mark several endpoint groups *Session-only* (replies, digs, follow, organizations, notifications, document CRUD), while others accept *Session or Bearer*. Either the docs understate Bearer support, or the app must also maintain a session cookie. **M0 includes a spike: probe each Session-only endpoint with a Bearer token against the live API and record results.** Fallback design if Bearer is truly rejected: perform `POST /api/auth/login` alongside token fetch and let `URLSession` manage the `HttpOnly` cookie, refreshing on 401.

OAuth (GitHub, Mastodon, Bluesky, LinkedIn) is link-account-only in v1, via `ASWebAuthenticationSession` against the `/api/auth/*/authorize?link=true` flows. Mastodon prompts for an instance hostname first.

---

## 5. Native macOS Experience

- **Main window:** `NavigationSplitView` — sidebar (Timeline, Scheduled, Notifications, Lists, Documents, Organizations, Profile) → content list → detail/inspector.
- **Composer:** separate `Window` scene, ⌘N anywhere, ⌘↩ to publish.
- **Settings:** native `Settings` scene (⌘,) — Account, Identities, Posting defaults, Subscription.
- **Menu bar:** full command set — File (New Post, New List, New Document, Export…), Edit, View (feed scope, list view mode), Go (sidebar sections with ⌘1–⌘7).
- **System integration:** UNUserNotifications for digs/replies/follows; dock badge for unread; drag-and-drop images into composer and documents; Quick Look on attachments; Handoff/universal links to `interlinedlist.com` URLs.
- **Offline:** Documents fully offline-capable via the sync engine; timeline and lists read from SwiftData cache with stale-while-revalidate.
- HIG compliance throughout — keyboard navigable, Dynamic Type, VoiceOver labels on all interactive elements.

---

## 6. Milestones

Each milestone ships a usable increment with tests; later milestones don't block earlier ones from being demoed.

| # | Milestone | Contents |
| --- | --- | --- |
| **M0** | Foundation | Xcode project + 3 SPM packages, CI (GitHub Actions: build + test), `APIClient`, auth (token + Keychain), error mapping, pagination, **Bearer-vs-Session spike**, onboarding window (login/register/reset), brand asset catalog from official kit (§9) |
| **M1** | Read-only core | Timeline (all/mine/tag), message detail + threads, user profiles, public list browsing, SwiftData caching |
| **M2** | Posting | Composer (text, Markdown, tags, visibility), replies, digs, reposts, delete/edit own messages |
| **M3** | Lists | Lists CRUD, schema DSL parser + editor, rows table (Table view), row inspector, nesting, connections graph, watchers/sharing, GitHub refresh |
| **M4** | Documents | Folder tree, Markdown editor + preview, image upload, **DocumentSyncEngine with delta sync + offline queue** |
| **M5** | Social & notifications | Follow/unfollow, requests (private accounts), follower lists, mutuals, notifications tray + native notifications + badge |
| **M6** | Subscriber & orgs | Media attachments (with client-side resize), scheduled posts, cross-posting (Mastodon/Bluesky/LinkedIn), OAuth identity linking, organizations + member roles, entitlement gating |
| **M7** | Ship | CSV exports, Settings polish (email change, account deletion, avatar), sandboxing + hardened runtime, notarization, Sparkle updates, accessibility audit, brand QA pass (§9) |

---

## 7. Testing & Quality

- **Unit tests** (BDD naming) for every service against `APIClient` stubs — minimum coverage per behavior: happy path, invalid input, API failure, empty/boundary.
- **Schema DSL parser** and **sync engine** get the deepest test suites (property-style cases for the parser; simulated delta sequences incl. deletes and conflicts for sync).
- **Contract tests:** an opt-in integration suite (env-gated) hitting the live API with a test account — this is also how the M0 auth spike and ongoing doc-drift detection run.
- **Endpoint coverage matrix:** a checked-off table in `docs/api-coverage.md` mapping every documented endpoint → implementing service → test. "Entire API" is verified, not assumed.
- Per-PR: build + tests in CI; architecture checklist from `.claude/skills/interlinedlist-macos-swift-engineer/assets/architecture-checklist.md`.

---

## 8. Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Session-only endpoints reject Bearer tokens | M0 spike; cookie-session fallback designed up front (§4) |
| Rate limits undocumented | Centralized retry/backoff in `APIClient`; respect 429 if it appears |
| Token never expires → high-value secret | Keychain with access control; revocation guidance in Settings |
| Subscriber 403s mid-flow (subscription lapses) | `EntitlementsService` + graceful 403 → re-fetch `customerStatus`, update UI |
| Media size limits (1.4 MB image / 3 MB video) | Client-side downscale/transcode before upload; clear errors when impossible |
| API drift vs docs | Contract test suite doubles as drift alarm |
| Markdown fidelity vs web rendering | Snapshot-compare rendered output against web for a corpus of real posts |

---

## 9. Branding & Visual Identity

All visual identity follows the [official branding standards](https://interlinedlist.com/help/branding). Assets come from the official brand kit (`/brand/interlinedlist-brand-kit.zip`) — never recreated, recolored, stretched, skewed, rotated, given effects, or placed on low-contrast backgrounds.

**Naming.** The product name is written **InterlinedList** — capital I, capital L, no spaces or hyphens — everywhere: bundle display name, menu bar, About window, notifications, and documentation.

**App icon.** Built from the canonical icon mark (`interlinedlist-logo-only.png` / SVG source). The kit ships 16×16–512×512; the macOS `AppIcon` set also needs 1024×1024, which M0 derives from the SVG source at full fidelity. Use the solid-background variants where macOS icon conventions require a filled shape.

**In-app logo usage** (onboarding, About window):

- `logo-light.svg` on light backgrounds, `logo-dark.svg` on dark or colored backgrounds — matched automatically to the current appearance.
- Minimum sizes: 24 pt for the icon mark, 120 pt for the full logotype.
- Clear space around the logo equal to the height of the "I" in "Interlined".

**Colors** — defined once as asset catalog Color Sets with light/dark variants:

| Role | Color | Hex |
| --- | --- | --- |
| Accent / primary actions (app `AccentColor`) | Ocean Blue | `#0F4C5F` |
| Active states, success | Emerald Green | `#34A56D` |
| Highlights, badges | Amber Gold | `#F9AF36` |
| Text / dark surfaces | Near Black | `#1A1A1A` |
| Text on dark / light surfaces | White | `#FFFFFF` |
| Dark appearance: window background | — | `#191E23` |
| Dark appearance: card background | — | `#1D2329` |
| Dark appearance: nested surface | — | `#242B33` |
| Errors (extended palette) | Alert Red | `#ED321F` |

The extended Darkone palette (violet `#7E67FE`, electric blue `#1A80F8`, teal cyan `#1AB0F8`, vivid green `#21D760`) is reserved for data visualization — list connection graphs and ERD diagrams.

**Typography.** Play (Regular 400, Bold 700; SIL OFL — bundled with the app) for headings and display text. Body and UI text use the system font (SF Pro), which is consistent with the brand's own `-apple-system` fallback stack and macOS HIG. Rendered Markdown uses 1.6 line-height for body text.

**Brand QA** is part of the M7 ship checklist: icon set verified at every size, logo clear-space audit, naming sweep, and palette contrast check in both appearances.
