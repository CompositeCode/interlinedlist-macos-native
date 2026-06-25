<p align="center">
  <img src="Brand/icon/icon-light-transparent-256.png" alt="InterlinedList" width="128" height="128">
</p>

<h1 align="center">InterlinedList for macOS</h1>

<p align="center">
  A native macOS client for <a href="https://interlinedlist.com">InterlinedList</a> &mdash; built with Swift 6, SwiftUI, and SwiftData.
</p>

<p align="center">
  <a href="https://github.com/CompositeCode/interlinedlist-macos-native/actions/workflows/ci.yml"><img src="https://github.com/CompositeCode/interlinedlist-macos-native/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status"></a>
  <a href="https://github.com/CompositeCode/interlinedlist-macos-native/actions/workflows/ci.yml?query=branch%3Adev"><img src="https://github.com/CompositeCode/interlinedlist-macos-native/actions/workflows/ci.yml/badge.svg?branch=dev" alt="CI status (dev)"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-orange.svg" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/macOS-15%2B-blue.svg" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Xcode-16.2-1575F9.svg" alt="Xcode 16.2">
</p>

<p align="center">
  <a href="https://github.com/CompositeCode/interlinedlist-macos-native/commits/dev"><img src="https://img.shields.io/github/last-commit/CompositeCode/interlinedlist-macos-native/dev" alt="Last commit"></a>
  <a href="https://github.com/CompositeCode/interlinedlist-macos-native/issues"><img src="https://img.shields.io/github/issues/CompositeCode/interlinedlist-macos-native" alt="Open issues"></a>
  <a href="https://github.com/CompositeCode/interlinedlist-macos-native/pulls"><img src="https://img.shields.io/github/issues-pr/CompositeCode/interlinedlist-macos-native" alt="Open pull requests"></a>
  <img src="https://img.shields.io/github/languages/top/CompositeCode/interlinedlist-macos-native" alt="Top language">
  <img src="https://img.shields.io/github/languages/code-size/CompositeCode/interlinedlist-macos-native" alt="Code size">
  <img src="https://img.shields.io/github/repo-size/CompositeCode/interlinedlist-macos-native" alt="Repo size">
</p>

---

## About

InterlinedList for macOS mirrors every capability of the [InterlinedList web app](https://interlinedlist.com), organized as native macOS features: a timeline, a composer window, structured lists with a schema DSL, an offline-capable Markdown document store, social and organization features, notifications, and Settings &mdash; all backed by the documented [InterlinedList API](https://interlinedlist.com/help/api).

The project is greenfield. Scope, architecture, milestones, and branding are pinned in [PLAN.md](PLAN.md); orchestration rules live in [ORCHESTRATION.md](ORCHESTRATION.md). Progress is recorded in [docs/progress.md](docs/progress.md) and endpoint coverage in [docs/api-coverage.md](docs/api-coverage.md).

## Status

| Milestone | Scope | Status |
| --- | --- | --- |
| **M0** &mdash; Foundation | Xcode project, three SPM packages, CI, auth, Keychain, brand assets | Shipped |
| **M1** &mdash; Read-only core | Timeline (all/mine/tag), threads, public list browsing, profile header | Shipped |
| **M2** &mdash; Posting | Composer (⌘N), replies, digs, reposts, edit/delete own messages | Shipped |
| **M3** &mdash; Lists | CRUD, schema DSL editor, rows table, nesting, connections graph, watchers, GitHub refresh | Shipped |
| **M4** &mdash; Documents | Folder tree, Markdown editor/preview, image upload, delta sync engine | Shipped |
| **M5** &mdash; Social & notifications | Follow/unfollow, requests, mutuals, notifications tray, dock badge | Shipped |
| **M6** &mdash; Subscriber & orgs | Media attachments, scheduled posts, cross-posting, OAuth linking, organizations | Shipped |
| **M7** &mdash; Ship | CSV exports, Settings polish, sandbox + notarization, Sparkle, accessibility, brand QA | Pending |

Endpoint coverage today: **97 / 98 implemented**, **66 / 98 fully tested**, **25 / 98 partial**. See [docs/api-coverage.md](docs/api-coverage.md) for the row-by-row matrix.

## Architecture

```text
InterlinedList.xcodeproj
App/                              # App target (UI only)
  Composition/                    # AppEnvironment composition root
  Features/                       # Timeline, Compose, Lists, Documents, Social, Orgs, Notifications, Settings, Onboarding
  MenuCommands/                   # ⌘N etc.
  Navigation/                     # Sidebar, deep-link routing
  Resources/                      # Asset catalog, fonts, Info.plist, entitlements
Packages/
  InterlinedKit/                  # API layer: APIClient, Endpoints, DTOs, Auth, Pagination, Errors
  InterlinedDomain/               # Business logic: Models + Services on top of InterlinedKit protocols
  InterlinedPersistence/          # SwiftData schemas, cache policy, document sync engine
AppTests/                         # App-target XCTest (BDD-named)
docs/                             # progress, api-coverage, decisions, spikes, user guides
```

See [PLAN.md §3](PLAN.md) for the rules at each boundary &mdash; in particular the kit-import policy from [Decision 0003](docs/decisions/0003-kit-import-policy.md): the App target imports `InterlinedKit` only from the composition root.

## Building

Requirements:

- macOS 15 (Sequoia) or later (see [Decision 0004](docs/decisions/0004-markdown-library-and-macos15.md))
- Xcode 16.2 / Swift 6.0.3

Build and test:

```sh
# All three SPM packages
swift test --package-path Packages/InterlinedKit
swift test --package-path Packages/InterlinedDomain
swift test --package-path Packages/InterlinedPersistence

# App target (incl. AppTests)
xcodebuild test \
  -project InterlinedList.xcodeproj \
  -scheme InterlinedList \
  -destination 'platform=macOS'
```

CI runs the same steps on every push and pull request (`.github/workflows/ci.yml`) and uploads the unsigned `.app` bundle as a workflow artifact.

### Live contract tests

The env-gated contract suite in `InterlinedKitTests` hits the real API. To run it locally, export credentials before invoking `swift test`:

```sh
export INTERLINEDLIST_EMAIL="you@example.com"
export INTERLINEDLIST_PASSWORD="..."
swift test --package-path Packages/InterlinedKit
```

The CI workflow does **not** run contract tests. Credentials must never be committed.

## Documentation

- [PLAN.md](PLAN.md) &mdash; product scope, architecture, milestones, branding (authoritative).
- [ORCHESTRATION.md](ORCHESTRATION.md) &mdash; how work is sequenced and how agents own paths.
- [docs/progress.md](docs/progress.md) &mdash; running log of waves, gates, deviations.
- [docs/api-coverage.md](docs/api-coverage.md) &mdash; endpoint matrix.
- [docs/decisions/](docs/decisions/) &mdash; recorded architecture decisions.
- [docs/spikes/](docs/spikes/) &mdash; investigations and probes against the live API.
- [docs/user/](docs/user/) &mdash; end-user guides.

## Branding

All visual identity follows the [official InterlinedList branding standards](https://interlinedlist.com/help/branding). The product name is **InterlinedList** &mdash; capital I, capital L, no spaces or hyphens. See [PLAN.md §9](PLAN.md) for the palette, typography, and asset rules used throughout the app.
