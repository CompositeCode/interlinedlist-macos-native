// GatingMatrixTests
//
// Guards the entitlement matrix settled for GitHub #40 / #41 / #42 against the
// surfaces G23 (lists sharing), G24 (documents tree) and G25 (orgs + org
// LinkedIn) added *after* the capability-gate branch was written.
//
// The rule these tests exist to hold: **creation is gated; managing, moving and
// leaving what you already have is free.** Two failure directions matter
// equally, so both are asserted throughout —
//
//   • a gated action must be refused *before* the HTTP call (a client that lets
//     the request through turns a explainable refusal into a bare 403), and
//   • a free action must NOT be refused, because the historical bug here was a
//     single over-broad seam: `requireListManagement()` once guarded all 24
//     `ListsService` write methods including pure reads, and tightening it would
//     have stopped free users reading their own lists.
//
// The "no HTTP call was made" assertion is the load-bearing one. Asserting only
// that an error was thrown would pass even if the gate ran after the round-trip.

import XCTest
@testable import InterlinedDomain

final class GatingMatrixTests: XCTestCase {

    private func free() -> EntitlementsService { EntitlementsService(customerStatus: .free) }
    private func subscriber() -> EntitlementsService { EntitlementsService(customerStatus: .subscriber) }

    // MARK: - Lists · addWatcher is `sharingWithPeople`, not list creation

    func test_givenFreeAccount_whenAddingAWatcher_thenRefusesBeforeAnyHTTPCall() async throws {
        let api = StubAPIClient()
        let service = ListsService(api: api, entitlements: free())

        do {
            try await service.addWatcher(listId: "l-1", userId: "u-2", role: .viewer, notify: false)
            XCTFail("Expected ListsError.subscriberRequired")
        } catch let error as ListsError {
            XCTAssertEqual(error, .subscriberRequired)
        }

        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "the gate must run before the HTTP call, not after the 403")
    }

    func test_givenSubscriber_whenAddingAWatcher_thenTheRequestIsSent() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"message":"ok"}"#)
        let service = ListsService(api: api, entitlements: subscriber())

        try await service.addWatcher(listId: "l-1", userId: "u-2", role: .viewer, notify: false)

        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1)
    }

    func test_givenFreeAccountAndBlankUserId_whenAddingAWatcher_thenReportsTheInvalidInputNotTheEntitlement() async throws {
        // Ordering matters for the message the user sees: a blank recipient is
        // wrong regardless of tier, and telling a free user to subscribe in
        // order to fix a typo would be actively misleading.
        let api = StubAPIClient()
        let service = ListsService(api: api, entitlements: free())

        do {
            try await service.addWatcher(listId: "l-1", userId: "   ", role: .viewer, notify: false)
            XCTFail("Expected ListsError.invalidWatcher")
        } catch let error as ListsError {
            XCTAssertEqual(error, .invalidWatcher)
        }

        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - Lists · reads stay free (the 24-call-site regression guard)

    func test_givenFreeAccount_whenListingWatchedLists_thenItIsNotGated() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.watchingEnvelope([(id: "l-1", role: "watcher")]))
        let service = ListsService(api: api, entitlements: free())

        let page = try await service.watching(limit: 50, offset: 0)

        XCTAssertEqual(page.lists.map(\.id), ["l-1"])
    }

    func test_givenFreeAccount_whenReadingContributors_thenItIsNotGated() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"contributors":[]}"#)
        let service = ListsService(api: api, entitlements: free())

        let contributors = try await service.contributors(of: "l-1")

        XCTAssertTrue(contributors.isEmpty)
    }

    func test_givenFreeAccount_whenListingWatcherCandidates_thenItIsNotGated() async throws {
        // Listing who *could* be added is a read; the gate belongs on the action
        // that actually shares the list.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"users":[]}"#)
        let service = ListsService(api: api, entitlements: free())

        let candidates = try await service.watcherCandidates(of: "l-1", search: nil, limit: 20)

        XCTAssertTrue(candidates.isEmpty)
    }

    // MARK: - Documents · creation gated, moving free

    func test_givenFreeAccount_whenCreatingADocument_thenRefusesWithTheCreationFeature() async throws {
        let api = StubAPIClient()
        let service = DocumentsService(api: api, entitlementsProvider: { EntitlementsService(customerStatus: .free) })

        do {
            _ = try await service.create(title: "N", body: "B", folderId: nil, isPublic: false)
            XCTFail("Expected DocumentsError.subscriberRequired(.documentCreation)")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .subscriberRequired(.documentCreation))
        }

        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenFreeAccount_whenMovingADocument_thenItIsNotGated() async throws {
        // A lapsed subscriber keeps existing content "fully usable" — moving is
        // reorganising what you already have, not creating something new.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.documentEnvelope(id: "d-1", title: "N", content: "B"))
        let service = DocumentsService(api: api, entitlementsProvider: { EntitlementsService(customerStatus: .free) })

        let moved = try await service.moveDocument(id: "d-1", toFolder: "f-2")

        XCTAssertEqual(moved.id, "d-1")
    }

    // MARK: - Orgs · lifecycle free, LinkedIn destinations gated

    func test_givenFreeAccount_whenSyncingOrgLinkedInPages_thenRefusesBeforeAnyHTTPCall() async throws {
        // Establishing a LinkedIn company page as a publishing destination is
        // cross-posting. Leaving it free would let the org route quietly create
        // a destination the personal cross-post route refuses to create.
        let api = StubAPIClient()
        let service = OrgService(api: api, entitlements: { EntitlementsService(customerStatus: .free) })

        do {
            _ = try await service.syncLinkedInPages(of: "o-1", callerRole: .owner)
            XCTFail("Expected OrgError.subscriberRequired(.crossPosting)")
        } catch let error as OrgError {
            XCTAssertEqual(error, .subscriberRequired(.crossPosting))
        }

        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenFreeAccount_whenAssigningALinkedInPage_thenRefusesBeforeAnyHTTPCall() async throws {
        let api = StubAPIClient()
        let service = OrgService(api: api, entitlements: { EntitlementsService(customerStatus: .free) })

        do {
            try await service.assignLinkedInPage(in: "o-1", userId: "u-1", pageId: "p-1", callerRole: .owner)
            XCTFail("Expected OrgError.subscriberRequired(.crossPosting)")
        } catch let error as OrgError {
            XCTAssertEqual(error, .subscriberRequired(.crossPosting))
        }

        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenFreeAccount_whenDisconnectingOrgLinkedIn_thenItIsNotGated() async throws {
        // Deliberately ungated: a user must always be able to undo a connection,
        // including *because* their subscription lapsed. Gating this would trap
        // them in a destination they can no longer manage.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"message":"ok"}"#)
        let service = OrgService(api: api, entitlements: { EntitlementsService(customerStatus: .free) })

        try await service.disconnectLinkedIn(from: "o-1", callerRole: .owner)

        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 1, "disconnect must reach the server on every tier")
    }

    func test_givenFreeAccountAndNonManagerRole_whenSyncingPages_thenReportsTheRoleNotTheEntitlement() async throws {
        // Role is the harder gate and is checked first: telling a viewer to
        // subscribe would be wrong, since subscribing would not grant them the
        // permission they actually lack.
        let api = StubAPIClient()
        let service = OrgService(api: api, entitlements: { EntitlementsService(customerStatus: .free) })

        do {
            _ = try await service.syncLinkedInPages(of: "o-1", callerRole: .member)
            XCTFail("Expected a role refusal, not an entitlement refusal")
        } catch let error as OrgError {
            XCTAssertNotEqual(error, .subscriberRequired(.crossPosting))
        } catch {
            // A role-specific error type is equally acceptable here; what must
            // not happen is the entitlement error masking the real reason.
        }

        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - The matrix itself

    func test_givenTheFeatureEnum_thenItCarriesNoListFolderCase() {
        // List folders were removed from macOS in PR #19 and confirmed not
        // returning (GitHub #49). A gate for a feature the client does not have
        // is dead code that reads like a promise.
        XCTAssertEqual(Feature.allCases.count, 11)
        XCTAssertFalse(Feature.allCases.contains { "\($0)".contains("listFolder") })
    }

    func test_givenAFreeAccount_thenExactlyTheCreationAndReachFeaturesAreDisabled() {
        let entitlements = free()
        for feature in Feature.allCases {
            XCTAssertFalse(
                entitlements.isEnabled(feature),
                "\(feature) should require a subscription on the published matrix"
            )
        }
    }

    func test_givenASubscriber_thenEveryFeatureIsEnabled() {
        let entitlements = subscriber()
        for feature in Feature.allCases {
            XCTAssertTrue(entitlements.isEnabled(feature), "\(feature) should be enabled for a subscriber")
        }
    }
}
