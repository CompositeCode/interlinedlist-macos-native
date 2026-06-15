# API Endpoint Coverage Matrix

**Audience:** engineering (maintainers and implementing agents).

This matrix exists so that full coverage of the [InterlinedList API](https://interlinedlist.com/help/api) is **verified, not assumed** (PLAN.md §7). It maps every documented endpoint to the service planned to implement it (PLAN.md §3) and the milestone that ships it (PLAN.md §6), with check-off columns for implementation and tests.

**Maintenance rule:** the documentation engineer updates this matrix at the end of each wave, after the wave gate passes. A row's **Implemented** box is checked only when the endpoint's request builder, DTOs, and service call path are merged; **Tested** is checked only when BDD-named unit tests against `APIClient` stubs cover that endpoint (happy path, invalid input, API failure, empty/boundary — PLAN.md §7). No box is checked speculatively.

- Source of truth for the endpoint inventory: https://interlinedlist.com/help/api (verified 2026-06-11), cross-checked against PLAN.md §1.
- ☐ = not done, ☑ = done. All rows start unchecked.
- **Auth** column reproduces the API reference's annotation. Groups marked *Session* are subject to the M0 Bearer-vs-Session spike (`docs/spikes/auth-bearer-vs-session.md`, decision in `docs/decisions/0001-auth-transport.md`).
- The three `GET /api/users/[username]/lists*` endpoints appear in the API reference under both **Lists** and **Public**; they are listed once here, under **Lists**, with no-auth noted.

| Endpoint (method + path) | Group | Auth | Planned service | Milestone | Implemented | Tested |
| --- | --- | --- | --- | --- | --- | --- |
| `POST /api/auth/login` | Auth | Public → session cookie | AuthService (InterlinedKit/Auth) | M0 | ☐ | ☐ |
| `POST /api/auth/logout` | Auth | Session | AuthService (InterlinedKit/Auth) | M0 | ☐ | ☐ |
| `POST /api/auth/register` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☐ | ☐ |
| `POST /api/auth/sync-token` | Auth | Public → Bearer token | AuthService (InterlinedKit/Auth) | M0 | ☐ | ☐ |
| `POST /api/auth/forgot-password` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☐ | ☐ |
| `POST /api/auth/reset-password` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☐ | ☐ |
| `POST /api/auth/send-verification-email` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☐ | ☐ |
| `POST /api/auth/verify-email` | Auth | Public | AuthService (InterlinedKit/Auth) | M0 | ☐ | ☐ |
| `GET /api/auth/github/authorize` | Auth (OAuth) | Public | AuthService (OAuth flows) | M6 | ☐ | ☐ |
| `GET /api/auth/mastodon/authorize` | Auth (OAuth) | Public | AuthService (OAuth flows) | M6 | ☐ | ☐ |
| `GET /api/auth/bluesky/authorize` | Auth (OAuth) | Public | AuthService (OAuth flows) | M6 | ☐ | ☐ |
| `GET /api/auth/linkedin/authorize` | Auth (OAuth) | Public | AuthService (OAuth flows) | M6 | ☐ | ☐ |
| `GET /api/user` | User | Session or Bearer | UserService¹ (+ EntitlementsService reads `customerStatus`) | M0 | ☐ | ☐ |
| `POST /api/user/update` | User | Session | UserService¹ | M7 | ☐ | ☐ |
| `POST /api/user/avatar/upload` | User | Session | UserService¹ | M7 | ☐ | ☐ |
| `POST /api/user/avatar/from-url` | User | Session | UserService¹ | M7 | ☐ | ☐ |
| `GET /api/user/identities` | User | Session | UserService¹ | M6 | ☐ | ☐ |
| `GET /api/user/organizations` | User | Session | OrgService | M6 | ☐ | ☐ |
| `POST /api/user/change-email/request` | User | Session | UserService¹ | M7 | ☐ | ☐ |
| `POST /api/user/delete` | User | Session | UserService¹ | M7 | ☐ | ☐ |
| `GET /api/messages` | Messages | Session or Bearer | MessagesService | M1 | ☐ | ☐ |
| `POST /api/messages` | Messages | Session or Bearer | MessagesService | M2² | ☐ | ☐ |
| `GET /api/messages/[id]` | Messages | Session or Bearer | MessagesService | M1 | ☐ | ☐ |
| `PUT /api/messages/[id]` | Messages | Session or Bearer | MessagesService | M2 | ☐ | ☐ |
| `DELETE /api/messages/[id]` | Messages | Session or Bearer | MessagesService | M2 | ☐ | ☐ |
| `GET /api/messages/scheduled` | Messages | Session or Bearer | MessagesService | M6 | ☐ | ☐ |
| `GET /api/messages/[id]/replies` | Messages | Session | MessagesService | M1 | ☐ | ☐ |
| `POST /api/messages/[id]/dig` | Messages | Session | MessagesService | M2 | ☐ | ☐ |
| `DELETE /api/messages/[id]/dig` | Messages | Session | MessagesService | M2 | ☐ | ☐ |
| `POST /api/messages/images/upload` | Messages | Session or Bearer | MessagesService | M6 | ☐ | ☐ |
| `POST /api/messages/videos/upload` | Messages | Session or Bearer | MessagesService | M6 | ☐ | ☐ |
| `GET /api/lists` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `POST /api/lists` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `GET /api/lists/[id]` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `PUT /api/lists/[id]` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `DELETE /api/lists/[id]` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `GET /api/lists/[id]/schema` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `PUT /api/lists/[id]/schema` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `POST /api/lists/[id]/refresh` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `GET /api/lists/[id]/data` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `POST /api/lists/[id]/data` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `GET /api/lists/[id]/data/[rowId]` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `PATCH /api/lists/[id]/data/[rowId]` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `DELETE /api/lists/[id]/data/[rowId]` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `GET /api/lists/[id]/watchers` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `GET /api/lists/[id]/watchers/me` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `GET /api/lists/[id]/watchers/users` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `PUT /api/lists/[id]/watchers/[userId]` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `DELETE /api/lists/[id]/watchers/[userId]` | Lists | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `GET /api/users/[username]/lists` | Lists (public) | None | ListsService | M1 | ☐ | ☐ |
| `GET /api/users/[username]/lists/[id]` | Lists (public) | None | ListsService | M1 | ☐ | ☐ |
| `GET /api/users/[username]/lists/[id]/data` | Lists (public) | None | ListsService | M1 | ☐ | ☐ |
| `GET /api/lists/connections` | List Connections | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `POST /api/lists/connections` | List Connections | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `DELETE /api/lists/connections/[id]` | List Connections | Session or Bearer | ListsService | M3 | ☐ | ☐ |
| `GET /api/documents/sync` | Documents & Sync | Session or Bearer | DocumentSyncEngine (InterlinedPersistence) | M4 | ☐ | ☐ |
| `POST /api/documents/sync` | Documents & Sync | Session or Bearer | DocumentSyncEngine (InterlinedPersistence) | M4 | ☐ | ☐ |
| `GET /api/documents` | Documents & Sync | Session | DocumentsService | M4 | ☐ | ☐ |
| `POST /api/documents` | Documents & Sync | Session | DocumentsService | M4 | ☐ | ☐ |
| `GET /api/documents/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☐ | ☐ |
| `PATCH /api/documents/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☐ | ☐ |
| `DELETE /api/documents/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☐ | ☐ |
| `POST /api/documents/[id]/images/upload` | Documents & Sync | Session | DocumentsService | M4 | ☐ | ☐ |
| `GET /api/documents/folders` | Documents & Sync | Session | DocumentsService | M4 | ☐ | ☐ |
| `POST /api/documents/folders` | Documents & Sync | Session | DocumentsService | M4 | ☐ | ☐ |
| `GET /api/documents/folders/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☐ | ☐ |
| `PATCH /api/documents/folders/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☐ | ☐ |
| `DELETE /api/documents/folders/[id]` | Documents & Sync | Session | DocumentsService | M4 | ☐ | ☐ |
| `GET /api/documents/folders/[id]/documents` | Documents & Sync | Session | DocumentsService | M4 | ☐ | ☐ |
| `POST /api/follow/[userId]` | Follow | Session | SocialService | M5 | ☐ | ☐ |
| `DELETE /api/follow/[userId]` | Follow | Session | SocialService | M5 | ☐ | ☐ |
| `GET /api/follow/[userId]/status` | Follow | Session | SocialService | M5 | ☐ | ☐ |
| `GET /api/follow/[userId]/followers` | Follow | Session | SocialService | M5 | ☐ | ☐ |
| `GET /api/follow/[userId]/following` | Follow | Session | SocialService | M5 | ☐ | ☐ |
| `GET /api/follow/[userId]/counts` | Follow | Session | SocialService | M5 | ☐ | ☐ |
| `GET /api/follow/[userId]/mutual` | Follow | Session | SocialService | M5 | ☐ | ☐ |
| `POST /api/follow/[userId]/approve` | Follow | Session | SocialService | M5 | ☐ | ☐ |
| `POST /api/follow/[userId]/reject` | Follow | Session | SocialService | M5 | ☐ | ☐ |
| `POST /api/follow/[userId]/remove` | Follow | Session | SocialService | M5 | ☐ | ☐ |
| `GET /api/follow/requests` | Follow | Session | SocialService | M5 | ☐ | ☐ |
| `GET /api/organizations` | Organizations | Session | OrgService | M6 | ☐ | ☐ |
| `POST /api/organizations` | Organizations | Session | OrgService | M6 | ☐ | ☐ |
| `GET /api/organizations/[id]` | Organizations | Session | OrgService | M6 | ☐ | ☐ |
| `PATCH /api/organizations/[id]` | Organizations | Session | OrgService | M6 | ☐ | ☐ |
| `GET /api/organizations/[id]/members` | Organizations | Session | OrgService | M6 | ☐ | ☐ |
| `POST /api/organizations/[id]/members` | Organizations | Session | OrgService | M6 | ☐ | ☐ |
| `PUT /api/organizations/[id]/members/[userId]` | Organizations | Session | OrgService | M6 | ☐ | ☐ |
| `DELETE /api/organizations/[id]/members/[userId]` | Organizations | Session | OrgService | M6 | ☐ | ☐ |
| `GET /api/organizations/[id]/users` | Organizations | Session | OrgService | M6 | ☐ | ☐ |
| `GET /api/exports/messages` | Exports | Session | ExportsService¹ | M7 | ☐ | ☐ |
| `GET /api/exports/lists` | Exports | Session | ExportsService¹ | M7 | ☐ | ☐ |
| `GET /api/exports/list-data-rows` | Exports | Session | ExportsService¹ | M7 | ☐ | ☐ |
| `GET /api/exports/follows` | Exports | Session | ExportsService¹ | M7 | ☐ | ☐ |
| `GET /api/notifications` | Notifications | Session | NotificationsService | M5 | ☐ | ☐ |
| `PATCH /api/notifications/[id]/read` | Notifications | Session | NotificationsService | M5 | ☐ | ☐ |
| `POST /api/notifications/mark-all-read` | Notifications | Session | NotificationsService | M5 | ☐ | ☐ |
| `GET /api/user/[username]/messages` | Public | None | MessagesService | M1 | ☐ | ☐ |
| `GET /api/auth/linkedin/status` | Public | None | AuthService (OAuth flows) | M6 | ☐ | ☐ |

**Totals:** 98 endpoints — Auth 12 · User 8 · Messages 11 · Lists 21 (incl. 3 public) · List Connections 3 · Documents & Sync 14 · Follow 11 · Organizations 9 · Exports 4 · Notifications 3 · Public-only 2.

## Footnotes and assumptions

1. **UserService / ExportsService** are not explicitly named in PLAN.md §3 (its service list ends with an ellipsis: "MessagesService, ListsService, DocumentsService, SocialService, OrgService, NotificationsService…"). These names follow the same convention and must be confirmed when the Wave 1 endpoint-group tasks are cut; update this column if the orchestrator picks different names.
2. `POST /api/messages` ships in M2 for plain posting; its scheduled-post (`scheduledAt`) and cross-posting (`mastodonProviderIds`, `crossPostToBluesky`, `crossPostToLinkedIn`) request fields land in M6. The row is checked Implemented at M2; the M6 wave update must confirm the extended fields are covered before the row counts toward M6.
3. Repost (`pushedMessageId`), visibility, and tag filters are request/response fields on existing rows above, not separate endpoints — they carry no row of their own.

## Cross-check against PLAN.md §1 (2026-06-11)

- Every API surface named in PLAN.md §1 maps to at least one row above. No PLAN.md endpoint is missing from the live reference.
- Present in the live reference but not explicitly named in PLAN.md §1: `POST /api/auth/logout` (implied by the auth feature), `GET /api/auth/linkedin/status` (supports the LinkedIn cross-post/OAuth feature, M6), and `GET /api/user/[username]/messages` (public user messages; nearest §1 feature is user profiles, M1). None contradict the plan; they are additive.
- PLAN.md §4's "Session-only" list (replies, digs, follow, organizations, notifications, document CRUD) matches the live annotations. The live reference additionally marks the User group's write endpoints and Exports as Session — the M0 spike should probe these groups too.
