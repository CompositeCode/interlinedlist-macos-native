# Feature status

**Audience:** application end users.

This page summarizes what the InterlinedList macOS app can do today and what is still on the way. Milestones come from [PLAN.md §6](../../PLAN.md); ship status is drawn from [progress.md](../progress.md). When you see "Coming in a future update" inside the app, the table below tells you which milestone unlocks the feature.

| Milestone | What it covers | Status |
| --- | --- | --- |
| M0 — Foundation | Sign in, sign up, password reset; brand assets; auth + Keychain. | Shipped. |
| M1 — Read-only core | Timeline (All / Mine, tag filter), message threads, public list browsing, basic profile header. | Shipped. |
| M2 — Posting | Composer window, Markdown, tags, visibility, replies, "I Dig!" reactions, reposts, edit and delete your own messages. | Shipped. |
| M3 — Lists | Create, edit, delete your own lists; schema editor; rows table; nested lists; sharing and watchers; connections graph; GitHub-backed list refresh. | Shipped. |
| M4 — Documents | Folder tree, Markdown editor and preview, image upload, offline sync. | Shipped. |
| M5 — Social and notifications | Follow / unfollow; follower and following lists; mutual follows; private-account follow requests; notifications tray; system notifications; dock badge. | Shipped. |
| M6 — Subscriber and orgs | Media attachments (with client-side resize), scheduled posts, cross-posting (Mastodon / Bluesky / LinkedIn), OAuth identity linking, organizations and member roles, entitlement gating. | Not yet. |
| M7 — Ship | CSV exports, Settings polish (email change, account deletion, avatar), sandboxing and hardened runtime, notarization, Sparkle updates, accessibility audit, brand QA pass. | Not yet. |

## Limits worth knowing about today

- **Profiles without public messages.** The current release builds a profile from the user's most recent public message. Users who have never posted publicly cannot be shown as a profile yet — you see a "no public messages yet" empty state. This is expected, not an error; it lifts when richer profile data is available.
- **Following scope on the timeline.** The timeline scope picker offers All and Mine today; a Following scope (timeline filtered to accounts you follow) is coming in a future update — the social roster and follow actions shipped with M5, but the timeline-side filter is not wired yet.
- **Watcher invites on lists.** You can rename roles or remove existing watchers on any list you own, but inviting a new user by handle is coming in a future update — the backend lookup endpoint the share sheet needs is not yet available.
- **Connections graph layout.** The list-connections graph currently uses a stable radial arrangement. An animated force-directed layout will land in a follow-up.
- **GitHub-backed list refresh is manual.** Use the toolbar Refresh button on a GitHub-sourced list to pull the latest rows. Automatic background refresh will arrive in a later update.
- **"Save to my lists" copies metadata only.** From a public list, the Save action creates an owned list with the same title, description, and schema, but does not yet copy the rows. Row-level cloning lands when the backend ships its clone endpoint.
- **Document sync is manual or on launch.** The Documents window syncs once automatically when the app opens, and the toolbar **Sync Now** button (also Documents > Sync Now, ⌥⌘S) pulls remote changes and pushes any local edits on demand. Background periodic sync arrives in a later update.
- **Document images are resized before upload.** If a screenshot or photo dropped into a document is above the upload limit, the app resizes and re-compresses it client-side before sending. Images that still cannot fit after compression surface a clear "image is too large" error instead of failing silently.
- **Document conflicts preserve your local copy.** If a document was edited on another device while you also edited it locally, the next sync keeps the remote version as the canonical document and stores your local edits as a separate "local copy" document. A banner offers an **Open local copy** action; if the preserved copy lives in a different folder than the one you currently have open, that action does not yet navigate across folders — switch folders manually to find it. This will improve once the sync engine reports the preserved copy's folder.
- **macOS 15 (Sequoia) is now the minimum.** The Documents Markdown preview uses the [Textual](https://github.com/gonzalezreal/textual) library, whose pure-SwiftUI rendering requires macOS 15 (see [Decision 0004](../decisions/0004-markdown-library-and-macos15.md)).
- **System notifications need permission the first time.** The first time you open the Notifications tab, macOS asks whether InterlinedList may show notifications. Grant permission to receive banners and the dock-tile unread badge; deny and the in-app tray still works, but system banners are suppressed. The prompt only appears once — change your answer later in **System Settings > Notifications > InterlinedList**.
- **Follow-button initial state.** When you open another user's profile the **Follow** button needs a round-trip to learn whether you already follow them; for a moment after opening the profile the button stays hidden. This is intentional — showing "Follow" against a user you already follow would be a wrong default.
- **Notification deep-linking is minimal in v1.** Clicking a system notification brings InterlinedList forward; routing to the specific message, list, or profile each notification refers to lands in a follow-up. Open the in-app Notifications tab to navigate to the related content.

## Related pages

- [Getting started](getting-started.md)
- In the app: **Help > InterlinedList Help** (or Command + ?).
