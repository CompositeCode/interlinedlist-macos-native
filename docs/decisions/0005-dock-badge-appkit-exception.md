# Decision 0005 — Dock badge: narrow AppKit exception via `NSApplicationDelegateAdaptor`

- **Status:** Accepted (2026-06-24)
- **Wave:** Locked in ahead of Wave 6.3 (M5 Social + Notifications App UI).
- **Related:** Memory `feedback_swiftui_only.md` (SwiftUI-only constraint), PLAN.md §5 ("dock badge for unread").

## Context

PLAN.md §5 explicitly calls for a **dock badge for unread notifications** as part of the M5 native experience. SwiftUI on macOS 15 does not expose a dock-badge API. The only platform-provided way to set the macOS dock-tile badge is `NSApplication.shared.dockTile.badgeLabel` — which requires `import AppKit`.

Memory `feedback_swiftui_only.md` says: "If the SwiftUI surface seems insufficient, **pause and ask the user before reaching for AppKit interop**." The user (in auto mode, 2026-06-24) was asked between three options:

- **A.** Tiny `@NSApplicationDelegateAdaptor` + dock-tile badge as a single documented exception file.
- **B.** Skip the dock badge entirely; defer until SwiftUI exposes it.
- **C.** Some other approach.

The user chose option **A** — "Go with the recommended or defaults."

## Decision

Allow a narrow `import AppKit` in **exactly one** new file: `App/Composition/AppDelegate.swift`. The file's sole purpose is to:

1. Be the `NSApplicationDelegateAdaptor` for the SwiftUI `@main` App.
2. Expose a single `updateDockBadge(unreadCount: Int)` method that writes `NSApplication.shared.dockTile.badgeLabel`.
3. Optionally request UNUserNotifications permission deferral to the App layer (kept SwiftUI-side; this file does not touch `UNUserNotificationCenter`).

The Wave 6.3 `NotificationsService` event stream / view models call into `AppDelegate.updateDockBadge(_:)` whenever the unread count changes; everything else stays pure SwiftUI.

## Rationale

- **Platform forces the choice.** macOS 15 SwiftUI has no public dock-badge API; the user explicitly wants the feature; the only path is the documented AppKit one. Skipping the badge would be a visible regression versus what PLAN.md §5 promises.
- **One file, one method, one purpose.** The exception is the narrowest possible. The rest of the App target stays pure SwiftUI (verified at the gate). Future contributors looking at `App/Composition/AppDelegate.swift` will find a single short file whose existence is documented here.
- **Precedent for narrow exceptions.** Decision 0003 already carves out `App/Composition/AppEnvironment.swift` as the **only** App-target file allowed to `import InterlinedKit`. The shape is the same — a tightly scoped composition-root file that the rest of the codebase doesn't see.

## Consequences

### Verification gate amendment

The `App/**` AppKit grep used in every wave gate must change from:

```sh
grep -rEn "^[[:space:]]*import AppKit" App/                 # must return empty
```

to:

```sh
# Allow the documented composition-root AppDelegate; everything else must be empty.
grep -rEn "^[[:space:]]*import AppKit" App/ \
  | grep -v '^App/Composition/AppDelegate.swift:'
```

Equivalently: the only acceptable hit is `App/Composition/AppDelegate.swift`. Any other file triggering the grep is a violation.

### File layout

- `App/Composition/AppDelegate.swift` — new, this wave (6.3).
- `App/Composition/AppEnvironment.swift` — unchanged; still owns the kit-side composition root per decision 0003.

### Memory rule still applies

The `feedback_swiftui_only.md` rule is **not relaxed**. Any future request to use AppKit anywhere else in the App target still triggers the pause-and-ask gate. This decision authorizes exactly one file for exactly one Apple-platform-required gap, and does so by name.

### Out of scope of this decision

- Other AppKit reaches (`NSSavePanel`, `NSPasteboard`, `NSWorkspace`, etc.). All still subject to the pause-and-ask rule from the memory; this decision narrowly covers dock badging.
- iOS / iPadOS parity. The project is macOS-only; UIKit equivalents don't apply.
- App Store distribution. Decision 0004 already pins macOS 15 + `.pkg` distribution; `NSApplicationDelegateAdaptor` is fully App-Store-eligible if that path is ever pursued.
