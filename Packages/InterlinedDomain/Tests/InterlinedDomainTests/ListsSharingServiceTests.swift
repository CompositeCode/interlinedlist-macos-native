import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD coverage for the work-consolidation.md G23 (issue #48) surface: the
/// "lists other people gave me access to" story.
///
/// - `ListsService.watching` / `contributors` / `addWatcher` /
///   `watcherCandidates`
/// - `SharingService.sharedListRows` / `resolveListInvite`
///
/// Quartet (happy / invalid / upstream-failure / boundary) is the floor for
/// each. Envelopes come from live read-only probes on 2026-09-09 except the
/// add-watcher write, whose shapes come from `/help/api/lists`.
final class ListsSharingServiceTests: XCTestCase {

    // MARK: - watching (shared with me)

    func test_givenListsSharedWithMe_whenLoadingWatching_thenMapsOwnerRoleAndParent() async throws {
        // Given — two rows: one editable collaborator share nested under a
        // parent, one read-only watcher share at the root.
        let api = StubAPIClient()
        await api.enqueue(json: """
        {"lists":[
          \(Fixtures.watchedListObject(id: "l-1", title: "Shows", role: "collaborator", parentTitle: "The Metal")),
          \(Fixtures.watchedListObject(id: "l-2", title: "Videos", role: "watcher"))
        ],"pagination":{"total":2,"limit":50,"offset":0,"hasMore":false}}
        """)
        let service = ListsService(api: api)

        // When
        let page = try await service.watching(limit: 50, offset: 0)

        // Then
        XCTAssertEqual(page.lists.map(\.id), ["l-1", "l-2"])
        XCTAssertEqual(page.lists.map(\.role), [.collaborator, .watcher])
        XCTAssertEqual(page.lists.first?.owner?.username, "adron")
        XCTAssertEqual(page.lists.first?.owner?.displayLabel, "Adron Hall")
        XCTAssertEqual(page.lists.first?.parentTitle, "The Metal")
        XCTAssertEqual(page.lists.first?.title, "Shows")
        XCTAssertFalse(page.hasMore)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/watching")
    }

    func test_givenReadOnlyShare_whenLoadingWatching_thenCanEditIsFalse() async throws {
        // The role decides whether the rows pane offers edit affordances.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watchingEnvelope([(id: "l-1", role: "watcher")]))
        let service = ListsService(api: api)

        let page = try await service.watching(limit: 50, offset: 0)

        XCTAssertEqual(page.lists.first?.role, .watcher)
        XCTAssertFalse(page.lists.first?.canEdit ?? true)
    }

    func test_givenUnknownRoleToken_whenLoadingWatching_thenFallsBackToLeastPrivilege() async throws {
        // Invalid input from upstream: a role the client does not know must
        // never unlock editing. `.watcher` is the least-privileged role.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watchingEnvelope([(id: "l-1", role: "overlord")]))
        let service = ListsService(api: api)

        let page = try await service.watching(limit: 50, offset: 0)

        XCTAssertEqual(page.lists.first?.role, .watcher)
        XCTAssertFalse(page.lists.first?.canEdit ?? true)
    }

    func test_givenMissingRole_whenLoadingWatching_thenFallsBackToLeastPrivilege() async throws {
        // Same rule when the field is absent entirely.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watchingEnvelope([(id: "l-1", role: nil)]))
        let service = ListsService(api: api)

        let page = try await service.watching(limit: 50, offset: 0)

        XCTAssertEqual(page.lists.first?.role, .watcher)
    }

    func test_givenNothingShared_whenLoadingWatching_thenReturnsEmptyPage() async throws {
        // Boundary: zero watched lists.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watchingEnvelope([]))
        let service = ListsService(api: api)

        let page = try await service.watching(limit: 50, offset: 0)

        XCTAssertTrue(page.lists.isEmpty)
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
    }

    func test_givenMorePages_whenLoadingWatching_thenSurfacesNextOffset() async throws {
        // Pagination: `hasMore` + the offset the next call should use.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watchingEnvelope(
            [(id: "l-1", role: "watcher")],
            limit: 50,
            offset: 50,
            hasMore: true
        ))
        let service = ListsService(api: api)

        let page = try await service.watching(limit: 50, offset: 50)

        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextOffset, 100)
    }

    func test_givenWatchingAPIFailure_whenLoading_thenThrows() async throws {
        // Upstream failure: no cache fallback here by design — the owned-list
        // cache is a different slice and must not be polluted.
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = ListsService(api: api)

        do {
            _ = try await service.watching(limit: 50, offset: 0)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    func test_givenWatchedListWithUnsharedParent_whenLoading_thenParentIsLabelOnly() async throws {
        // Boundary from the issue: the `parent` projection must not imply
        // access. It maps to a title string and nothing navigable.
        let api = StubAPIClient()
        await api.enqueue(json: """
        {"lists":[\(Fixtures.watchedListObject(id: "l-1", role: "collaborator", parentTitle: "Private Parent"))],
         "pagination":{"total":1,"limit":50,"offset":0,"hasMore":false}}
        """)
        let service = ListsService(api: api)

        let page = try await service.watching(limit: 50, offset: 0)

        XCTAssertEqual(page.lists.first?.parentTitle, "Private Parent")
        // The parent id rides along on the underlying list, but nothing in
        // `WatchedList` exposes it as an openable target.
        XCTAssertEqual(page.lists.first?.list.parentID, "parent-l-1")
    }

    // MARK: - contributors

    func test_givenRankedContributors_whenLoading_thenPreservesServerOrderAndCounts() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.contributorsEnvelope([
            (id: "c-1", added: 17, edited: 17),
            (id: "c-2", added: 2, edited: 0)
        ]))
        let service = ListsService(api: api)

        let contributors = try await service.contributors(of: "l-1")

        XCTAssertEqual(contributors.map(\.id), ["c-1", "c-2"])
        XCTAssertEqual(contributors.first?.addedCount, 17)
        XCTAssertEqual(contributors.first?.editedCount, 17)
        XCTAssertEqual(contributors.first?.score, 34)
        XCTAssertEqual(contributors.first?.displayLabel, "User c-1")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/l-1/contributors")
    }

    func test_givenNoContributors_whenLoading_thenReturnsEmptyArray() async throws {
        // Boundary — verified live against a brand-new list.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.contributorsEnvelope([]))
        let service = ListsService(api: api)

        let contributors = try await service.contributors(of: "l-1")

        XCTAssertTrue(contributors.isEmpty)
    }

    func test_givenContributorsOmitCounts_whenLoading_thenDefaultsToZero() async throws {
        // Invalid/partial upstream row: counts absent. Zero beats a crash and
        // beats a nil the view has to special-case.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"contributors":[{"id":"c-1"}],"totalContributors":1}"#)
        let service = ListsService(api: api)

        let contributors = try await service.contributors(of: "l-1")

        XCTAssertEqual(contributors.first?.addedCount, 0)
        XCTAssertEqual(contributors.first?.editedCount, 0)
        XCTAssertEqual(contributors.first?.score, 0)
        XCTAssertEqual(contributors.first?.displayLabel, "Contributor")
    }

    func test_givenContributorsAPIFailure_whenLoading_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no list"))
        let service = ListsService(api: api)

        do {
            _ = try await service.contributors(of: "l-1")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "no list"))
        }
    }

    // MARK: - addWatcher

    func test_givenUserAndRole_whenAddingWatcher_thenPostsToWatchers() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.addWatcherEnvelope)
        let service = ListsService(api: api)

        try await service.addWatcher(listId: "l-1", userId: "u-9", role: .editor, notify: true)

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/lists/l-1/watchers")
    }

    func test_givenBlankUserId_whenAddingWatcher_thenThrowsBeforeCallingAPI() async throws {
        // Invalid input: an empty id would silently flip the route into its
        // self-subscribe branch and add the *caller* instead.
        let api = StubAPIClient()
        let service = ListsService(api: api)

        do {
            try await service.addWatcher(listId: "l-1", userId: "   ", role: .editor, notify: true)
            XCTFail("Expected ListsError.invalidWatcher")
        } catch let error as ListsError {
            XCTAssertEqual(error, .invalidWatcher)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "An invalid watcher must not reach the network.")
    }

    func test_givenFreeOwner_whenAddingWatcher_thenThrowsSubscriberRequired() async throws {
        // Upstream failure: the documented 403 must arrive as the domain's
        // subscriber case so the sharing UI shows an upsell.
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "Subscribe to share lists."))
        let service = ListsService(api: api)

        do {
            try await service.addWatcher(listId: "l-1", userId: "u-9", role: .editor, notify: true)
            XCTFail("Expected ListsError.subscriberRequired")
        } catch let error as ListsError {
            XCTAssertEqual(error, .subscriberRequired)
        }
    }

    func test_givenNonForbiddenFailure_whenAddingWatcher_thenSurfacesRawAPIError() async throws {
        // Boundary on the 403 projection: only 403 becomes `subscriberRequired`.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "no list"))
        let service = ListsService(api: api)

        do {
            try await service.addWatcher(listId: "l-1", userId: "u-9", role: .viewer, notify: false)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "no list"))
        }
    }

    func test_givenIdempotentReAdd_whenAddingWatcher_thenSucceedsQuietly() async throws {
        // Boundary: a re-add answers 200 with the same body and no error —
        // the route is documented as idempotent.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.addWatcherEnvelope)
        let service = ListsService(api: api)

        try await service.addWatcher(listId: "l-1", userId: "u-9", role: .viewer, notify: false)
    }

    // MARK: - watcher role wire tokens

    func test_givenWatcherRoles_whenWritten_thenUseTheDocumentedWireTokens() {
        // Regression: the enum used to emit `owner`/`editor`/`viewer`, none of
        // which the API accepts — every role write was a 400.
        XCTAssertEqual(WatcherRole.viewer.wireToken, "watcher")
        XCTAssertEqual(WatcherRole.editor.wireToken, "collaborator")
        XCTAssertEqual(WatcherRole.owner.wireToken, "manager")
        XCTAssertEqual(WatcherRole(wireToken: "manager"), .owner)
        XCTAssertEqual(WatcherRole(wireToken: "collaborator"), .editor)
        XCTAssertEqual(WatcherRole(wireToken: "watcher"), .viewer)
        // Labels match the web's vocabulary and `ShareRole.label`.
        XCTAssertEqual(WatcherRole.viewer.label, ShareRole.watcher.label)
        XCTAssertEqual(WatcherRole.editor.label, ShareRole.collaborator.label)
        XCTAssertEqual(WatcherRole.owner.label, ShareRole.manager.label)
    }

    // MARK: - watcherCandidates

    func test_givenCandidateSearch_whenSearching_thenMapsUsersAndSendsQuery() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watcherCandidatesEnvelope(["u-9", "u-10"], total: 18))
        let service = ListsService(api: api)

        let candidates = try await service.watcherCandidates(of: "l-1", search: "ada", limit: 50)

        XCTAssertEqual(candidates.map(\.id), ["u-9", "u-10"])
        XCTAssertEqual(candidates.first?.email, "u-9@example.com")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/l-1/watchers/users")
        XCTAssertEqual(recorded.first?.query["search"], "ada")
        XCTAssertEqual(recorded.first?.query["limit"], "50")
    }

    func test_givenBlankSearch_whenSearching_thenOmitsTheQueryParameter() async throws {
        // Invalid/blank input: sending `search=` would filter on an empty
        // string instead of returning the route's default page.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watcherCandidatesEnvelope([]))
        let service = ListsService(api: api)

        _ = try await service.watcherCandidates(of: "l-1", search: "   ", limit: 50)

        let recorded = await api.recorded
        XCTAssertNil(recorded.first?.query["search"])
    }

    func test_givenNoCandidates_whenSearching_thenReturnsEmptyArray() async throws {
        // Boundary: everyone matching already has access.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watcherCandidatesEnvelope([]))
        let service = ListsService(api: api)

        let candidates = try await service.watcherCandidates(of: "l-1", search: nil, limit: 50)

        XCTAssertTrue(candidates.isEmpty)
    }

    func test_givenCandidateSearchFailure_whenSearching_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "owner only"))
        let service = ListsService(api: api)

        do {
            _ = try await service.watcherCandidates(of: "l-1", search: nil, limit: 50)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "owner only"))
        }
    }

    // MARK: - sharedListRows (SharingService)

    func test_givenShareToken_whenReadingSharedRows_thenMapsRowsWithoutAuth() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedRows(ids: ["r-1", "r-2"]))
        let service = SharingService(api: api)

        let page = try await service.sharedListRows(token: "tok", limit: 100, offset: 0)

        XCTAssertEqual(page.rows.map(\.id), ["r-1", "r-2"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/shared/tok/data")
        XCTAssertEqual(recorded.first?.method, "GET")
    }

    func test_givenSharedListWithNoRows_whenReading_thenReturnsEmptyPage() async throws {
        // Boundary: an empty shared list still renders a landing.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedRows(ids: []))
        let service = SharingService(api: api)

        let page = try await service.sharedListRows(token: "tok", limit: 100, offset: 0)

        XCTAssertTrue(page.rows.isEmpty)
        XCTAssertFalse(page.hasMore)
    }

    func test_givenRevokedToken_whenReadingSharedRows_thenThrowsNotFound() async throws {
        // Upstream failure, verified live: unknown / expired / revoked are one
        // indistinguishable 404.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "Share link not found, expired, or revoked"))
        let service = SharingService(api: api)

        do {
            _ = try await service.sharedListRows(token: "gone", limit: 100, offset: 0)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "Share link not found, expired, or revoked"))
        }
    }

    func test_givenNonSubscriber_whenReadingSharedRows_thenIsNotGated() async throws {
        // Reading a share you were given is free on every tier — an
        // entitlement-blocking service must not intercept it.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedRows(ids: ["r-1"]))
        let service = SharingService(
            api: api,
            entitlements: EntitlementsService(customerStatus: .free)
        )

        let page = try await service.sharedListRows(token: "tok", limit: 100, offset: 0)

        XCTAssertEqual(page.rows.map(\.id), ["r-1"])
    }

    // MARK: - resolveListInvite (SharingService)

    func test_givenClaimableInvite_whenResolving_thenMapsRoleTitleAndFlags() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listInviteEnvelope())
        let service = SharingService(api: api)

        let invite = try await service.resolveListInvite(token: "tok")

        XCTAssertEqual(invite.role, .collaborator)
        XCTAssertEqual(invite.resourceTitle, "Q3 Planning")
        XCTAssertTrue(invite.canClaim)
        XCTAssertFalse(invite.needsAuth)
        XCTAssertFalse(invite.wrongAccount)
        XCTAssertFalse(invite.accepted)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/lists/invite/tok")
    }

    func test_givenAnonymousResolve_whenFlagsOmitted_thenDefaultsAreConservative() async throws {
        // Boundary: an anonymous resolve returns fewer fields. Missing flags
        // must read as "not claimable / still open", never the reverse.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"role":"watcher","needsAuth":true}"#)
        let service = SharingService(api: api)

        let invite = try await service.resolveListInvite(token: "tok")

        XCTAssertEqual(invite.role, .watcher)
        XCTAssertTrue(invite.needsAuth)
        XCTAssertFalse(invite.canClaim)
        XCTAssertFalse(invite.accepted)
        XCTAssertNil(invite.resourceTitle)
    }

    func test_givenUnknownInviteRole_whenResolving_thenFallsBackToLeastPrivilege() async throws {
        // Invalid input from upstream: an unrecognised role must not imply
        // more access than the least privileged one.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.listInviteEnvelope(role: "overlord"))
        let service = SharingService(api: api)

        let invite = try await service.resolveListInvite(token: "tok")

        XCTAssertEqual(invite.role, .watcher)
    }

    func test_givenExpiredInvite_whenResolving_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "Invite not found, expired, or revoked"))
        let service = SharingService(api: api)

        do {
            _ = try await service.resolveListInvite(token: "gone")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "Invite not found, expired, or revoked"))
        }
    }
}
