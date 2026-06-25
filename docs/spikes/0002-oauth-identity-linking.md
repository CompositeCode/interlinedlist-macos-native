# Spike: OAuth identity linking — native completion viability

- **Date:** 2026-06-24
- **Milestone:** M6 / Wave 7
- **Question:** The InterlinedList web app links GitHub, Mastodon, Bluesky, and
  LinkedIn identities (and cross-posts to them) via `GET /api/auth/{provider}/authorize`.
  Can a **native macOS** client complete one of these OAuth flows — i.e. is
  story 7.4 (native OAuth linking UI) viable, blocked on upstream, or in need of
  a maintainer decision? The known fact going in: `GET /api/auth/linkedin/status`
  returns a **web** callback URL (`https://interlinedlist.com/api/auth/linkedin/callback`),
  and that callback domain is the central open question for native completion.
- **Method:** Unauthenticated `curl` against the live API (`interlinedlist.com`)
  with redirects **not** followed (`-o /dev/null -D -`), capturing HTTP status,
  the `Location` header, and any `Set-Cookie`. No credentials were used; no
  provider authorization was completed; no write requests were made. The probe
  characterizes only the public/redirect surface. (Secrets visible below —
  OAuth `client_id`s, the Bluesky client-metadata document, and short-lived
  `state`/PKCE values — are public by design: they are sent to a user's browser
  on every sign-in. No client *secret* is exposed by these endpoints; the one
  `client_secret` seen is the per-instance Mastodon app secret the server itself
  mints and stores in an `HttpOnly` cookie, not an InterlinedList secret.)

## Raw findings

### `GET /api/auth/{provider}/authorize` (no auth, no redirect follow)

| Provider | Status | `Location` (provider authorize URL) | `redirect_uri` embedded | Notes |
| --- | --- | --- | --- | --- |
| `github` | **307** | `github.com/login/oauth/authorize` | `https://interlinedlist.com/api/auth/github/callback` | PKCE (`code_challenge`, `S256`); `state`; sets `oauth_state` `HttpOnly` cookie carrying `state`+`codeVerifier`+`link:false` |
| `mastodon` | **307** | `interlinedlist.com/login?error=Instance%20domain%20is%20required` | — | Without `?instance=` the server rejects before redirecting to a provider |
| `bluesky` | **307** | `bsky.social/oauth/authorize?client_id=https://interlinedlist.com/api/oauth/client-metadata&request_uri=urn:ietf:params:oauth:request_uri:req-…` | (in client-metadata doc) | AT-proto PAR + DPoP; `client_id` is the hosted client-metadata URL |
| `linkedin` | **307** | `linkedin.com/oauth/v2/authorization` | `https://interlinedlist.com/api/auth/linkedin/callback` | `state`; scopes `openid profile email w_member_social`; sets `oauth_state` cookie |

### Query-parameter behavior (verified, drives the Kit builder)

- **`?link=true`** — `oauth_state` cookie flips to `"link":true`, and the provider
  scope set widens: GitHub gains `repo`; LinkedIn gains
  `rw_organization_admin w_organization_social`. This is the account-link
  (vs. sign-in) switch PLAN.md §4 references.
- **`?instance=mastodon.social`** (Mastodon) — 307s to
  `mastodon.social/oauth/authorize` and sets a second `oauth_mastodon_creds`
  `HttpOnly` cookie (`instance`, dynamically-registered `clientId`, `clientSecret`).
  The `oauth_state` cookie's `provider` becomes `mastodon:mastodon.social`.

### `GET /api/auth/linkedin/status` (no auth)

- **200** `application/json`:
  `{"configured":true,"redirectUri":"https://interlinedlist.com/api/auth/linkedin/callback"}`

### `GET /api/oauth/client-metadata` (Bluesky AT-proto)

- **200** `application/json`:
  `application_type":"web"`, `redirect_uris":["https://interlinedlist.com/api/auth/bluesky/callback"]`,
  `token_endpoint_auth_method":"none"`, `dpop_bound_access_tokens":true`.

### `GET /api/auth/github/callback` (no/invalid code, no auth)

- No `code`/`state` → **307** `Location: interlinedlist.com/login?error=Missing%20code%20or%20state`.
- Bogus `code`+`state` → **307** `Location: interlinedlist.com/login?error=Invalid%20state`,
  and clears the `oauth_state` cookie.
- The callback **always lands on the `interlinedlist.com` web domain** and
  depends on the browser carrying both the InterlinedList session cookie *and*
  the `HttpOnly` `oauth_state`/`oauth_mastodon_creds` cookies set at `/authorize`.

## Conclusion

**Story 7.4 (native OAuth identity-linking UI) is NOT natively completable
against the API as it exists today — status: blocked-on-upstream /
needs-maintainer-decision.** The evidence is consistent across all four
providers:

1. **The registered callback is a web URL on `interlinedlist.com`, not a custom
   scheme.** Every provider's `redirect_uri` (and the Bluesky client-metadata
   `redirect_uris`, whose `application_type` is literally `"web"`) points at
   `https://interlinedlist.com/api/auth/{provider}/callback`. A native macOS
   client cannot register or intercept that URL. `ASWebAuthenticationSession`
   (the framework PLAN.md §4 names) requires a callback the system can match —
   either a custom scheme or an associated-domain universal link the app claims.
   Neither exists here. (This spike does not import that framework; per the task
   constraints it only characterizes feasibility.)
2. **The flow is cookie-bound to the web session, not bearer-bound.** The
   `/authorize` step issues short-lived `HttpOnly` `oauth_state` (and, for
   Mastodon, `oauth_mastodon_creds`) cookies, and the `/callback` step requires
   both those cookies and the logged-in `interlinedlist.com` session cookie to
   associate the new identity with the right account. Our app's primary
   transport is the bearer token (decision 0001); it does not hold the web
   session cookie, so even a hidden web view that *did* complete the redirect
   would link the identity to whatever account the embedded cookie jar happens
   to be signed into — not deterministically to our bearer-token user.
3. **There is no native-completion contract.** Nothing in the probed surface
   offers a custom-scheme callback, a deep-link handoff, an
   exchange-the-code-for-a-token endpoint, or a "link with this bearer token"
   variant. The flow is designed end-to-end for a first-party browser.

So the blocker is upstream, not in our Kit: completing an identity link from a
native client needs a server change.

## Recommendation for 7.4

**Defer 7.4 and escalate to the maintainer with a specific ask.** Do not build
native OAuth linking UI in Wave 7. The Kit gains the additive, harmless request
builders now (they cost nothing and let a future feature — or a `Settings`
"Open in browser to link…" affordance — construct the correct URLs), but the
interactive completion is blocked until the server provides one of:

- **(preferred) a custom-scheme / universal-link callback** the macOS app can
  register, so `ASWebAuthenticationSession` can complete the flow and the server
  associates the identity via a one-time code rather than the web session
  cookie; **or**
- **a bearer-authenticated link endpoint** (`POST /api/auth/{provider}/link`
  taking the provider code/token) that ties the identity to the bearer-token
  user directly.

**Concrete question for the maintainer:** *"Will the API expose a native-callback
(custom scheme or universal link) or a bearer-authenticated identity-link
endpoint, or should the macOS app link identities by opening the existing web
flow in the default browser (no in-app completion)?"* The fully viable, zero-
upstream-change fallback is the last option — a Settings affordance that opens
`…/authorize?link=true` in the user's browser, where the user is already (or
gets) signed in, and completes the link on the web. That requires no new
framework and no in-app callback handling, and is the recommended Wave-7+
posture if the maintainer does not want to change the server. Track in
NEXT-WORK under M6.

## Kit deliverables landed by this spike (additive only)

- `OAuthProvider` enum (`github`/`mastodon`/`bluesky`/`linkedin`) and
  `LinkedInStatusResponse` DTO — `DTOs/OAuthDTO.swift`.
- `Auth.authorize(provider:link:instance:) -> Request<EmptyResponse>` (public,
  GET, `?link`/`?instance` query, `EmptyResponse` phantom because the endpoint
  replies `307` with no JSON body) and
  `Auth.linkedinStatus() -> Request<LinkedInStatusResponse>` (public, GET) —
  `Endpoints/AuthEndpoint.swift`.
- These commit us to **no UI** and import **no new framework**. They make the
  five M6 OAuth coverage rows *buildable* (the 7.5 docs gate owns the
  checkmarks).
