# Feature status

**Audience:** application end users.

This page summarizes what the InterlinedList macOS app can do today and what is still on the way. Milestones come from [PLAN.md §6](../../PLAN.md); ship status is drawn from [progress.md](../progress.md). When you see "Coming in a future update" inside the app, the table below tells you which milestone unlocks the feature.

| Milestone | What it covers | Status |
| --- | --- | --- |
| M0 — Foundation | Sign in, sign up, password reset; brand assets; auth + Keychain. | Shipped. |
| M1 — Read-only core | Timeline (All / Mine, tag filter), message threads, public list browsing, basic profile header. | Shipped. |
| M2 — Posting | Composer window, Markdown, tags, visibility, replies, "I Dig!" reactions, reposts, edit and delete your own messages. | Shipped. |
| M3 — Lists | Create, edit, delete your own lists; schema editor; rows table; nested lists; sharing and watchers; connections graph; GitHub-backed list refresh. | Shipped. |
| M4 — Documents | Folder tree, Markdown editor and preview, image upload, offline sync. | Not yet. |
| M5 — Social and notifications | Follow / unfollow; follower and following lists; mutual follows; private-account follow requests; notifications tray; system notifications; dock badge. | Not yet. |
| M6 — Subscriber and orgs | Media attachments (with client-side resize), scheduled posts, cross-posting (Mastodon / Bluesky / LinkedIn), OAuth identity linking, organizations and member roles, entitlement gating. | Not yet. |
| M7 — Ship | CSV exports, Settings polish (email change, account deletion, avatar), sandboxing and hardened runtime, notarization, Sparkle updates, accessibility audit, brand QA pass. | Not yet. |

## Limits worth knowing about today

- **Profiles without public messages.** The current release builds a profile from the user's most recent public message. Users who have never posted publicly cannot be shown as a profile yet — you see a "no public messages yet" empty state. This is expected, not an error; it lifts when richer profile data is available.
- **Following scope on the timeline.** The timeline scope picker offers All and Mine today; the Following scope arrives with M5.
- **Watcher invites on lists.** You can rename roles or remove existing watchers on any list you own, but inviting a new user by handle is coming in a future update — the backend lookup endpoint the share sheet needs is not yet available.
- **Connections graph layout.** The list-connections graph currently uses a stable radial arrangement. An animated force-directed layout will land in a follow-up.
- **GitHub-backed list refresh is manual.** Use the toolbar Refresh button on a GitHub-sourced list to pull the latest rows. Automatic background refresh will arrive in a later update.
- **"Save to my lists" copies metadata only.** From a public list, the Save action creates an owned list with the same title, description, and schema, but does not yet copy the rows. Row-level cloning lands when the backend ships its clone endpoint.

## Related pages

- [Getting started](getting-started.md)
- In the app: **Help > InterlinedList Help** (or Command + ?).
