import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// The service-level half of the subscriber matrix (GitHub #40): document and
/// organization **creation** are gated before any HTTP call, while every
/// non-create path on the same services stays free.
///
/// The create-only rule is the thing worth protecting here. A gate that also
/// caught reads or edits would lock a lapsed subscriber out of content they
/// already own, which the published matrix explicitly promises it will not do.
final class SubscriberCreateGateTests: XCTestCase {

    private func free() -> @Sendable () -> EntitlementsService {
        { EntitlementsService(customerStatus: .free) }
    }

    private func subscriber() -> @Sendable () -> EntitlementsService {
        { EntitlementsService(customerStatus: .subscriber) }
    }

    // MARK: - Documents: happy path

    func test_givenSubscriber_whenCreatingDocument_thenProceedsToAPI() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.documentEnvelope(id: "d-new", title: "New", content: "Body"))
        let service = DocumentsService(api: api, entitlementsProvider: subscriber())

        // When
        let doc = try await service.create(title: "New", body: "Body", folderId: nil, isPublic: false)

        // Then
        XCTAssertEqual(doc.id, "d-new")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/documents")
    }

    // MARK: - Documents: invalid state (free account)

    func test_givenFreeAccount_whenCreatingDocument_thenThrowsBeforeAnyAPICall() async throws {
        // Given
        let api = StubAPIClient()
        let service = DocumentsService(api: api, entitlementsProvider: free())

        // When / Then — the client predicts the server's 403.
        do {
            _ = try await service.create(title: "New", body: "Body", folderId: nil, isPublic: false)
            XCTFail("Expected DocumentsError.subscriberRequired(.documentCreation)")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .subscriberRequired(.documentCreation))
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "A predicted denial must not hit the network.")
    }

    // MARK: - Documents: boundary — the lapsed subscriber

    /// The promise in `/help/settings`: "your existing lists, documents, and
    /// organizations stay fully usable: you can still read and edit them."
    func test_givenFreeAccount_whenReadingAndEditingExistingDocument_thenUngated() async throws {
        // Given — a lapsed account acting on content it already owns.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.documentEnvelope(id: "d-1", title: "Existing", content: "Body"))
        await api.enqueue(json: Fixtures.documentEnvelope(id: "d-1", title: "Edited", content: "Body"))
        let service = DocumentsService(api: api, entitlementsProvider: free())

        // When — a read, then an edit.
        let read = try await service.document(id: "d-1")
        let edited = try await service.update(
            id: "d-1", title: "Edited", body: nil, folderId: nil, isPublic: nil
        )

        // Then — both went through.
        XCTAssertEqual(read.id, "d-1")
        XCTAssertEqual(edited.title, "Edited")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.count, 2)
    }

    // MARK: - Documents: upstream failure still surfaces

    func test_givenSubscriberAndServerRejection_whenCreatingDocument_thenAPIErrorSurfacesUnchanged() async throws {
        // Given — the gate is open, so a genuine server failure must reach the
        // caller unchanged rather than being masked as an entitlement problem.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "title required"))
        let service = DocumentsService(api: api, entitlementsProvider: subscriber())

        // When / Then
        do {
            _ = try await service.create(title: "", body: "", folderId: nil, isPublic: false)
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "title required"))
        }
    }

    // MARK: - Organizations: happy path

    func test_givenSubscriber_whenCreatingOrganization_thenProceedsToAPI() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.organizationEnvelope(id: "o-new", name: "Acme", isPublic: false))
        let service = OrgService(api: api, entitlements: subscriber())

        // When
        let org = try await service.create(name: "Acme", description: "We make things", isPublic: false)

        // Then
        XCTAssertEqual(org.id, "o-new")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/organizations")
    }

    // MARK: - Organizations: invalid state (free account)

    func test_givenFreeAccount_whenCreatingOrganization_thenThrowsBeforeAnyAPICall() async throws {
        // Given
        let api = StubAPIClient()
        let service = OrgService(api: api, entitlements: free())

        // When / Then
        do {
            _ = try await service.create(name: "Acme", description: "d", isPublic: true)
            XCTFail("Expected OrgError.subscriberRequired")
        } catch let error as OrgError {
            XCTAssertEqual(error, .subscriberRequired(.organizationCreation))
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - Organizations: boundary — joining stays free

    /// `/help/settings` puts "join organizations" in the **Free** column, so
    /// reading and joining must not be caught by the creation gate.
    func test_givenFreeAccount_whenListingOrganizations_thenUngated() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedOrganizations(ids: ["o-1"]))
        let service = OrgService(api: api, entitlements: free())

        // When
        let page = try await service.organizations(isPublic: nil, userId: nil, limit: 20, offset: 0)

        // Then
        XCTAssertEqual(page.organizations.map(\.id), ["o-1"])
    }

    // MARK: - The live provider

    /// The gate is evaluated per call, not captured at construction, so a
    /// mid-session sign-in or upgrade re-gates without rebuilding the service.
    func test_givenTierChangesMidSession_whenCreatingAgain_thenGateFollowsTheNewTier() async throws {
        // Given — a provider whose answer changes between calls.
        let api = StubAPIClient()
        let isSubscriber = MutableFlag()
        let service = DocumentsService(api: api, entitlementsProvider: {
            EntitlementsService(customerStatus: isSubscriber.value ? .subscriber : .free)
        })

        // When — first attempt while free.
        do {
            _ = try await service.create(title: "N", body: "B", folderId: nil, isPublic: false)
            XCTFail("Expected DocumentsError.subscriberRequired(.documentCreation)")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .subscriberRequired(.documentCreation))
        }

        // And then the account subscribes.
        isSubscriber.value = true
        await api.enqueue(json: Fixtures.documentEnvelope(id: "d-new", title: "N", content: "B"))
        let doc = try await service.create(title: "N", body: "B", folderId: nil, isPublic: false)

        // Then — the second attempt goes through, with no rebuild in between.
        XCTAssertEqual(doc.id, "d-new")
    }
}

/// A trivially mutable, `Sendable` box so the provider closure above can change
/// its answer between calls.
private final class MutableFlag: @unchecked Sendable {
    var value = false
}
