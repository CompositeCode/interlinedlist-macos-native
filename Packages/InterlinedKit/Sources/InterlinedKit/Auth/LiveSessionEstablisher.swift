import Foundation

/// Production `SessionEstablisher` for the decision-0001 session-only allowlist.
///
/// Issues `POST /api/auth/login` once (lazily, on the first `.session`
/// request) using credentials from the injected `CredentialStore`. The
/// response's `Set-Cookie` header is automatically retained by the
/// `URLSession` backing the `transport`, so all subsequent requests through
/// the same session are cookie-authenticated without re-logging-in.
///
/// `DefaultAuthTransport` also gates re-entry via its own `sessionEstablished`
/// flag, so `establishIfNeeded()` is called at most once per app session even
/// if multiple concurrent `.session` requests race at startup.
public actor LiveSessionEstablisher: SessionEstablisher {

    private let credentialStore: any CredentialStore
    private let transport: any HTTPDataTransport
    private let loginURL: URL
    private let encoder = JSONEncoder()

    /// - Parameters:
    ///   - credentialStore: Source of the signed-in user's email + password.
    ///     Written by `AuthService.signIn` on successful authentication.
    ///   - transport: The **same** `HTTPDataTransport` (typically a dedicated
    ///     `URLSession`) used as `DefaultAuthTransport.sessionTransport`, so
    ///     the login cookie lands in the right cookie jar.
    ///   - baseURL: Defaults to `https://interlinedlist.com`.
    public init(
        credentialStore: any CredentialStore,
        transport: any HTTPDataTransport,
        baseURL: URL = URL(string: "https://interlinedlist.com")!
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/auth/login"
        components.query = nil
        self.loginURL = components.url!
    }

    public func establishIfNeeded() async throws {
        guard let creds = try credentialStore.read() else {
            throw APIError.unauthorized(serverMessage: "No credentials stored — sign in first")
        }

        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            CredentialsRequest(email: creds.email, password: creds.password)
        )

        let (_, response) = try await transport.data(for: request)

        switch response.statusCode {
        case 200, 204:
            return
        case 401:
            throw APIError.unauthorized(serverMessage: nil)
        default:
            throw APIError.httpStatus(code: response.statusCode, serverMessage: nil)
        }
    }
}
