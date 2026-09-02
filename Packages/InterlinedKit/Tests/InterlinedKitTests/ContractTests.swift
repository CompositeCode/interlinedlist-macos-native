import XCTest
@testable import InterlinedKit

/// Env-gated **live contract test** (PLAN.md §7 — the integration suite that
/// doubles as a drift alarm against the real API).
///
/// When `INTERLINEDLIST_EMAIL` / `INTERLINEDLIST_PASSWORD` are present in the
/// environment, this performs a **real** `AuthService.signIn` against
/// `https://interlinedlist.com` and a **real** `GET /api/messages` (small
/// `limit`), asserting:
/// - sign-in returns a non-empty bearer token (HTTP 200),
/// - the timeline request returns HTTP 200 (any non-2xx throws `APIError`
///   from `sendRaw`, failing the test), and
/// - the body decodes into the production DTOs (`Paginated<MessageDTO>` via the
///   builder's `paginationKey`).
///
/// When the credentials are absent (the default CI case), every test calls
/// `throw XCTSkip(...)` so the suite stays green. This is a genuine network
/// test — it is **not** stubbed — but it asserts only on status + decodability,
/// and never logs the token or password.
final class ContractTests: XCTestCase {

    private let liveBaseURL = URL(string: "https://interlinedlist.com")!

    private struct Credentials {
        let email: String
        let password: String
    }

    /// Reads credentials from the environment, or `nil` if either is missing /
    /// blank. The values themselves are never logged.
    private func credentialsFromEnvironment() -> Credentials? {
        let env = ProcessInfo.processInfo.environment
        guard
            let email = env["INTERLINEDLIST_EMAIL"], !email.isEmpty,
            let password = env["INTERLINEDLIST_PASSWORD"], !password.isEmpty
        else {
            return nil
        }
        return Credentials(email: email, password: password)
    }

    /// A real, network-backed client + auth service pointed at the live API.
    /// The token is held only in an in-memory store for the duration of the
    /// test and is never written to disk or logged.
    private func makeLiveStack(tokenStore: TokenStore) -> (APIClient, AuthService) {
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: URLSession.shared,
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(
            baseURL: liveBaseURL,
            transport: URLSession.shared,
            authTransport: auth
        )
        return (client, AuthService(api: client, tokenStore: tokenStore))
    }

    // MARK: - Tests

    func test_givenLiveCredentials_whenSignedIn_thenReceivesBearerToken() async throws {
        guard let credentials = credentialsFromEnvironment() else {
            throw XCTSkip("Live credentials not set — skipping contract test.")
        }

        let store = InMemoryTokenStore()
        let (_, service) = makeLiveStack(tokenStore: store)

        let token = try await service.signIn(
            email: credentials.email,
            password: credentials.password
        )

        // Assert only that a token came back and was persisted. Never log it.
        XCTAssertFalse(token.isEmpty, "sync-token should return a non-empty token")
        XCTAssertNotNil(try store.read())
    }

    func test_givenLiveCredentials_whenFetchingTimeline_thenReturns200AndDecodes() async throws {
        guard let credentials = credentialsFromEnvironment() else {
            throw XCTSkip("Live credentials not set — skipping contract test.")
        }

        let store = InMemoryTokenStore()
        let (client, service) = makeLiveStack(tokenStore: store)

        // Real sign-in to obtain the bearer token used by the timeline request.
        _ = try await service.signIn(
            email: credentials.email,
            password: credentials.password
        )

        // Real GET /api/messages?limit=3. `sendRaw` throws an `APIError` for any
        // non-2xx response, so reaching the decode step proves HTTP 200.
        let request = Messages.list(limit: 3)
        let (data, _) = try await client.sendRaw(request)

        // Decode into the production DTOs via the builder's pagination key —
        // this is the assertion that the live shape still matches our model.
        let page = try PaginatedDecoder.decode(
            MessageDTO.self,
            collectionKey: try XCTUnwrap(request.paginationKey),
            from: data
        )

        XCTAssertLessThanOrEqual(page.items.count, 3, "limit=3 should cap the page")
        // Pagination envelope must be present and self-consistent.
        XCTAssertGreaterThanOrEqual(page.pagination.total, 0)
        XCTAssertEqual(page.pagination.limit, 3)
    }

    /// Direct-message thread contract (work-consolidation.md G1). The DM
    /// composer's enabled state in `DMThreadView` is gated entirely on the
    /// thread response's `isMutual` / `isBlocked` fields (both optional in the
    /// DTO, defaulting to `false` when absent). A server- or DTO-side drift
    /// that dropped or renamed either field would silently gray the composer
    /// for genuine mutual followers — the exact symptom this test guards.
    ///
    /// It signs in, reads the mutual-follower recipient set, and for the first
    /// recipient asserts `GET /api/dm/thread/{username}` returns HTTP 200 and
    /// decodes with the mutuality fields present and coherent. Skips when the
    /// account has no recipients (a fresh account is legitimate). Never logs
    /// the token, usernames, or message bodies.
    func test_givenLiveCredentials_whenFetchingDMThread_thenMutualityFieldsDecode() async throws {
        guard let credentials = credentialsFromEnvironment() else {
            throw XCTSkip("Live credentials not set — skipping contract test.")
        }

        let store = InMemoryTokenStore()
        let (client, service) = makeLiveStack(tokenStore: store)
        _ = try await service.signIn(
            email: credentials.email,
            password: credentials.password
        )

        // The users this account may DM (mutual followers, not blocked). An
        // empty set is valid — there is then no thread to assert about.
        let recipients = try await client.send(DirectMessages.recipients())
        guard let target = recipients.recipients.first else {
            throw XCTSkip("Test account has no mutual-follower recipients — no thread to probe.")
        }

        // A recipient surfaced by /recipients must resolve to a mutual,
        // non-blocked thread with a populated `otherUser`. These three fields
        // drive the composer's enabled state; asserting they decode true is the
        // drift alarm for the "grayed composer for a mutual" symptom. Any
        // non-2xx would throw an `APIError` from `send`, failing the test.
        let thread = try await client.send(DirectMessages.thread(username: target.username))
        XCTAssertEqual(thread.isMutual, true, "a recipient from /recipients must decode as mutual")
        XCTAssertEqual(thread.isBlocked, false, "a recipient from /recipients must decode as not-blocked")
        XCTAssertEqual(
            thread.otherUser?.username,
            target.username,
            "thread otherUser must match the requested username"
        )
    }
}
