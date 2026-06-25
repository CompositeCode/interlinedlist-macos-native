import Foundation

/// Request builders for the **Auth** endpoint group (the credential and
/// account-lifecycle endpoints not tied to the bearer-token exchange).
///
/// The bearer-exchange endpoints (`sync-token`, `register`) are built inline by
/// `AuthService` because they carry token-persistence side effects. This
/// namespace covers the remaining stateless auth endpoints so they follow the
/// same builder pattern as every other group.
///
/// Auth requirements per decision 0001 and the live probe:
/// - `forgotPassword`, `resetPassword`, `verifyEmail` — `.none` (public).
/// - `sendVerificationEmail` — `.bearer` (the live endpoint returned 401 for an
///   unauthenticated request, i.e. it identifies the account from the session).
/// - `logout` — `.session` (clears the cookie session; the bearer token is a
///   separate, client-held secret cleared by `TokenStore.delete()`).
public enum Auth {

    /// `POST /api/auth/forgot-password` — start the password-reset email flow.
    ///
    /// This replaces the non-existent `/api/auth/password-reset/request` path
    /// (which 404s on the live API). Returns `{ "message": ... }`.
    public static func forgotPassword(email: String) -> Request<MessageResponse> {
        Request(
            method: .post,
            path: "/api/auth/forgot-password",
            body: .json(ForgotPasswordRequest(email: email)),
            auth: .none
        )
    }

    /// `POST /api/auth/reset-password` — complete the reset using the token
    /// from the reset email and a new password.
    public static func resetPassword(token: String, newPassword: String) -> Request<MessageResponse> {
        Request(
            method: .post,
            path: "/api/auth/reset-password",
            body: .json(ResetPasswordRequest(token: token, password: newPassword)),
            auth: .none
        )
    }

    /// `POST /api/auth/send-verification-email` — (re)send the verification
    /// email for the given address. `.bearer` because the live endpoint
    /// requires an authenticated caller.
    public static func sendVerificationEmail(email: String) -> Request<MessageResponse> {
        Request(
            method: .post,
            path: "/api/auth/send-verification-email",
            body: .json(SendVerificationEmailRequest(email: email)),
            auth: .bearer
        )
    }

    /// `POST /api/auth/verify-email` — verify the account using the token from
    /// the verification email.
    public static func verifyEmail(token: String) -> Request<MessageResponse> {
        Request(
            method: .post,
            path: "/api/auth/verify-email",
            body: .json(VerifyEmailRequest(token: token)),
            auth: .none
        )
    }

    /// `POST /api/auth/logout` — end the cookie session. **Session-only** per
    /// the coverage matrix. Returns `{ "message": "Logged out successfully" }`.
    public static func logout() -> Request<MessageResponse> {
        Request(method: .post, path: "/api/auth/logout", auth: .session)
    }

    // MARK: - OAuth (identity linking / cross-post providers)

    /// `GET /api/auth/{provider}/authorize` — begin an OAuth flow for the given
    /// provider. **Public** (`.none`): the live endpoint issues the redirect
    /// without a bearer token; whether the resulting session is anonymous or
    /// linked is determined by the cookies the *browser* carries, not by this
    /// request.
    ///
    /// **Response shape:** this endpoint replies `307` with a `Location` header
    /// pointing at the provider's authorization page (and sets an `oauth_state`
    /// `HttpOnly` cookie). There is no JSON body, so the `Request` is typed
    /// `Request<EmptyResponse>` purely as a phantom type — do not call
    /// `send(_:)` on it. See `docs/spikes/0002-oauth-identity-linking.md` for
    /// why this is **not natively completable as-is** (the registered callback
    /// is a `https://interlinedlist.com/…` web URL, not a custom scheme).
    ///
    /// - Parameters:
    ///   - provider: the identity provider path segment.
    ///   - link: when `true`, appends `?link=true` so the server records the
    ///     flow as an account-link rather than a sign-in (verified: the
    ///     `oauth_state` cookie carries `"link":true` and GitHub gains the
    ///     `repo` scope / LinkedIn gains org-admin scopes).
    ///   - instance: the Mastodon instance hostname (e.g. `mastodon.social`).
    ///     **Required for `.mastodon`** — without it the server redirects to
    ///     `…/login?error=Instance%20domain%20is%20required`. Ignored by the
    ///     other providers and dropped when `nil`.
    public static func authorize(
        provider: OAuthProvider,
        link: Bool? = nil,
        instance: String? = nil
    ) -> Request<EmptyResponse> {
        Request(
            method: .get,
            path: "/api/auth/\(provider.rawValue)/authorize",
            query: [
                .bool("link", link),
                .string("instance", instance)
            ],
            auth: .none
        )
    }

    /// `GET /api/auth/linkedin/status` — report whether LinkedIn OAuth is
    /// configured and the registered redirect URI. **Public** (`.none`): the
    /// live endpoint returns `200` with
    /// `{ "configured": true, "redirectUri": "https://…/callback" }` to an
    /// unauthenticated caller.
    public static func linkedinStatus() -> Request<LinkedInStatusResponse> {
        Request(method: .get, path: "/api/auth/linkedin/status", auth: .none)
    }
}
