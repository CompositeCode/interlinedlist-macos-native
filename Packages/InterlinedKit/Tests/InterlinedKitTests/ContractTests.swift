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
    // MARK: - §1c live-verb defects (V1–V7)

    /// The drift alarm for the verb fixes made on 2026-09-06.
    ///
    /// Each of these routes shipped with a verb the live server rejects, so the
    /// feature behind it failed in production. This asserts the corrected verb
    /// is still the one the server advertises, by reading the `Allow` header
    /// from a real authenticated `OPTIONS` — the same evidence the fixes were
    /// built on. It is read-only: `OPTIONS` mutates nothing, so this is safe to
    /// run against the live account on every CI pass.
    ///
    /// A failure means the live API moved again. Re-probe before editing the
    /// expectation, and fix the builder rather than this test.
    func test_givenLiveCredentials_whenOptioningFixedRoutes_thenAllowHeadersStillMatch() async throws {
        guard let credentials = credentialsFromEnvironment() else {
            throw XCTSkip("Live credentials not set — skipping contract test.")
        }

        let store = InMemoryTokenStore()
        let (_, service) = makeLiveStack(tokenStore: store)
        let token = try await service.signIn(
            email: credentials.email,
            password: credentials.password
        )

        // (path, the verb the client now sends). Ids are placeholders — the
        // route table answers OPTIONS without resolving the resource.
        let expectations: [(path: String, verb: String)] = [
            ("/api/messages/probe", "PATCH"),                       // V1
            ("/api/user/update", "PATCH"),                          // V2
            ("/api/lists/probe/data/probe", "PUT"),                 // V3
            ("/api/organizations/probe", "PUT"),                    // V4
            ("/api/documents/folders/probe", "PUT"),                // V5
            ("/api/follow/probe/remove", "DELETE"),                 // V6
            ("/api/github/issues/owner/repo/1", "PATCH"),           // V7
            ("/api/github/issues/owner/repo/1/comments", "POST")    // V7
        ]

        for expectation in expectations {
            var request = URLRequest(url: liveBaseURL.appendingPathComponent(expectation.path))
            request.httpMethod = "OPTIONS"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)
            let http = try XCTUnwrap(response as? HTTPURLResponse)
            let allow = try XCTUnwrap(
                http.value(forHTTPHeaderField: "Allow"),
                "no Allow header for \(expectation.path)"
            )

            let verbs = Set(
                allow.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces).uppercased()
                }
            )
            XCTAssertTrue(
                verbs.contains(expectation.verb),
                "\(expectation.path) no longer allows \(expectation.verb) — live Allow is \(allow)"
            )
        }
    }

    /// Pins the **absence** of a scheduled-post editor route (GitHub #55).
    ///
    /// macOS deliberately ships a time-only editor for a queued post, because
    /// `PATCH /api/messages/[id]` honours `scheduledAt` alone and there is no
    /// other route that touches a scheduled post. That is a server-side gap, and
    /// the day it closes we want the gate to say so rather than the constraint
    /// quietly outliving its reason. This test fails — on purpose — if the API
    /// grows a scheduled-post editor, which is the signal to reopen #55.
    ///
    /// Verified read-only 2026-09-09: `/api/messages/scheduled` allows
    /// `GET, HEAD, OPTIONS`; both candidate editor paths 404.
    func test_givenLiveCredentials_whenOptioningScheduledRoutes_thenNoEditorRouteHasAppeared() async throws {
        guard let credentials = credentialsFromEnvironment() else {
            throw XCTSkip("Live credentials not set — skipping contract test.")
        }

        let store = InMemoryTokenStore()
        let (_, service) = makeLiveStack(tokenStore: store)
        let token = try await service.signIn(
            email: credentials.email,
            password: credentials.password
        )

        func options(_ path: String) async throws -> (status: Int, allow: String?) {
            var request = URLRequest(url: liveBaseURL.appendingPathComponent(path))
            request.httpMethod = "OPTIONS"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: request)
            let http = try XCTUnwrap(response as? HTTPURLResponse)
            return (http.statusCode, http.value(forHTTPHeaderField: "Allow"))
        }

        // The scheduled *list* is read-only — no write verb to update a queued
        // post in bulk or in place.
        let scheduled = try await options("/api/messages/scheduled")
        let scheduledVerbs = Set(
            (scheduled.allow ?? "").split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces).uppercased()
            }
        )
        XCTAssertFalse(
            scheduledVerbs.contains("PATCH") || scheduledVerbs.contains("PUT")
                || scheduledVerbs.contains("POST"),
            "/api/messages/scheduled grew a write verb — live Allow is "
                + "\(scheduled.allow ?? "none"). Reopen GitHub #55."
        )

        // Neither candidate per-post editor route exists.
        for path in ["/api/messages/scheduled/probe", "/api/messages/probe/schedule"] {
            let result = try await options(path)
            XCTAssertEqual(
                result.status, 404,
                "\(path) now resolves (HTTP \(result.status), Allow: \(result.allow ?? "none")). "
                    + "A scheduled-post editor route may exist — reopen GitHub #55."
            )
        }
    }

}
