# Synchronization Plan — InterlinedList Document Sync Agent

**A background menu-bar utility that keeps a local folder of Markdown files bidirectionally in sync with your InterlinedList documents — so you can use Obsidian (or any editor) to read, edit, and manage them.**

- **Owner:** Adron Hall · **Status doc reviewed:** 2026-07-31
- **Target OS:** macOS 15+ (matches the main app) · **Team:** `BJA9558E4B`
- **Reference blueprint:** [`CompositeCode/interlinedlist-synchronization`](https://github.com/CompositeCode/interlinedlist-synchronization) (its macOS Swift menu-bar daemon; used as an architecture blueprint only — this agent is a clean-room reimplementation).

---

## 1. Why

The native client (`com.interlinedlist.macos`) already speaks the full `/api/documents/sync` protocol *inside* the app, but only into an app-private, in-memory SwiftData cache that drives the in-app Documents UI. Documents never land on disk where an external tool can touch them.

This project adds a separate **synchronization utility + background service** that installs alongside the client. It projects your documents onto a real folder of `.md` files and watches that folder for edits, pushing changes back. The headline use case is **editing your InterlinedList documents in Obsidian**, with the sync running quietly in the menu bar and starting automatically at login.

## 2. What ships

- **`InterlinedListSync.app`** — a `LSUIElement` menu-bar agent (bundle id `com.interlinedlist.macos.sync`). No Dock icon; a status item with sync state, "Sync Now", "Pause", "Open Folder", "Preferences", and "Quit".
- **Bundled inside the main app** at `InterlinedList.app/Contents/Library/LoginItems/InterlinedListSync.app` and installed by the same notarized `.pkg`. No extra download.
- **Autonomous background service** — registered as an `SMAppService` login item, controlled by a **toggle in the main app's Settings ▸ Document Sync**. Launches at every login and keeps running whether or not the main app is open.
- **Silent auth** — reads the main app's existing sync token from a shared Keychain access group. Sign in once (in the app); the agent just works.

## 3. Locked decisions

| Area | Decision | Rationale |
|---|---|---|
| **Code strategy** | **Clean-room reimplement** (self-contained agent) | Agent has its own URLSession client + Codable models + sync engine; no dependency on `InterlinedKit`/`InterlinedDomain`/`InterlinedPersistence`, so it runs fully independent of the app and its package graph. |
| **Auth** | **Silent shared token** via Keychain access group `$(AppIdentifierPrefix)com.interlinedlist.shared` | One sign-in. Main app writes the token into the shared group; agent reads it read-only. |
| **File ↔ doc mapping** | **xattr + folder mirror** | Server `id` stored in extended attribute `com.interlinedlist.sync.documentID`; server folders mirrored as directories; filename = sanitized `title` + `.md`. Clean files for Obsidian; survives rename/move. |
| **Autonomy** | **`SMAppService` login item + Settings toggle** | Launches at login, runs independently, and appears in System Settings ▸ Login Items for user control. |
| **Conflict policy** | **Remote-wins + conflict copy** | On simultaneous edits, local content is preserved as `<base>.conflict-<yyyyMMdd-HHmmss>.md` and the file is overwritten with the remote version. |

## 4. Architecture

```
InterlinedList.app  (com.interlinedlist.macos — existing, sandboxed SwiftUI)
│  ├─ writes il_tok_ into shared Keychain group  ──►  $(TeamPrefix)com.interlinedlist.shared
│  ├─ Settings ▸ Document Sync toggle  ──►  SMAppService.loginItem(id).register()/unregister()
│  └─ Contents/Library/LoginItems/
│        └─ InterlinedListSync.app  (com.interlinedlist.macos.sync — NEW)
│
InterlinedListSync.app  (autonomous menu-bar agent)
   NSStatusItem ◀── StatusItemController ◀── SyncState (@MainActor)
   SyncEngine (actor)  ── poll timer + FSEventsWatcher ─┐
     ├─ SyncAPIClient ──►  https://interlinedlist.com/api
     │       GET/POST /documents/sync · CRUD /documents · CRUD /documents/folders
     ├─ DocumentMapper ──►  <sync folder>/**/*.md   (xattr ids · folder mirror · .conflict-<ts>.md)
     ├─ ChangeSet (diff) · ConflictResolver (remote-wins) · SyncLedger (JSON in App Support)
     ├─ SharedTokenStore (reads shared Keychain group)
     └─ NetworkMonitor · NotificationManager
```

**Local state = the filesystem.** The agent reconciles server ↔ folder directly. It deliberately does *not* reuse the app's SwiftData cache (ephemeral, app-private) — the folder + xattr ids + a small on-disk ledger are the single source of local truth, so two caches never fight.

## 5. Sync algorithm

Each cycle runs on a poll timer (default 60 s, configurable 30–600 s), an FSEvents debounce (0.3 s), or a manual "Sync Now":

1. **Pull.** `GET /api/documents/sync?lastSyncAt=<ISO8601>` (omit on first run for a full snapshot). Persist the returned `lastSyncAt`. Parse `documents[]` (+ optional `deletedAt`) and `folders[]`.
2. **Scan local.** Enumerate `.md` files: *tracked* (carry the sync xattr) vs *untracked* (new local docs).
3. **Diff** — `ChangeSet.compute(remote:local:ledger:)` decides per document from the 5-state matrix (`localChanged × remoteChanged × localExists × remoteExists`): `pull`, `push`, `conflictCopy`, `deleteLocal`, `deleteRemote`, `noOp`.
4. **Conflicts** → write `<base>.conflict-<ts>.md`, then overwrite with remote; notify.
5. **Remote → disk** — create/update/delete files; mirror the folder tree from `folderId`/`parentId`; set xattr id on every write.
6. **Local → server** — `POST` new, `PATCH` edited, `DELETE` removed; fold server-assigned ids back into xattr.
7. **Deletion safety net** — `/sync` tombstones are unreliable (per the reference `API_CONTRACT.md`), so every N cycles (default 10) do a full `GET /api/documents` reconciliation: a tracked file whose id is absent is treated as remote-deleted.
8. **Persist ledger** (`{remoteUpdatedAt, localModifiedAt, contentHash}` per doc) and update `SyncState`.

**Resilience.** `429` → honor `Retry-After`, else exponential backoff + jitter (cap 300 s). `401` → `authExpired` + "Open InterlinedList to sign in". Network loss (`NWPathMonitor`) → `offline`, pause until restored. `SyncEngine` is an `actor`; a per-document gate serializes same-doc writes while different docs proceed concurrently.

## 6. Auth & migration

- Shared group `$(AppIdentifierPrefix)com.interlinedlist.shared` added to the `keychain-access-groups` entitlement of **both** apps.
- Main-app `KeychainTokenStore` gains an optional `accessGroup:`; when set, `kSecAttrAccessGroup` is included in read/write/delete. Item stays `kSecClassGenericPassword` / service `com.interlinedlist.macos.bearer-token` / account `default`.
- **Migration:** on a shared-group read-miss, fall back to the legacy (app-default group) item and re-write it into the shared group — one-time, transparent.
- Agent's `SharedTokenStore` is a minimal read-only `SecItem` wrapper against the same service/account/group.

## 7. Distribution

The agent is a **SwiftPM executable** assembled into an `.app` by a script (no fragile `.xcodeproj` target surgery), matching the reference repo's approach.

- `SyncAgent/` package → `swift build -c release` → `SyncAgent/scripts/build-app.sh` assembles `InterlinedListSync.app` (binary + `Info.plist` with `LSUIElement` + icon) and codesigns (Developer ID Application, hardened runtime, entitlements).
- `scripts/notarize-and-package.sh` is extended to build the agent, copy it into the exported `InterlinedList.app/Contents/Library/LoginItems/`, deep-sign, then continue the existing notarize → `pkgbuild`/`productbuild` → `.dmg` flow. One ticket, one `.pkg`. Sparkle updates carry the embedded agent automatically.

## 8. Component inventory

**Agent (`SyncAgent/Sources/InterlinedListSync/`)**

| Area | Files |
|---|---|
| App | `App/InterlinedListSyncApp.swift`, `App/AppDelegate.swift` |
| API | `API/SyncAPIClient.swift`, `API/Models.swift` |
| Auth | `Auth/SharedTokenStore.swift` |
| FileSystem | `FileSystem/FSEventsWatcher.swift`, `FileSystem/DocumentMapper.swift` |
| Sync | `Sync/SyncEngine.swift`, `Sync/SyncState.swift`, `Sync/ChangeSet.swift`, `Sync/ConflictResolver.swift`, `Sync/SyncLedger.swift`, `Sync/DocumentGate.swift` |
| UI/Menu | `MenuBar/StatusItemController.swift`, `UI/PreferencesView.swift`, `UI/OnboardingView.swift` |
| Services | `Network/NetworkMonitor.swift`, `Notifications/NotificationManager.swift`, `Storage/PreferencesManager.swift`, `Storage/LoginItemManager.swift`, `Storage/SecurityScopedAccess.swift` |
| Config | `Resources/`, `Info.plist`, `InterlinedListSync.entitlements` |
| Tests | `ChangeSetTests`, `ConflictResolverTests`, `DocumentMapperTests`, `SyncAPIClientTests`, `SyncEngineTests`, `SharedTokenStoreTests`, `PreferencesManagerTests` |

**Main app (modified)**

- `Packages/InterlinedKit/Sources/InterlinedKit/Auth/TokenStore.swift` — `accessGroup` + migration.
- `App/Composition/AppEnvironment.swift` — construct token store with the shared group.
- `App/Resources/InterlinedList.entitlements` — add `keychain-access-groups`.
- `App/Features/Settings/…` + `App/Composition/SyncServiceController.swift` — Document Sync pane; `SMAppService` register/unregister + status.
- `scripts/notarize-and-package.sh` (+ `scripts/build-sync-agent.sh`) — build/embed/sign.

## 9. Verification

- **Unit:** `cd SyncAgent && swift test` all green; main-app packages `swift test`; App target with `CODE_SIGNING_ALLOWED=NO`; 0 regressions.
- **End-to-end** (live `.env` test account): initial full pull writes the folder tree with xattr ids; editing a file `PATCH`es; new `.md` creates a doc and back-fills its id; server edit pulls down; simultaneous edits yield a `.conflict-<ts>.md`; deletion caught by the full-list safety net; menu bar shows status + "Sync Now".
- **Autonomy:** enabling the Settings toggle registers the login item (visible in System Settings ▸ Login Items), which launches at login and survives quitting the app.
- **Auth:** sign in only in the app → agent syncs with no separate sign-in; legacy-token migration works.

## 10. Progress — implemented ✅ (2026-07-31)

- [x] 1. `synch-plan.md` (this file)
- [x] 2. Scaffold `SyncAgent/` package (SwiftPM: `InterlinedListSyncCore` lib + `InterlinedListSync` executable + tests)
- [x] 3. Agent core (models → engine) + unit tests
- [x] 4. Agent shell (menu bar, prefs, login item)
- [x] 5. Main-app wiring (shared Keychain group + migration, entitlement, Document Sync settings pane, `SyncServiceController`)
- [x] 6. Packaging (`SyncAgent/scripts/build-app.sh`, `scripts/build-sync-agent.sh`, embed+sign step in `notarize-and-package.sh`, bundled LaunchAgent plist)
- [x] 7. Verify — see below

### Verification results

| Check | Result |
|---|---|
| `SyncAgent` unit + live tests | **53 passing** (`swift test`) incl. a read-only live check against the real API |
| `InterlinedKit` (token-store change) | **274 passing**, 0 regressions |
| Main App target | **builds** + **502 tests passing** (`xcodebuild test … CODE_SIGNING_ALLOWED=NO`) |
| Agent `.app` assembly | universal (arm64 + x86_64) bundle assembles & signs via `build-app.sh` |
| Live API (`.env` test account, read-only) | `POST /api/auth/sync-token`, `GET /api/documents/sync` (9 docs/3 folders), `GET /api/documents` (5/3), `GET /api/documents/folders`, `GET /api/documents/{id}` all decode |

**Live correction folded in:** `GET /api/documents/{id}` returns an envelope `{document:…}` on the live API (not the bare object the reference contract described) — the client now tolerates both.

### Still requires an interactive login session / Developer ID (not runnable headless)

- Menu-bar GUI smoke (status item, preferences window) — needs a real Aqua session.
- Full notarized `.pkg` build + `SMAppService.agent` registration + on-device shared-Keychain read by the running agent — needs Developer ID certs + Apple notary + a signed install. The packaging pipeline is wired; run `scripts/notarize-and-package.sh` on a signing machine.
- Live **write** paths (create/update/delete) were intentionally not exercised against the account (read-only session); they share the request-building + envelope decoder that the read paths and fake-server engine tests cover.

## 11. Risks / open items

- Shared Keychain access group requires re-signing the main app with a new entitlement; migration moves the token.
- Sandbox + login item + shared Keychain wiring must be validated on-device (usual failure point).
- `relativePath` / `contentHash` server fields are advisory/inconsistent — the agent relies on `folderId` + local hashing.
- Filename collisions (same sanitized title in the same folder) are disambiguated with a short id suffix.
